# static-webhost

Helm chart for hosting static sites at GEWIS. Each release pairs a Caddy web
server with an in-browser code-server editor, sharing an RWX volume so files
can be edited live.

## What gets deployed

- `PersistentVolumeClaim` — RWX, size from `storage.size`, cluster default storage class.
- `Deployment` + `Service` — Caddy serving the volume at `/srv` (read-only).
- `Deployment` + `Service` — code-server mounting the same volume read-write.
- `IngressRoute` (Traefik) — every entry in `domains` routes to Caddy.
  The first domain additionally exposes `/admin` → code-server, gated by OIDC.
- `Middleware` ×2 — `traefik-oidc-auth` and `stripPrefix /admin`.
- `Secret oidc-secret` — empty shell annotated for reflection from
  `shared-secrets/oidc-auth` by the emberstack reflector.

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
      version: 0.1.0
      sourceRef:
        kind: HelmRepository
        name: gewis-webhost
        namespace: flux-system
  values:
    storage:
      size: 20Gi
    domains:
      - myapp.gewis.nl
    oidc:
      groups:
        - CBC - Application Hosting Team (ADM)
```

By convention, target namespaces are `webhost-<release>`; the chart no longer
enforces this so `targetNamespace` is yours to set.

## Standalone helm install

```sh
helm repo add gewis-webhost https://gewis.github.io/webhost-helm-chart
helm install myapp gewis-webhost/static-webhost \
  --create-namespace --namespace webhost-myapp \
  --set 'domains={myapp.gewis.nl}'
```

## Key values

| Key | Description | Default |
| --- | --- | --- |
| `storage.size` | Size of the shared RWX volume | `10Gi` |
| `domains` | List of hosts routed to Caddy; first also serves `/admin` (code-server) | `[example.gewis.nl]` |
| `oidc.groups` | Group names allowed through the OIDC middleware | `[CBC - Application Hosting Team (ADM)]` |
| `oidc.provider.url` | OIDC issuer URL | GEWISWG realm |
| `oidc.secretReflectsFrom` | Source for the reflected OIDC secret | `shared-secrets/oidc-auth` |
| `codeServer.image` / `caddy.image` | Container images | upstream `latest` / `2-alpine` |

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
helm template demo . --set 'domains={demo.gewis.nl}'
```
