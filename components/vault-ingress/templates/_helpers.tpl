{{/*
Mirror of the platform-wide estabilis metadata helpers (ADR 0003).
Duplicated identically across internal charts; keep in sync.
*/}}
{{- define "estabilis.labels" -}}
estabilis.io/component: {{ .Chart.Name }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: estabilis-platform
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "estabilis.annotations" -}}
estabilis.io/platform: "Estabilis Platform"
estabilis.io/chart-version: {{ .Chart.Version | quote }}
estabilis.io/website: "https://estabilis.com"
estabilis.io/source: "https://github.com/Estabilis/estabilis-platform"
estabilis.io/support: "ops@estabilis.com"
estabilis.io/license: "proprietary"
{{- if and .Values.global .Values.global.provenance .Values.global.provenance.gitRevision }}
estabilis.io/git-revision: {{ .Values.global.provenance.gitRevision | quote }}
estabilis.io/git-source: {{ .Values.global.provenance.gitSource | quote }}
estabilis.io/built-at: {{ .Values.global.provenance.builtAt | quote }}
estabilis.io/build-id: {{ .Values.global.provenance.buildId | quote }}
{{- end }}
{{- end -}}

{{- define "estabilis.metadata" -}}
labels:
  {{- include "estabilis.labels" . | nindent 2 }}
annotations:
  {{- include "estabilis.annotations" . | nindent 2 }}
{{- end -}}
