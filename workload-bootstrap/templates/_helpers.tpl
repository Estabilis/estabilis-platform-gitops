{{/*
  Estabilis branding labels — selectable identifiers for resources
  rendered by this chart. Follows the v0.1.36 convention from
  estabilis-platform.
*/}}
{{- define "estabilis.labels" -}}
estabilis.io/component: {{ .Chart.Name }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: estabilis-platform
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
  Estabilis branding annotations — non-selectable provenance metadata.
*/}}
{{- define "estabilis.annotations" -}}
estabilis.io/platform: "Estabilis Platform"
estabilis.io/chart-version: {{ .Chart.Version | quote }}
estabilis.io/website: "https://estabilis.com"
estabilis.io/source: "https://github.com/Estabilis/estabilis-platform-gitops"
estabilis.io/support: "ops@estabilis.com"
estabilis.io/license: "proprietary"
{{- end -}}

{{/*
  Combined labels + annotations block (convenience). Inline into metadata:
    metadata:
      name: foo
      {{- include "estabilis.metadata" . | nindent 2 }}
*/}}
{{- define "estabilis.metadata" -}}
labels:
  {{- include "estabilis.labels" . | nindent 2 }}
annotations:
  {{- include "estabilis.annotations" . | nindent 2 }}
{{- end -}}
