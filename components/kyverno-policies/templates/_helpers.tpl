{{/*
List of platform namespaces excluded from policy evaluation.
Used as building block by the exclude helpers below.
Do NOT call directly in policy templates — use the full exclude helpers.
*/}}
{{- define "kyverno-policies.excluded-namespace-list" }}
                - argocd
                - aws-load-balancer-controller
                - cert-manager
                - cnpg-system
                - external-dns
                - external-secrets
                - grafana
                - karpenter
                - kube-node-lease
                - kube-public
                - kube-state-metrics
                - kube-system
                - kyverno
                - metrics-server
                - node-exporter
                - vault
                - opencost
                - traefik
                - trivy-system
                - velero
                - estabilis-system
                - policy-reporter
{{- end }}

{{/*
Exclude block for policies matching namespaced resources (Pod, Deployment, etc).
Filters by the namespace where the resource lives.
*/}}
{{- define "kyverno-policies.platform-exclude" }}
      exclude:
        any:
          - resources:
              namespaces:
{{- include "kyverno-policies.excluded-namespace-list" . }}
{{- end }}

{{/*
Exclude block for policies matching Namespace-kind resources (cluster-scoped).
Uses "names" instead of "namespaces" because Namespace resources
are cluster-scoped and don't have a namespace field.
*/}}
{{- define "kyverno-policies.platform-exclude-namespaces" }}
      exclude:
        any:
          - resources:
              names:
{{- include "kyverno-policies.excluded-namespace-list" . }}
{{- end }}

{{/*
Match block for policies targeting platform namespaces (namespaced resources).
Inverse of the exclude — used by mutation policies that apply TO platform.
*/}}
{{- define "kyverno-policies.platform-namespace-match" }}
              namespaces:
{{- include "kyverno-policies.excluded-namespace-list" . }}
{{- end }}

{{/*
Match block for platform namespace names (cluster-scoped resources like Namespace).
*/}}
{{- define "kyverno-policies.platform-namespace-names-match" }}
              names:
{{- include "kyverno-policies.excluded-namespace-list" . }}
{{- end }}

{{/*
Estabilis Platform — standard metadata helpers.

These defines are duplicated identically across every internal chart in the
platform (Option 2 from estabilis-platform-tools issue #45). Keep them in
sync — if you change one, run `git grep -A 8 "define \"estabilis.labels\""`
across core/components and apply the same edit everywhere.
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
{{- include "estabilis.provenanceAnnotations" . }}
{{- end -}}

{{/*
ADR 0005 Phase 2b — supply-chain L1 provenance annotations, populated
from global.provenance.* at render time. The CLI sets these values via
helm.parameters propagated from platform-root
(see platform-root.provenanceParameters). The three-level guard keeps
helm template standalone-renderable when the values are absent.
*/}}
{{- define "estabilis.provenanceAnnotations" -}}
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
