{{/*
Expand the name of the chart.
*/}}
{{- define "static-webhost.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified app name.
*/}}
{{- define "static-webhost.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Chart label.
*/}}
{{- define "static-webhost.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "static-webhost.labels" -}}
helm.sh/chart: {{ include "static-webhost.chart" . }}
{{ include "static-webhost.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "static-webhost.selectorLabels" -}}
app.kubernetes.io/name: {{ include "static-webhost.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Component-scoped selector labels (used by per-component Deployments/Services).
Call with: (dict "Context" . "Component" "code-server")
*/}}
{{- define "static-webhost.componentSelectorLabels" -}}
{{ include "static-webhost.selectorLabels" .Context }}
app.kubernetes.io/component: {{ .Component }}
{{- end }}

{{/*
Per-group code-server resource name.
Call with: (dict "Context" $ "Group" $g.name)
*/}}
{{- define "static-webhost.codeServerName" -}}
{{- printf "%s-cs-%s" (include "static-webhost.fullname" .Context) .Group | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Per-group code-server selector labels.
Call with: (dict "Context" $ "Group" $g.name)
*/}}
{{- define "static-webhost.codeServerSelectorLabels" -}}
{{ include "static-webhost.selectorLabels" .Context }}
app.kubernetes.io/component: code-server
webhost.gewis.nl/group: {{ .Group }}
{{- end }}

{{/*
Sanitize a hostname into a Caddy named-matcher token (alnum + underscore).
*/}}
{{- define "static-webhost.matcher" -}}
{{- regexReplaceAll "[^a-zA-Z0-9]" . "_" }}
{{- end }}
