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
{{- /*
  ADR 0005 L1 provenance annotations — DISABLED due to ArgoCD bug #20477.
  https://github.com/argoproj/argo-cd/issues/20477

  managedNamespaceMetadata does NOT respect ignoreDifferences. These
  temporal annotations (built-at, git-revision) change on every promote,
  causing ALL Applications to show OutOfSync permanently. Confirmed in
  ArgoCD v3.3.2.

  DO NOT UNCOMMENT until the upstream bug is fixed. Track the issue.

  {{- if and .Values.global .Values.global.provenance .Values.global.provenance.gitRevision }}
  estabilis.io/git-revision: {{ .Values.global.provenance.gitRevision | quote }}
  estabilis.io/git-source: {{ .Values.global.provenance.gitSource | quote }}
  estabilis.io/built-at: {{ .Values.global.provenance.builtAt | quote }}
  estabilis.io/build-id: {{ .Values.global.provenance.buildId | quote }}
  {{- end }}
*/ -}}
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
  Privileged namespace metadata — for components that require host access
  (hostNetwork, hostPID, hostPath). Used by node-exporter.
  Mirrors `platform-root.managedNamespaceMetadataExcludedPrivileged`.
*/}}
{{- define "workload-bootstrap.managedNamespaceMetadataPrivileged" -}}
managedNamespaceMetadata:
  labels:
    estabilis.io/managed-by: workload-bootstrap
    kyverno.io/exclude: "true"
    pod-security.kubernetes.io/enforce: privileged
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

{{/*
Override helpers — allow downstream config repos to customize component
values per cluster/environment. Mirrors the platform-root override
pattern (see estabilis-platform/bootstrap/platform-root/templates/_helpers.tpl).

When configRepoUrl AND configRepoVersion are set in workload-bootstrap
values.yaml, each ApplicationSet template gains:
  - A third source ($overrides) pointing at the config repo
  - An extra valueFile path reading from $overrides/overrides/{component}/values.yaml
  - ignoreMissingValueFiles: true so missing override files are not errors

Without both values set, all three helpers render nothing (no-op) and
the ApplicationSets work exactly as before.
*/}}

{{/*
Ref resolver helpers — resolve the effective git ref (branch or tag)
for each repo, preferring the new *Revision values over the legacy
*Version values. Adopted in v0.31.0 per ADR 0020 (GitOps-native
continuous reconciliation) to allow consumers to track branches
(main / release/<env>) instead of pinning tags for own-content repos.

Both the legacy (configRepoVersion / clientGitopsRepoVersion) and the
new (configRepoRevision / clientGitopsRepoRevision) values are
accepted. When both are set, the *Revision wins. When neither is set
but the corresponding URL is configured, the helper fails loudly.

Migration path for existing consumers:
  - No action required: continue setting the legacy *Version value.
  - To adopt branch tracking: unset *Version, set *Revision to a branch
    name (e.g. "main") or tag.
*/}}

{{- define "workload-bootstrap.configRepoRef" -}}
{{- if .Values.configRepoRevision -}}
{{- .Values.configRepoRevision -}}
{{- else if .Values.configRepoVersion -}}
{{- .Values.configRepoVersion -}}
{{- end -}}
{{- end -}}

{{- define "workload-bootstrap.configRepoRefRequired" -}}
{{- $ref := include "workload-bootstrap.configRepoRef" . -}}
{{- if not $ref -}}
{{- fail "configRepoRevision (or legacy configRepoVersion) is required when configRepoUrl is set" -}}
{{- end -}}
{{- $ref -}}
{{- end -}}

{{- define "workload-bootstrap.clientGitopsRef" -}}
{{- if .Values.clientGitopsRepoRevision -}}
{{- .Values.clientGitopsRepoRevision -}}
{{- else if .Values.clientGitopsRepoVersion -}}
{{- .Values.clientGitopsRepoVersion -}}
{{- end -}}
{{- end -}}

{{- define "workload-bootstrap.clientGitopsRefRequired" -}}
{{- $ref := include "workload-bootstrap.clientGitopsRef" . -}}
{{- if not $ref -}}
{{- fail "clientGitopsRepoRevision (or legacy clientGitopsRepoVersion) is required when clientGitopsRepoUrl is set" -}}
{{- end -}}
{{- $ref -}}
{{- end -}}

{{- define "workload-bootstrap.overrideEnabled" -}}
{{- and .Values.configRepoUrl (include "workload-bootstrap.configRepoRef" .) -}}
{{- end -}}

{{- define "workload-bootstrap.overrideSource" -}}
{{- if include "workload-bootstrap.overrideEnabled" . }}
- repoURL: {{ .Values.configRepoUrl }}
  targetRevision: {{ include "workload-bootstrap.configRepoRefRequired" . }}
  ref: overrides
{{- end }}
{{- end -}}

{{- define "workload-bootstrap.overrideValueFile" -}}
{{- if include "workload-bootstrap.overrideEnabled" .root }}
- $overrides/overrides/{{ .component }}/values.yaml
{{- end }}
{{- end -}}

{{- define "workload-bootstrap.ignoreMissingValueFiles" -}}
{{- if include "workload-bootstrap.overrideEnabled" . }}
ignoreMissingValueFiles: true
{{- end }}
{{- end -}}

{{/*
Client GitOps override helpers (ADR 0008 Tier 3).
*/}}

{{- define "workload-bootstrap.gitopsSource" -}}
{{- if and .Values.clientGitopsRepoUrl .Values.deploymentId }}
- repoURL: {{ .Values.clientGitopsRepoUrl }}
  targetRevision: {{ include "workload-bootstrap.clientGitopsRefRequired" . }}
  ref: gitops
{{- end }}
{{- end -}}

{{- define "workload-bootstrap.gitopsValueFile" -}}
{{- if and .root.Values.clientGitopsRepoUrl .root.Values.deploymentId }}
- $gitops/platforms/{{ .root.Values.deploymentId }}/workload-overrides/{{ .component }}/values.yaml
{{- end }}
{{- end -}}

{{- /*
  Scheduling helpers — renders tolerations + nodeAffinity for charts so
  workloads tolerate Spot node taints and optionally express preference
  for a pool (regular / spot / auto).

  Mirrors the helpers in estabilis-platform/bootstrap/platform-root.
  ADR 0012 (tracked in Estabilis/estabilis-platform-tools#97).

  Input: .mode — one of {auto, regular-only, spot-only}. Default: auto.

  These helpers are rendered at workload-bootstrap time. Consumed via
  helm.valuesObject in each Application template below, which gets
  rendered once per workload cluster by the clusters generator.
*/ -}}

{{- define "workload-bootstrap.schedulingTolerations" -}}
- key: "kubernetes.azure.com/scalesetpriority"
  operator: "Equal"
  value: "spot"
  effect: "NoSchedule"
{{- end -}}

{{- define "workload-bootstrap.schedulingAffinity" -}}
{{- $mode := default "auto" .mode -}}
nodeAffinity:
{{- if eq $mode "auto" }}
  preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 50
      preference:
        matchExpressions:
          - key: estabilis.io/schedulable
            operator: In
            values: ["regular"]
{{- else if eq $mode "regular-only" }}
  requiredDuringSchedulingIgnoredDuringExecution:
    nodeSelectorTerms:
      - matchExpressions:
          - key: estabilis.io/schedulable
            operator: In
            values: ["regular"]
{{- else if eq $mode "spot-only" }}
  requiredDuringSchedulingIgnoredDuringExecution:
    nodeSelectorTerms:
      - matchExpressions:
          - key: estabilis.io/schedulable
            operator: In
            values: ["spot"]
{{- end }}
{{- end -}}

{{- define "workload-bootstrap.schedulingValuesFor" -}}
{{- $mode := default "auto" .mode -}}
{{- $tolerations := include "workload-bootstrap.schedulingTolerations" . -}}
{{- $affinity := include "workload-bootstrap.schedulingAffinity" (dict "mode" $mode) -}}
{{- range $comp := .paths }}
{{ $comp }}:
  tolerations:
    {{- $tolerations | nindent 4 }}
  affinity:
    {{- $affinity | nindent 4 }}
{{- end -}}
{{- end -}}

{{- define "workload-bootstrap.schedulingValuesTopLevel" -}}
{{- $mode := default "auto" .mode -}}
tolerations:
  {{- include "workload-bootstrap.schedulingTolerations" . | nindent 2 }}
affinity:
  {{- include "workload-bootstrap.schedulingAffinity" (dict "mode" $mode) | nindent 2 }}
{{- end -}}

{{- define "workload-bootstrap.schedulingTolerationsOnly" -}}
tolerations:
  {{- include "workload-bootstrap.schedulingTolerations" . | nindent 2 }}
{{- end -}}
