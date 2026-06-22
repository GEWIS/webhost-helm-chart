# static-webhost

Helm chart for hosting sites at GEWIS. A release serves many sites from a two-level
`domainGroups → domains` model on one shared RWX volume: one FrankenPHP (Caddy with
embedded PHP) web server serves every domain from its own folder, and each domain group
gets its own in-browser code-server editor. Static files and PHP are both served.

## Model

```
domainGroups:
  - name: board                 # editor + OIDC allow-list scope; folder name
    domains: [board.gewis.nl, bestuur.gewis.nl]
  - name: cie
    domains: [cie.gewis.nl]
```

On the shared volume this becomes `site/<group>/<domain>/`. Each domain serves its own
folder; `/admin` on **every** domain opens that group's editor (which sees only its
group's per-domain subfolders). Removing a domain archives its folder to
`site/.archive/`; removing a whole group leaves its folder orphaned (data kept, unserved).

## What gets deployed

- `PersistentVolumeClaim` — RWX, size from `storage.size`; holds the `site/<group>/<domain>/`
  tree plus `.state/` (chart markers) and `.archive/`.
- `Deployment` + `Service` (caddy) — FrankenPHP, `caddy.replicas` (default 3), read-only;
  each domain is routed to its own root `site/<group>/<domain>` and its PHP is confined to
  that folder via `open_basedir`.
- `Deployment` + `Service` **per domain group** — code-server editing only that group's
  folder (subPath mount); non-root, read-only rootfs, DNS-only egress. A root `seed-site`
  init container seeds/archives/`chown`s the group's subtree before the editor starts.
- `Job` — installs `codeServer.extensions` (from Open VSX) plus, when `codeServer.phpantom.enabled`,
  the PHPantom PHP language server (`.vsix` + prebuilt binary) onto the shared volume, and re-runs
  when any of that changes; the only component allowed egress to fetch them. Shared by all editors.
- `NetworkPolicy` — denies code-server egress except DNS. Requires a CNI that enforces it.
- `IngressRoute` (Traefik) — every domain routes to Caddy; `/admin` on every domain routes
  to that group's code-server, gated by OIDC.
- `Middleware` — `traefik-oidc-auth` **per group** plus shared `redirect` + `stripPrefix /admin`.
- `Secret oidc-secret` — empty shell annotated for reflection from
  `shared-secrets/oidc-auth` by the emberstack reflector.

## Security posture

code-server is the only interactive surface, so it is locked down: non-root, read-only
root filesystem, all capabilities dropped, no service-account token, and DNS-only egress
(`networkPolicy.enabled`). The integrated terminal is enabled — safe because egress is
blocked, the rootfs is read-only, and nothing sensitive is mounted. Extensions are
pre-installed read-only and the marketplace is disabled, so the editor runs only what the
chart ships. User `settings.json` is seeded from the chart on each start; in-session edits
are allowed but reset to the chart defaults on every pod restart.

Group isolation has two layers: each group's editor is mount-isolated (it only mounts
its own `site/<group>` subPath), and each domain's PHP is confined to its own folder via
`open_basedir`. The latter is defense-in-depth, not a hard boundary — one shared FrankenPHP
process serves all groups, so do not treat it as isolation between mutually-untrusted tenants.
Because the web tier is multi-replica with per-pod `/tmp`, PHP sessions/uploads (default
`/tmp`) are not shared across replicas; sites relying on PHP sessions need sticky sessions
or shared session storage.

## Install via Flux

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: gewis-webhost
  namespace: flux-system
spec:
  interval: 10m
  url: https://gewis.github.io/webhost-helm-chart
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: myapp
  namespace: flux-system
spec:
  interval: 10m
  releaseName: myapp
  targetNamespace: webhost-myapp
  install:
    createNamespace: true
  chart:
    spec:
      chart: static-webhost
      version: 0.6.0
      sourceRef:
        kind: HelmRepository
        name: gewis-webhost
        namespace: flux-system
  values:
    storage:
      size: 20Gi
    domainGroups:
      - name: myapp
        domains:
          - myapp.gewis.nl
        oidc:
          groups:
            - "GEWIS - Some Committee"
```

`"CBC - Application Hosting Team (ADM)"` always has editor access; per-group
`oidc.groups` are additionally allowed in for that group.

By convention, target namespaces are `webhost-<release>`; the chart no longer
enforces this so `targetNamespace` is yours to set.

## Standalone helm install

```sh
helm repo add gewis-webhost https://gewis.github.io/webhost-helm-chart
helm install myapp gewis-webhost/static-webhost \
  --create-namespace --namespace webhost-myapp \
  --set 'domainGroups[0].name=myapp' \
  --set 'domainGroups[0].domains={myapp.gewis.nl}'
```

## Key values

| Key | Description | Default |
| --- | --- | --- |
| `storage.size` | Size of the shared RWX volume | `10Gi` |
| `domainGroups` | List of `{name, domains[], oidc.groups[]}`; one editor per group, each domain served from `site/<group>/<domain>` | `[{name: example, domains: [example.gewis.nl]}]` |
| `domainGroups[].oidc.groups` | Extra OIDC groups allowed into that group's `/admin` (ADM always allowed) | `[]` |
| `oidc.provider.url` | OIDC issuer URL | GEWISWG realm |
| `oidc.secretReflectsFrom` | Source for the reflected OIDC secret | `shared-secrets/oidc-auth` |
| `caddy.replicas` | FrankenPHP web-server replica count | `3` |
| `codeServer.image` | code-server editor image | `codercom/code-server:4.125.0` |
| `caddy.image` | Web server image (FrankenPHP = Caddy + PHP) | `dunglas/frankenphp:1-php8.5-alpine` |
| `networkPolicy.enabled` | Restrict code-server egress to DNS only | `true` |

See [`values.yaml`](./values.yaml) for the full schema.

## Releasing

The `release-chart` workflow publishes to `gh-pages` whenever a new chart
version is pushed to `main`. To cut a release:

1. Edit templates/values as needed.
2. Bump `version:` in `Chart.yaml` (semver).
3. Merge to `main`. CI packages the chart and updates the Helm repo index.

If the version on `main` is already in `index.yaml`, the workflow skips
publishing — no clobbering of existing releases.

## Local development

A Nix flake provides Helm:

```sh
nix develop
helm lint .
helm template demo . \
  --set 'domainGroups[0].name=demo' \
  --set 'domainGroups[0].domains={demo.gewis.nl}'
```
