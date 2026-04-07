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
estabilis.io/platform-version: {{ .Chart.Version | quote }}
estabilis.io/website: "https://estabilis.com"
estabilis.io/source: "https://github.com/Estabilis/estabilis-platform-gitops"
estabilis.io/support: "ops@estabilis.com"
estabilis.io/license: "proprietary"
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
