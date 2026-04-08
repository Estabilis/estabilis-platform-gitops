{{/*
  Estabilis branding annotations — applied to namespaces on workload clusters
  via ArgoCD managedNamespaceMetadata. Mirrors
  estabilis-platform/bootstrap/platform-root/templates/_helpers.tpl →
  `platform-root.estabilisNamespaceAnnotations` so operators see identical
  provenance on hub and workload clusters.

  See: estabilis-platform-tools issue #45.
*/}}
{{- define "workload-bootstrap.estabilisNamespaceAnnotations" -}}
estabilis.io/platform: "Estabilis Platform"
estabilis.io/platform-version: {{ .Values.platformVersion | quote }}
estabilis.io/workload-bootstrap-version: {{ .Chart.Version | quote }}
estabilis.io/website: "https://estabilis.com"
estabilis.io/source: "https://github.com/Estabilis/estabilis-platform-gitops"
estabilis.io/support: "ops@estabilis.com"
estabilis.io/license: "proprietary"
{{- if and .Values.global .Values.global.provenance .Values.global.provenance.gitRevision }}
estabilis.io/git-revision: {{ .Values.global.provenance.gitRevision | quote }}
estabilis.io/git-source: {{ .Values.global.provenance.gitSource | quote }}
estabilis.io/built-at: {{ .Values.global.provenance.builtAt | quote }}
estabilis.io/build-id: {{ .Values.global.provenance.buildId | quote }}
{{- end }}
{{- end -}}

{{/*
  Standard namespace metadata — PSA baseline enforcement + platform label.
  Used by all Applications rendered by the workload-bootstrap ApplicationSet
  (CreateNamespace=true). Mirrors
  `platform-root.managedNamespaceMetadata`.
*/}}
{{- define "workload-bootstrap.managedNamespaceMetadata" -}}
managedNamespaceMetadata:
  labels:
    estabilis.io/managed-by: workload-bootstrap
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/enforce-version: latest
  annotations:
    {{- include "workload-bootstrap.estabilisNamespaceAnnotations" . | nindent 4 }}
{{- end -}}

{{/*
  ADR 0005 Phase 2b — forwards global.provenance.* from the workload-
  bootstrap chart values down into each child ApplicationSet's Helm
  render. The workload-components charts pick these up through their
  own `estabilis.provenanceAnnotations` helper (byte-identical to the
  ones in estabilis-platform/core/components/). Both helpers emit
  nothing when gitRevision is empty, so the enclosing block stays valid
  when the CLI has no git context.

  Mirrors estabilis-platform/bootstrap/platform-root/templates/_helpers.tpl
  → platform-root.provenanceParameters{,Block}.

  Two variants:

  - `provenanceParameters` — emits bare list items. Use inside a child
    ApplicationSet template that ALREADY has a `parameters:` block;
    append the include at the end so the extra entries merge in
    cleanly.

        parameters:
          - name: foo
            value: bar
          {{- include "workload-bootstrap.provenanceParameters" $ | nindent 10 }}

  - `provenanceParametersBlock` — emits a complete `parameters:` key
    wrapped in a guard so nothing is rendered when provenance is
    absent. Use inside a child ApplicationSet template that does NOT
    already have a `parameters:` block.

        helm:
          valueFiles:
            - ...
          {{- include "workload-bootstrap.provenanceParametersBlock" $ | nindent 10 }}
*/}}
{{- define "workload-bootstrap.provenanceParameters" -}}
{{- if and .Values.global .Values.global.provenance .Values.global.provenance.gitRevision }}
- name: global.provenance.gitRevision
  value: {{ .Values.global.provenance.gitRevision | quote }}
- name: global.provenance.gitSource
  value: {{ .Values.global.provenance.gitSource | quote }}
- name: global.provenance.builtAt
  value: {{ .Values.global.provenance.builtAt | quote }}
- name: global.provenance.buildId
  value: {{ .Values.global.provenance.buildId | quote }}
{{- end }}
{{- end -}}

{{- define "workload-bootstrap.provenanceParametersBlock" -}}
{{- if and .Values.global .Values.global.provenance .Values.global.provenance.gitRevision }}
parameters:
  {{- include "workload-bootstrap.provenanceParameters" . | nindent 2 }}
{{- end }}
{{- end -}}
