# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

For versions prior to the introduction of this changelog, see the
[tag history](https://github.com/Estabilis/estabilis-platform-gitops/tags)
and the corresponding commit messages.

## [Unreleased]

### Fixed

- `components/cert-manager-config`: the ExternalSecret branch of
  `cluster-issuer-cloudflare.yaml` hardcoded `remoteRef.key:
  cloudflare-api-token`. That is a flat Azure Key Vault name; on AWS the
  external-secrets IRSA role is scoped to `estabilis/<deploymentId>/*`, so a
  bare key never resolves and the branch was unusable — leaving AWS
  deployments on the direct-injection path, which writes the token in
  cleartext onto the Application spec.

  The key now comes from `kvSecrets.cloudflareApiToken`, defaulting to the
  previous literal so Azure behaviour is unchanged. `platform-root` in
  estabilis-platform >= the companion release passes the prefixed Secrets
  Manager path on AWS.

## [0.42.10] - 2026-06-08

### Fixed

- **`workload-bootstrap.repoVersion` bumped to v0.42.10** (was stuck at `v0.42.7`).
  Nested Applications read their `$values` (e.g. `values/workload/traefik.yaml`)
  from this revision, NOT from the chart's own `targetRevision`. It is a manually
  kept literal and was not bumped for 0.42.8/0.42.9, so the **v0.42.9 public-Traefik
  `ingressClass` fix never reached the workloads** (template/parameter changes
  propagate with the chart version; values-file changes propagate via `repoVersion`).
  This release makes `repoVersion` match so the Traefik fix lands. Follow-up: have
  `platform-root` pass `repoVersion = platformGitopsVersion` to remove this footgun.

## [0.42.9] - 2026-06-08

### Fixed

- **Public workload Traefik now filters by `ingressClass: traefik`.** The public
  and internal Traefik share the controller `traefik.io/ingress-controller` and
  `traefik` is the default IngressClass, so without a provider `ingressClass`
  filter the public Traefik also claimed the `traefik-internal` Ingresses and
  wrote its public LB IP into their `.status`, fighting the internal Traefik. The
  internal Ingress status (and the Azure Private DNS records published from it)
  flapped between the ILB IP and the public LB IP — internal hostnames
  intermittently resolved to the PUBLIC IP. `values/workload/traefik.yaml` now
  sets `providers.{kubernetesIngress,kubernetesCRD}.ingressClass: traefik`,
  mirroring the `traefik-internal` overlay. Only affects clusters running the
  public Traefik (e.g. brazilsouth crypto); backward-compatible.

## [0.42.8] - 2026-06-07

### Fixed

- **Base `external-dns` (public/Cloudflare) now excludes the internal split-horizon
  domain.** Added `excludeDomains[0] = bridge.internal-domain` to the base
  `external-dns` ApplicationSet parameters (mirrors `external-dns-public-dnat`,
  without `--force-default-targets`). Without it, a base-variant cluster (no
  FortiGate, e.g. brazilsouth crypto) published its `*.{internal-domain}` hosts
  into the public Cloudflare zone pointing at the ILB private IP — a leak. The
  internal hosts remain owned by `external-dns-internal` (Azure Private DNS).
  No effect on clusters whose `internal-domain` bridge key is empty.

## [0.42.7] - 2026-06-06

### Added

- **`external-dns-public-dnat` ApplicationSet** — public external-dns variant for
  workload clusters fronted by a DNAT gateway (FortiGate/NVA). Selected by the
  per-cluster gate label `estabilis.io/addon.public-dns` (stamped by
  estabilis-workload-operator >= v0.10.4 from the `public-dns-enabled` bridge
  key set by estabilis-workload >= v3.5.1). On top of the base public
  external-dns it adds `excludeDomains[0]` = the internal split-horizon domain
  (`bridge.internal-domain`) and `extraArgs` `--default-targets=<bridge.ingress-public-ip>`
  + `--force-default-targets`, so the public (Cloudflare) zone publishes the
  gateway VIP instead of the private ILB and stops leaking the `.azure` internal
  hostnames.

### Changed

- **Base `external-dns` ApplicationSet** now carries a `matchExpressions` selector
  `estabilis.io/addon.public-dns DoesNotExist`, making it mutually exclusive with
  `external-dns-public-dnat`: exactly one external-dns variant targets each
  workload cluster. Clusters without the label (incl. NAT-Gateway topology) keep
  the existing base behavior unchanged.

## [0.42.6] - 2026-06-01

### Fixed

- `kyverno-policies`: the real fix for the ClusterPolicy drift. Revert v0.42.5's
  `managedFieldsManagers` (which never matched — Kyverno applies its defaults as
  untracked object defaults, owned by no field manager) back to
  `jqPathExpressions`, AND remove `RespectIgnoreDifferences=true` from
  `syncOptions`. Root cause: `RespectIgnoreDifferences` + jqPathExpressions that
  target `.spec.rules[]` array items make ArgoCD pin the whole `.spec.rules`
  array to the live state, silently blocking every legitimate rule change (the
  v0.42.2 `excluded-namespace-list` edit never applied; policies froze and the
  apps stayed perpetually OutOfSync, on the hub too). `RespectIgnoreDifferences`
  is redundant with ServerSideApply — verified by server-side dry-run: a plain
  SSA apply lands the rule change AND preserves the Kyverno-defaulted fields
  (no churn). So `jqPathExpressions` keeps the diff display clean while SSA-only
  lets rule changes flow. The hub copy in
  `estabilis-platform/bootstrap/platform-root/templates/kyverno.yaml` gets the
  same `RespectIgnoreDifferences` removal.

## [0.42.5] - 2026-05-31

### Fixed

- `kyverno-policies`: replace the `ignoreDifferences` `jqPathExpressions` (which
  targeted `.spec.rules[]` array items) with `managedFieldsManagers: [kyverno]`.
  Combined with `RespectIgnoreDifferences=true` + ServerSideApply, the array
  jqPath expressions pinned the entire `.spec.rules` array to the live state, so
  ArgoCD silently dropped every legitimate change to the rules — the ClusterPolicies
  were frozen at `generation: 1` and the v0.42.2 `excluded-namespace-list` edit
  (and any future policy change) never applied, leaving the apps perpetually
  OutOfSync. Ignoring by field manager skips exactly what Kyverno's admission
  controller mutates without pinning the array, so our changes sync normally.
- `external-dns-internal`: pin the image by digest. The chart renders
  `repository:tag`, so `image.tag: "v0.20.0@sha256:ddc7f42…"` yields the valid
  OCI reference `…/external-dns:v0.20.0@sha256:ddc7f42…` — digest-pinned (the
  multi-arch manifest-list index, so it resolves on any node arch) and satisfying
  the `require-image-digest` policy on its own merits rather than only via the
  namespace exclusion.

## [0.42.4] - 2026-05-31

### Fixed

- `external-dns-internal`: pass the `azure.json` content via the ApplicationSet
  `helm.valuesObject` instead of a `--set-string` parameter. v0.42.3 injected
  `secretConfiguration.data.azure\.json` as a Helm parameter, but ArgoCD renders
  parameters as `--set-string`, and the JSON value (which contains commas) was
  split into a list — breaking manifest generation entirely with
  `secret.yaml ... wrong type for value; expected string; got []interface {}`,
  so the app could not sync at all. `valuesObject` is written to a values file,
  keeping `azure.json` a single string. Verified end-to-end: the pod
  authenticates via Workload Identity and creates the internal A record (e.g.
  `hubble.<cluster>.azure.<domain>` → traefik-internal ILB IP), resolvable from
  the cluster's VNet-linked Private DNS zone.

## [0.42.3] - 2026-05-31

### Fixed

- `external-dns-internal`: provision `/etc/kubernetes/azure.json` so the
  `azure-private-dns` provider can authenticate. The values used a top-level
  `azure:` block (a Bitnami-chart feature) which the kubernetes-sigs external-dns
  chart silently ignores, so no cloud config file was ever mounted and the pod
  crashed with `failed to read Azure config file '/etc/kubernetes/azure.json'`.
  Switched `values/workload/external-dns-internal.yaml` to the chart's
  `secretConfiguration` (mounted at `/etc/kubernetes`), and the
  `workload-bootstrap` ApplicationSet now injects
  `secretConfiguration.data.azure\.json` per-cluster from the bridge annotations
  (`tenant-id`, `internal-dns-subscription-id`, `internal-dns-resource-group`,
  `useWorkloadIdentityExtension: true`). Identity still comes from the federated
  SA token (Workload Identity), so no client secret is stored. Only surfaced
  once v0.42.2 unblocked the egress NetworkPolicy and the pod got past the
  Ingress informer sync.

## [0.42.2] - 2026-05-30

### Fixed

- `components/network-policies`: add an `allow-external-dns-internal` NetworkPolicy
  for the `external-dns-internal` namespace (the second, Azure Private DNS
  external-dns instance on workload clusters). The Kyverno `default-deny-all`
  policy is generated into every namespace, but this one had no companion
  allow rule, so its pod had zero egress and the Ingress informer timed out
  (`failed to sync *v1.Ingress: context deadline exceeded`) → CrashLoopBackOff,
  before it ever reached the Azure DNS API. Egress shape mirrors
  `allow-external-dns` (DNS + all-egress for the Kubernetes API / Azure
  management plane / IMDS). Gated by `policies.external-dns-internal.enabled`
  AND `components.external-dns-internal`.
- `values/platform/network-policies.yaml`: disable `policies.external-dns-internal`
  on the hub (same rationale as `alloy`) — the `external-dns-internal` namespace
  only exists on workload clusters, so rendering the policy on the hub would
  target a non-existent namespace and leave the `network-policies` App OutOfSync.
- `components/resource-quotas`: add `external-dns-internal` and `alloy` to the
  `components` + `namespaces` maps so both workload-only namespaces get a
  `ResourceQuota` + `LimitRange`. They were previously unregistered, tripping
  the Kyverno `require-resource-quotas` / `require-limit-ranges` audit policies.
  `values/platform/resource-quotas.yaml` disables both on the hub (neither
  namespace exists there — hub Alloy runs in `grafana`, internal external-dns is
  workload-only) to avoid quotas targeting non-existent namespaces.
- `components/kyverno-policies`: add `external-dns-internal` to
  `excluded-namespace-list` (`_helpers.tpl`). It is a platform-managed namespace
  running the upstream external-dns image (tag-based, no digest), so it belongs
  in the same hardening-exclusion set as `external-dns` — clearing the
  `require-image-digest` audit finding.
- `workload-bootstrap/templates/{network-policies,resource-quotas}.yaml`: gate
  `components.external-dns-internal` per-cluster from the bridge annotation
  `external-dns-internal-enabled` (mirroring `traefik-internal`) instead of
  forwarding it fleet-wide. The internal external-dns is a per-cluster opt-in, so
  its NetworkPolicy / quota must only render on clusters where the namespace
  actually exists — otherwise opted-out workload clusters would go OutOfSync.

## [0.41.3] - 2026-05-29

### Changed

- `workload-bootstrap/templates/alloy.yaml`: the Alloy loki/mimir `remote_write`
  push URLs now read the domain from the bridge annotation `hub-telemetry-domain`
  instead of `domain`. This lets the workload's Terraform pick the network path
  (internal split-horizon vs public) per environment via
  `telemetry_use_internal` (estabilis-workload >= v3.3.0); the template stays
  logic-free — it just substitutes `mimir.{hub-cluster-name}.{hub-telemetry-domain}`.
  Requires the workload to emit the `hub-telemetry-domain` annotation; a
  malformed `mimir..<domain>` previously also depended on the empty
  `hub-cluster-name`, now sourced from the hub Key Vault.

## [0.41.2] - 2026-05-29

### Fixed

- `values/workload/cert-manager.yaml`: enable DNS-01 self-check against public
  recursive nameservers on workload clusters
  (`dns01RecursiveNameservers: "1.1.1.1:53,8.8.8.8:53"`,
  `dns01RecursiveNameserversOnly: true`), mirroring `values/platform/cert-manager.yaml`.
  Internal hostnames under `*.azure.<domain>` resolve only via Azure Private DNS
  (split-horizon) and have no public A record. Without public recursive
  nameservers, cert-manager's DNS-01 propagation self-check fails with
  `Could not determine authoritative nameservers for _acme-challenge.<host>.azure.…`
  and the certificate never issues (challenge stuck `pending`). Public resolvers
  see the ACME challenge TXT in the public Cloudflare zone, so the cert issues
  while the A record stays private. The hub already had this; workload clusters
  were missing it.

## [0.41.1] - 2026-05-29

Fixes three defects in the v0.41.0 per-cluster ingress change that only surface
at ArgoCD render/apply time (`helm template`/`lint` do not catch them). Validated
live against the Transfero crypto workload cluster.

### Fixed

- **`parameters: null` on traefik / hubble-ui ApplicationSets.**
  `workload-bootstrap/templates/traefik.yaml` and `hubble-ui.yaml` had
  `parameters:` followed solely by the `provenanceParameters` include; on a
  deployment without provenance (`.Values.global.provenance.gitRevision` unset)
  the include is empty, so the applied manifest had `parameters: null`, which the
  ApplicationSet schema rejects (`must be of type array`). Both now use the
  existing `provenanceParametersBlock` helper, which omits the key entirely when
  there is no provenance. (Latent since the provenance include was added;
  surfaced by the v0.41.0 re-apply.)
- **`get` fails in goTemplate ApplicationSets.**
  `traefik-internal.yaml` read the fixed-ILB-IP annotation with
  `get .metadata.annotations "…"`. ArgoCD passes `.metadata.annotations` as
  `map[string]string`, but sprig's `get`/`dig` require `map[string]interface{}`,
  so the generator failed with `RenderTemplateParamsError: wrong type for value`
  and never produced the per-cluster Application. Switched to
  `index .metadata.annotations "…"` (the pattern already used by
  `cert-manager-config` / `hubble-ui-ingress`); `index` returns "" for an absent
  key without tripping `missingkey=error`.
- **`get` used in non-goTemplate ApplicationSets.**
  `network-policies.yaml` and `resource-quotas.yaml` are clusters-generator
  ApplicationSets that were **not** `goTemplate`, so the per-cluster
  `components.traefik` / `components.traefik-internal` values written as
  `{{ get .metadata.annotations … }}` were emitted as **literal strings** instead
  of `true`/`false`. Both are now `goTemplate: true`
  (`goTemplateOptions: ["missingkey=error"]`), their `{{name}}`/`{{server}}`
  references converted to `{{ .name }}`/`{{ .server }}`, and the traefik gates read
  via `index .metadata.annotations "…" | default "false"`.

## [0.41.0] - 2026-05-29

### Changed

- **Per-cluster ingress gating (root-cause fix).** `traefik` and `traefik-internal`
  ApplicationSets are now gated **per cluster** instead of fleet-wide. The clusters
  generator selector is extended with the operator-stamped labels
  `estabilis.io/ingress.traefik` / `estabilis.io/ingress.traefik-internal` (derived
  from the workload's `traefik_enabled` / `traefik_internal_enabled` via the bridge,
  ADR 0010), so only opted-in clusters receive each Traefik instance. The global
  `components.traefik` / `components.traefik-internal` toggles in `values.yaml` are now
  kill-switches for whether the ApplicationSet renders at all (both default `true`).
- `workload-bootstrap/templates/network-policies.yaml` and `resource-quotas.yaml`:
  the `components.traefik` / `components.traefik-internal` chart parameters are now read
  **per cluster** from the bridge annotations (`estabilis.io/bridge.traefik-enabled` /
  `traefik-internal-enabled`, `default "false"`) instead of the fleet-wide values map.
  The `traefik`-namespace NetworkPolicy/ResourceQuota only renders where ingress is
  actually deployed on that cluster — fixes the chronic OutOfSync on clusters without
  Traefik.

### Added

- `workload-bootstrap/templates/traefik-internal.yaml`: per-cluster fixed Internal
  LoadBalancer IP via `service.spec.loadBalancerIP`, read from the bridge annotation
  `estabilis.io/bridge.traefik-internal-lb-ip` (emitted by `estabilis-workload`
  `traefik_internal_lb_ip`). Absent annotation → empty value → dynamic ILB IP
  (brazilsouth/NAT-GW); set → fixed IP for the FortiGate DNAT topology (eastus2).

## [0.40.1] - 2026-05-27

### Fixed

- `workload-bootstrap/templates/traefik-internal.yaml`: use `ignoreMissingValueFiles` helper instead of inline literal (lint rule).

## [0.40.0] - 2026-05-27

### Added — `traefik`: migrate hub values + add workload traefik-internal

- **Hub traefik values migrated** from `estabilis-platform/core/components/traefik/` to `values/platform/` (traefik.yaml, traefik-azure.yaml, traefik-aws.yaml, traefik-internal.yaml). Follows the vault migration pattern — templates remain in estabilis-platform, values owned by gitops.
- **Hub traefik hardened**: image pinned to v3.4.0, securityContext (non-root, read-only FS, NET_BIND_SERVICE, seccomp RuntimeDefault), podSecurityContext (fsGroup 65532), `estabilis.io/managed-by: platform` label. Aligned with existing workload traefik baseline.
- **Workload traefik-internal**: new ApplicationSet + values for environments behind NVA (FortiGate) where only internal ingress is available. Opt-in via `components.traefik-internal: false` (default off). Same ILB + ingressClass pattern as hub traefik-internal (ADR 0014). Deploys to namespace `traefik` with `releaseName: traefik-internal` for resource isolation.

### Added — `values/platform/karpenter`: enable `NodeRepair` feature gate

Karpenter v1.x ships `NodeRepair` as a beta feature gate, default-off. With it disabled, Karpenter only acts on node lifecycle events delivered through the SQS interruption queue (spot reclaim, AZ rebalance, scheduled maintenance, instance state-change). Nodes that go unhealthy *without* an AWS-originated signal — kubelet crash, kernel deadlock, network partition, container runtime hang — are not surfaced through SQS and therefore stay tainted (`node.kubernetes.io/unreachable:NoExecute/NoSchedule`) indefinitely. Workload pods enter `Terminating` but can't finalize (no kubelet to confirm shutdown), which means the `WhenEmpty` consolidation policy never finds the node empty and never disrupts it.

Observed 2026-05-19 on a production AWS deployment: a spot node went `NotReady` (kubelet stopped heart­beating); ~25 pods stayed `Terminating` for ~52 minutes before manual intervention. NodeClaim `Ready=True` and `Consolidatable=True` throughout — Karpenter had no mechanism to act on the bad Node Conditions.

Enabling `nodeRepair: true` adds a second observation channel: Karpenter watches the Node Object's `Conditions` directly and, when any of `Ready=Unknown/False`, `KernelDeadlock=True`, `NetworkUnavailable=True`, `ContainerRuntimeNotReady=True`, or `ReadonlyFilesystem=True` persists for the per-condition threshold (~30 min, hardcoded in Karpenter v1.x), force-terminates the NodeClaim and reprovisions. NodeRepair bypasses PDBs, drain timeouts, and disruption budgets — the node is already dead, so there is nothing to protect.

| Trigger source | Before | After |
|---|---|---|
| AWS-originated (spot reclaim, AZ rebalance, scheduled events) | SQS queue → Karpenter cordon+drain ✓ | unchanged ✓ |
| Silent degradation (kubelet/runtime/network/kernel) | not detected — node tainted forever | NodeRepair force-replaces after ~30 min |
| Consolidation (empty/underutilized) | NodePool `WhenEmpty` policy ✓ | unchanged ✓ |

**Behavioral impact downstream.** AWS clusters consuming this chart will, after the platform-root promote, see Karpenter automatically replace nodes whose Conditions go bad. False-positive force-replacement of a transiently flapping node is possible but rare given the ~30 min stability window; the cost (~3 min of churn for one node) is materially less than the current failure mode (open-ended outage requiring manual `kubectl delete nodeclaim`). No-op for Azure clusters (gated on `provider == "aws"` in platform-root).

**Operator runbook.** If NodeRepair fires unexpectedly often (more than a node/day in steady state), that indicates a deeper AMI / kernel / network issue that NodeRepair would be masking — investigate `karpenter` controller logs filtered on `reason=NodeRepair` and EC2 console for the affected instance IDs before disabling the gate.

## [0.39.14] — 2026-05-18

### Fixed — `workload-bootstrap`: ADR 0029 compliance — auto-prune on Safe-class templates

Six Application/ApplicationSet templates in `workload-bootstrap/templates/` were out of compliance with [ADR 0029 — Auto-prune policy](https://github.com/Estabilis/estabilis-platform-tools/blob/main/docs/adr/0029-auto-prune-policy.md). The ADR classifies each template by risk (Safe / Coupled / CRD-owning / Foundational) and dictates whether `automated.prune: true` is appropriate.

The six templates emit only CR instances or Kubernetes-native resources (no CRDs, no operators, no cross-chart `optional: false` coupling) — they qualify as **Safe class** and should auto-prune so that gate flips and chart cleanups don't leak orphan resources cluster-wide.

| Template | Before | After |
|---|---|---|
| `hubble-ui.yaml` | `automated.selfHeal: true` only | `automated.{prune,selfHeal}: true` |
| `kube-state-metrics.yaml` | `automated.selfHeal: true` only | `automated.{prune,selfHeal}: true` |
| `kyverno-exceptions.yaml` | no `automated` block | `automated.{prune,selfHeal}: true` |
| `kyverno-policies.yaml` | no `automated` block | `automated.{prune,selfHeal}: true` |
| `network-policies.yaml` | no `automated` block | `automated.{prune,selfHeal}: true` |
| `resource-quotas.yaml` | no `automated` block | `automated.{prune,selfHeal}: true` |

The `kyverno-policies` template comment ("no automated sync — destructive changes to ClusterPolicies must be operator-initiated") predated ADR 0029 and contradicted the ADR's explicit classification of `kyverno-policies` as **Safe / Enabled** (ADR 0029 §"Platform components", line 93). Comment updated to reflect the ADR decision.

Same change applied to the `kyverno-exceptions` template comment ("no automated sync") — the template now syncs automatically with prune, consistent with the matching `client-kyverno-exceptions` template that was already on `automated.{prune,selfHeal}: true`.

**Behavioral impact downstream.** Workload clusters consuming this chart will reconcile `hubble-ui`, `kube-state-metrics`, `kyverno-exceptions`, `kyverno-policies`, `network-policies`, `resource-quotas` automatically on git pushes to the workload-bootstrap source. Orphans from removed templates or flipped gates are pruned automatically. `selfHeal: true` reverts out-of-band `kubectl patch` operations — operators with active incident debugging should be aware.

## [0.39.13] — 2026-05-17

### Fixed — `components/resource-quotas`: argocd namespace `limits.memory` 16Gi → 32Gi

The default ResourceQuota for the `argocd` namespace was sized for a single-replica control plane (~13Gi steady-state). Operators following the legacy `cortex-eks-prod` HA baseline set `controller.replicas: 2` in their downstream `overrides/argocd/values.yaml`. With a second `application-controller` pod requesting 5Gi memory, total exceeds 16Gi and the StatefulSet retries `FailedCreate` indefinitely.

The downstream symptom is silent and severe: ArgoCD enables sharding when `ARGOCD_CONTROLLER_REPLICAS=2`, the cluster is hash-assigned to shard 1, and with no `application-controller-1` pod (blocked by quota), nobody reconciles that shard. Applications freeze at their last successful sync state — observed 18h of `platform-root` `OutOfSync` on cortex HML with no error surfaced anywhere obvious; only `kubectl describe statefulset` showed the `exceeded quota` warnings, 103 retries deep.

Bumping `limits.memory` to 32Gi accommodates the HA configuration with headroom for bulk sync waves. Memory cap is cheap relative to the failure mode.

## [0.39.12] — 2026-05-15

### Fixed — `components/karpenter-resources`: memory floor (`instance-memory Gt 4096`)

Follow-up to v0.39.11. The ENI pod-density fix unblocked `*.medium` saturation, but the surviving `*.large` nodes still ran into a different ceiling: memory exhaustion as more DaemonSets joined the cluster post-provisioning.

**Root cause.** Karpenter calculates DaemonSet overhead **only at the moment of provisioning** a node. Once the node is up, adding more DaemonSets to the cluster (ESO, alloy, observability stack, …) gradually saturates the node. Karpenter does NOT revisit sizing — the NodePool spec didn't change, the node isn't `Drifted`, and the `WhenEmpty` consolidation policy doesn't replace busy nodes. The result is "node slowly tightens until the next DaemonSet pod stays `Pending` forever".

**Fix.** Add `karpenter.k8s.aws/instance-memory Gt 4096` (MiB) to the default NodePool requirements. Excludes anything with ≤ 4 GiB raw memory (i.e., excludes `*.large`), forcing `xlarge+` as the minimum. With ~6.5 GiB allocatable per node, the DaemonSet set (~950 Mi) plus typical workload pods has comfortable headroom; future DaemonSet additions land without retroactively breaking provisioned nodes.

**Trade-off.** Roughly 2x the hourly cost vs `*.large`. Compensated by (a) one xlarge bin-packs the workload of 1.5-2 larges, (b) eliminates the entire failure mode described above.

**Combined effect of v0.39.11 + v0.39.12**: any node Karpenter provisions has ≥ 2 vCPU AND > 4 GiB raw memory, which means it can host any reasonable DaemonSet count plus workload. The default became operationally sane.

## [0.39.11] — 2026-05-15

### Fixed — `components/karpenter-resources`: default NodePool no longer provisions unusable nodes

Three coordinated changes to the baseline NodePool that were validated downstream (cortex prd, 2026-04-30 → 2026-05-01) but never propagated upstream — every fresh AWS cluster bootstrap was hitting the same issues until each operator wrote a wrapper override.

- **ENI pod-density floor.** Replaced `instance-size: [medium, large, xlarge]` with `instance-cpu Gt 1`. AWS VPC CNI without Prefix Delegation caps `--max-pods` at 8 for `*.medium` types, which can't accommodate the 6+ mandatory DaemonSets (aws-node, kube-proxy, ebs-csi-node, eks-pod-identity-agent, alloy, node-exporter) plus any workload pod. The functional `instance-cpu Gt 1` constraint excludes mediums (all 1 vCPU) while leaving the upper end (2xlarge, 4xlarge, …) fully open — Karpenter retains flexibility to bin-pack large workloads efficiently. The pool's `limits` block (32 vCPU / 64 GiB) caps total cost regardless of size.

- **Consolidation policy `WhenEmpty` (was: `WhenEmptyOrUnderutilized`).** Karpenter v1.3+ SpotToSpotConsolidation has a hardcoded minimum of 15 cheaper instance options for single-node consolidation. On steady-state fleets where only 1-11 alternatives surface, the policy still fires every minute and aborts, generating constant churn without forward progress. Observed live on a production fleet: 208 nodes launched in 24h, 95% disrupted by `Underutilized` consolidation. Reverting to `WhenEmpty` is the documented workaround until the upstream issue is fixed. Downstream may re-enable `WhenEmptyOrUnderutilized` per cluster.

- **`consolidateAfter: 5m` (was: `1m`).** 1m fires while pods are mid-rotation, cascading single deletes into chains. 5m absorbs natural rescheduling waves.

This patch fixes a default that nobody had ever revisited since the initial commit copied the legacy NodePool verbatim in 2026-02.

## [0.39.10] — 2026-05-06

### Added — `components/snapshot-controller/` chart with VolumeSnapshotClass

New optional component that ships VolumeSnapshotClass resources for the
in-cluster CSI snapshot-controller. The controller and CRDs themselves
are installed via cloud-managed mechanisms (AWS: EKS managed addon
`snapshot-controller`, provisioned in
`estabilis-platform/providers/aws/eks.tf`).

`values-aws.yaml` ships one VolumeSnapshotClass `ebs-csi-aws` with the
`velero.io/csi-volumesnapshot-class: "true"` discovery label so Velero
backups can snapshot EBS PVs (previously fell back to no snapshot →
`PartiallyFailed` backups, observed on cortex prd 2026-05-05). Default
class annotation set so workloads requesting `kind: VolumeSnapshot`
without `snapshotClassName` resolve to this VSC.

Consumed by `bootstrap/platform-root/templates/snapshot-controller.yaml`
in estabilis-platform v0.46.0+ (AWS-only, sync wave 6 — before
velero in wave 7).

## [0.39.9] — 2026-05-04

### Fixed — Workload Alloy `metric_pods` relabel for annotation scrape

`values/workload/alloy.yaml`: same regex bug shipped fixed in the hub
Alloy via Estabilis/estabilis-platform#148. The previous rule used
only the `prometheus.io/port` annotation as source label with regex
`"(.+)"` and replacement `"${1}:$0"`, causing both backrefs to resolve
to the captured port value. Result: `__address__="<port>:<port>"`
(e.g. `"9090:9090"`) instead of `"<pod_ip>:<port>"`. Any pod with
`prometheus.io/scrape=true` annotation on a workload cluster never had
its `/metrics` endpoint reached.

Replaced with the canonical Prometheus pattern: combine `__address__`
(pod IP from discovery) with the annotation port, matching
`"([^:]+)(?::\d+)?;(\d+)"` and replacing with `"$1:$2"`. Also added a
companion rule honoring `prometheus.io/path` when present.

Workload Alloy does not run an OTLP receiver — only the hub does — so
Bug 2 from the upstream PR (OTLP metrics + logs routing) does not
apply here.

Validation: `helm template grafana/alloy --version 1.6.2 -f
values/workload/alloy.yaml` renders cleanly; `alloy fmt` exit 0;
`alloy run` on the rendered config exits 0 (only the expected
`sys.env()` errors fire when run offline without `LOKI_PUSH_URL` /
`MIMIR_PUSH_URL` / `CLUSTER_NAME` set).

Lower urgency than the hub fix — there are no workload clusters in
production at the time of writing. Merging keeps the workload Alloy
ready for the first cluster that gets provisioned.

Refs Estabilis/estabilis-platform-tools#210, PR #40.

## [0.39.4] — 2026-04-30

### Fixed — `allow-grafana` NetworkPolicy now allows AWS ALB ingress

`components/network-policies/templates/policies.yaml`: the `allow-grafana`
NetworkPolicy was Azure-first, with three ingress rules all keyed on
`namespaceSelector` (traefik / grafana / any-ns). On AWS the ingress
controller is the ALB Controller with `target-type: ip`, which delivers
traffic from the ALB's VPC ENIs directly to the pod IP, **outside any
K8s namespace scope**. NetworkPolicy `namespaceSelector` rules don't
match that source, so the ALB's health-checks and proxied requests both
hit the implicit default-deny on `policyTypes: [Ingress]` and timed out
(observed: ALB Target Group reports `Target.Timeout`, browser sees
HTTP 504 after 10s).

The fix mirrors the existing `allow-vault` pattern in this same file:
a port-restricted allow-all source rule on the app's HTTP port (3000),
plus the namespace-selectors for in-cluster comms preserved.

Azure impact: zero. The removed `namespaceSelector: traefik` rule was
strictly redundant with the kept `namespaceSelector: {}` — the wildcard
selector covers any namespace including `traefik`. Loki/Mimir/Tempo/
Alloy/Pyroscope intra-namespace and cross-namespace traffic continues
to be allowed by the unchanged namespace-selector rules — port-agnostic,
so internal Loki:3100/Mimir:8080/Tempo:3200/etc. communication is not
affected.

Validated end-to-end on cortex EKS prd: ALB Target Group flipped from
`Target.Timeout` to `healthy` within 10s of the patch; `/`, `/login`,
`/api/health` all return 200/302 in ~0.5s instead of 10s+504.

## [0.39.3] — 2026-04-30

### Added — Vault provider in `cluster-secret-store` (opt-in `app-secret-store`)

`components/cluster-secret-store/templates/cluster-secret-store-vault.yaml`:
new template that renders a Vault-backed `ClusterSecretStore` named
`app-secret-store` ONLY when `.Values.vault.enabled: true`. Default is
off — chart stays quiet for deployments that don't run Vault.

When activated (passed by platform-root from `components.vault: true`,
the same toggle that activates the Vault Application), the chart
renders an additional ClusterSecretStore alongside the existing
`platform-secret-store` (AWS SM / Azure KV). Two stores let apps pick
where their secrets live:

- `platform-secret-store` (provider=aws|azure) → platform infra
  secrets bootstrapped by Terraform (grafana-db, argocd-redis,
  openai-api-key, etc).
- `app-secret-store` (provider=vault) → workload application secrets
  curated by the platform team out-of-band.

Driven by cortex prd 2026-04-30 postmortem: 19 ExternalSecrets in
`app-*` namespaces were stuck on `SecretSyncedError` because the
cortex `common-app` Helm chart hardcodes
`externalSecrets.storeName: app-secret-store` as canonical, but the
chart had branches only for AWS / Azure — no Vault counterpart. The
`common-app` Chart.yaml description even says "Platform layer
provisions the ClusterSecretStore pointing to the chosen backend",
but that promise was unfulfilled until this release.

Defaults assume in-cluster Vault deployed via the HashiCorp chart at
`vault.vault.svc.cluster.local:8200`, KV-v2 at `secret/`, kubernetes
auth method with role `external-secrets` (which `vault-bootstrap.sh`
provisions). Override any of these in downstream values when running
a remote / external Vault.

### Files

- `components/cluster-secret-store/templates/cluster-secret-store-vault.yaml` (NEW)
- `components/cluster-secret-store/values.yaml` (added `vault:` block, default `enabled: false`)
- `workload-bootstrap/Chart.yaml` (`version` + `appVersion` → 0.39.3)
- `workload-bootstrap/values.yaml` (`repoVersion` → v0.39.3)
- `CHANGELOG.md` (this entry)

## [0.39.2] — 2026-04-30

### Added — Universal `selfsigned` ClusterIssuer in `cert-manager-config`

`components/cert-manager-config/templates/cluster-issuer-selfsigned.yaml`:
new universal ClusterIssuer named `selfsigned` (cert-manager.io/v1,
type SelfSigned). Created unconditionally — applies to both Azure and
AWS deployments — because the use cases (admission webhook certs,
internal mTLS, bootstrap CAs) are provider-agnostic and don't require
ACME/DNS validation.

Canonical first consumer: `external-secrets` chart's
`webhook.certManager.cert.issuerRef` in `estabilis-platform >= v0.36.3`.
Without this issuer the chart cannot enable cert-manager mode for the
webhook cert, and falls back to its bundled cert-controller which
fights ArgoCD's ServerSideApply on the cluster-scoped
ValidatingWebhookConfiguration (full diagnosis in
`estabilis-platform-tools/docs/runbooks/cortex/cortex-aws-prd-upstart-cli-mirror.md`
Wave 3 postmortem).

Other components can reuse the same issuer for any internal cert that
doesn't need a publicly-validated chain.

### Files

- `components/cert-manager-config/templates/cluster-issuer-selfsigned.yaml` (NEW)
- `workload-bootstrap/Chart.yaml` (`version` + `appVersion` → 0.39.2)
- `workload-bootstrap/values.yaml` (`repoVersion` → v0.39.2)
- `CHANGELOG.md` (this entry)

## [0.39.1] — 2026-04-29

### Fixed — `allow-metrics-server` NetworkPolicy port mismatch (AWS-only)

The `allow-metrics-server` NetworkPolicy in `components/network-policies/templates/policies.yaml`
hardcoded `port: 4443` for ingress traffic from the API server. The
upstream metrics-server helm chart consumed by
`estabilis-platform/bootstrap/platform-root/templates/metrics-server.yaml`
serves the aggregated API on **port 10250** (`--secure-port=10250` in
the deployment args; matches `containerPort.https`). With the policy
restricting ingress to a port the pod did not listen on, the API
server's discovery probe to `v1beta1.metrics.k8s.io` failed with
`context deadline exceeded`, leaving the APIService stuck at
`Available: False (FailedDiscoveryCheck)` and breaking `kubectl top`,
HPA, and any controller that reads the Resource Metrics API.

This bug affects **AWS deployments only**. Azure (AKS) clusters provide
metrics-server natively as part of the managed control plane, so the
NetworkPolicy is gated off (`components.metrics-server: false` and the
metrics-server Application is also AWS-only via
`{{ if eq .Values.global.provider "aws" }}`).

The bug was introduced in v0.37.2 (commit `a9f3d6a` —
`fix: cover metrics-server namespace in policy/quota layers`). Until
the cortex-platform-aws-us-east-1-prd upstart on 2026-04-29, no AWS
PRD environment had run both metrics-server (Wave 2) and network-policies
(Wave 15) end-to-end, so the regression went unnoticed.

Fix:

- `components/network-policies/templates/policies.yaml` line 626:
  `port: 4443` → `port: 10250`
- Updated inline comments on lines 607 and 623 to reflect the chart's
  actual port and document why this block must track the chart.

### Files

- `components/network-policies/templates/policies.yaml`
- `workload-bootstrap/Chart.yaml` (`version` + `appVersion` → 0.39.1)
- `workload-bootstrap/values.yaml` (`repoVersion` → v0.39.1)

## [0.39.0] — 2026-04-28

### Changed — `client-apps` ApplicationSet aligns with ADR 0027 taxonomy v2

The wrapper Application generated by the `client-apps` ApplicationSet
in `workload-bootstrap/templates/client-apps.yaml` now declares
`project: workload-client-infra` (renamed from `workload-infra` per
ADR 0027). The wrapper itself is platform infrastructure deployed on
the hub argocd namespace by `workload-bootstrap`; inner Applications
declared by the client at `platforms/{deploymentId}/apps/{name}/application.yaml`
choose their own project independently:

- `app-*` namespace → `project: workload-apps` (NEW project, see
  estabilis-platform v0.36.0 release)
- system namespace + cluster CRDs/RBAC → `project: workload-client-infra`

ArgoCD enforces project boundaries on the inner Application at sync
time, so the wrapper's project does not propagate.

### Added — `clientApps.autoSync` flag (default `false`)

New `workload-bootstrap/values.yaml` key `clientApps.autoSync` gates
the `automated.{prune,selfHeal}` block on every Application generated
by `client-apps`. **The new default is `false` (manual sync).**

Why default manual:

- **Cold-cluster bootstrap is race-free.** Workload Apps stay
  `OutOfSync` until the operator triggers sync, so they never thrash
  while ESO/ALB/CNPG/image-updater are still coming up.
- **Production-safe by default.** Every workload deploy goes through
  an explicit gate (operator, CI pipeline, or argocd-image-updater
  writeback). No accidental rollout if a gitops-repo merge slips
  through.

To opt back into pure GitOps continuous reconciliation per cluster,
set in the wrapper's `overrides/platform-root/values.yaml`:

```yaml
clientApps:
  autoSync: true
```

The override propagates from the parent platform-root chart's
`.Values.clientApps.autoSync` via the `workload-bootstrap.yaml`
Application's helm parameter (estabilis-platform v0.36.0+).

### Migration

Bump `workload-bootstrap/Chart.yaml` `version` + `appVersion` to
`0.39.0`, `workload-bootstrap/values.yaml` `repoVersion` to `v0.39.0`.

Inner Applications in client gitops repos that previously declared
`project: workload-infra` MUST migrate per ADR 0027 §Decision Part 4:

- `app-*` namespace → `project: workload-apps`
- system namespace → `project: workload-client-infra`

Apps that do not migrate hit `InvalidSpecError: project workload-infra not found`
because the project no longer exists at the platform v0.36.0 level.

## [0.38.2] — 2026-04-26

### Added — `components/vault-ingress/` (migrated from platform repo per ADR 0002)

The `vault-ingress` chart was originally created in
`estabilis-platform/core/components/vault-ingress/` (v0.28.2). Per
ADR 0002 (gitops chart consolidation, Phase 3 target), all platform
component charts must live in this repo, with the platform repo
keeping only the bootstrap Application templates that reference them.

This release moves the chart to its correct home before any client
takes a hard dependency on the legacy path.

#### Changes

- **NEW**: `components/vault-ingress/` (Chart.yaml, values.yaml,
  templates/_helpers.tpl, templates/middleware.yaml). Byte-identical
  copy of what shipped in `estabilis-platform v0.28.2`.
- The platform repo's `bootstrap/platform-root/templates/vault-ingress.yaml`
  is updated in `estabilis-platform v0.28.3` (paired) to reference the
  new path: `repoURL: estabilis-platform-gitops.git` + `path: components/vault-ingress`.

#### Migration

For clusters running `estabilis-platform v0.28.2`:
- Bump platform to `v0.28.3` (paired with this release). The
  Application's source repoURL changes from platform to gitops; ArgoCD
  handles the source change transparently — same chart content, no
  pod restart, no Ingress recreation.

For deployments not yet using Vault: no-op.

## [0.38.1] — 2026-04-25

### Fixed — Vault chart overlays cleaned up (no more dead-code placeholders, no more gp3 default)

Companion to `estabilis-platform v0.28.2` which lands the `vault-ingress`
chart. v0.38.0's overlays carried two issues exposed during the cortex
deployment:

#### `values/platform/vault-aws.yaml` & `vault-azure.yaml`

- **Removed placeholder strings** (`VAULT_KMS_REGION_PLACEHOLDER`,
  `VAULT_KMS_KEY_ID_PLACEHOLDER`, `VAULT_TENANT_ID_PLACEHOLDER`, etc.)
  inside the `server.ha.raft.config` block. The platform-root template
  in `bootstrap/platform-root/templates/vault.yaml` injects the entire
  `server.ha.raft.config` value via `--set` from helm.parameters,
  completely overriding any value set in these overlay files. The
  placeholders were dead code — confusing and never substituted.

- **`server.dataStorage.storageClass` default changed `gp3` → `""`**
  (use the cluster's default StorageClass). Older EKS clusters ship
  only the legacy in-tree `gp2` provisioner without the EBS CSI driver;
  hardcoding `gp3` blocked PVC binding on those. Clusters that have
  `gp3` available can override per-client via `overrides/vault/values.yaml`.

These overlay files now carry only the bits NOT handled via helm
parameter — `serviceAccount.create: true`, the `azure.workload.identity/use`
label for Azure, and the (now-empty) `storageClass`.

## [0.38.0] — 2026-04-25

### Added — `vault` namespace coverage in policy/quota layers (foundation)

First pass of HashiCorp Vault as a multi-provider platform component.
This release lands ONLY the policy/quota coverage (triple-belt) for
the `vault` namespace; the chart values overlay, Terraform
infrastructure, and platform-root Application live in
`estabilis-platform v0.28.0` (paired).

#### Changes

1. **`components/kyverno-policies/templates/_helpers.tpl`** — add
   `vault` to `excluded-namespace-list` (alphabetically last). Affects
   the four ClusterPolicies that use this helper
   (`default-deny-network-policy`, `inject-pss-labels`,
   `require-limit-ranges`, `require-resource-quotas`).
2. **`components/network-policies/`** — declare `vault` in `components`
   and `policies` maps (default `false`) + new `allow-vault` template.
   Allows broad egress (cloud unseal endpoint — KMS / Azure Key Vault,
   backup storage — S3 / Azure Storage, Kubernetes API), inter-pod
   Raft on port 8201, ingress on Vault API port 8200 from any pod
   (Vault is the cluster-scoped secret store), and Alloy metrics
   scraping from `grafana` namespace.
3. **`components/resource-quotas/`** — declare `vault` in `components`
   and `namespaces` maps (default `false`). Sized for 3-replica Raft HA
   at chart defaults (50m/128Mi requests, 250m/256Mi limits per pod):
   hard `requests.cpu=300m, requests.memory=600Mi, limits.cpu=1500m,
   limits.memory=1500Mi`. PVC count = 5 (3 Raft replicas with headroom).

#### Foundation scope

This release is part of the Vault foundation — chart deployment +
provider-aware unseal infrastructure only. Bootstrap (auth methods,
policies, KV mount, ClusterSecretStore wiring) is intentionally
deferred to downstream / follow-up releases. Vault comes up sealed
or auto-unsealed (depending on cloud unseal status) but
NOT-INITIALIZED — operator runs `vault operator init` manually after
the platform-root Application syncs.

The `vault: false` default in both charts pairs with the upstream
`bootstrap/platform-root/values.yaml` default of `vault: false` —
opt-in feature, activated by `vault_enabled = true` in
terraform.tfvars.

## [0.37.2] — 2026-04-25

### Added — `metrics-server` namespace coverage in policy/quota layers

Audit follow-up to v0.37.1: `metrics-server` (AWS-only — Azure AKS
ships it natively) had the same triple-layer gap that
`aws-load-balancer-controller` and `karpenter` had before v0.37.0:
- Not in `excluded-namespace-list` → Kyverno generated `default-deny-all`
- Not in `network-policies` `components` / `policies` → no `allow-*`
- Not in `resource-quotas` `components` / `namespaces` → no quota / limit

Live cortex-eks observation prior to this fix:
```
$ kubectl -n metrics-server get networkpolicy,resourcequota,limitrange
NAME               POD-SELECTOR   AGE
default-deny-all   <none>         13h    ← only Kyverno-generated, no compensating allow
```

#### Changes

1. **`components/kyverno-policies/templates/_helpers.tpl`** — add
   `metrics-server` to `excluded-namespace-list` (alphabetically between
   `kyverno` and `node-exporter`).
2. **`components/network-policies/`** — declare `metrics-server` in
   `components` (default `false`) + `policies` map + new
   `allow-metrics-server` template. Allows kubelet egress (port 10250)
   for resource metrics scrape, broad egress for cluster IP, ingress
   from API server on chart default port 4443 (aggregated /apis/metrics.k8s.io)
   and from grafana namespace for Alloy scraping.
3. **`components/resource-quotas/`** — declare `metrics-server` in
   `components` (default `false`) + `namespaces` map. Sized for chart
   default of 2 HA replicas × 100m/200Mi (requests): hard
   `requests.cpu=300m, requests.memory=600Mi, limits.cpu=1, limits.memory=1Gi`.

The upstream platform-root provider-aware filter (introduced in
`estabilis-platform v0.27.0`) already includes `metrics-server` in the
`awsOnly` list, so on Azure these stay `false` and the chart skips
rendering for the non-existent namespace.

## [0.37.1] — 2026-04-25

### Fixed — `karpenter` ResourceQuota undersized for chart defaults

`components/resource-quotas/values.yaml` shipped v0.37.0 with a
karpenter quota of `requests.cpu=500m, requests.memory=1Gi` based on
a back-of-envelope sizing. The actual karpenter chart defaults
(per pod) are `requests.cpu=500m, requests.memory=1Gi`, and the
chart deploys 2 replicas — so the steady-state consumption already
exceeds the quota out of the box (2 × 1Gi = 2Gi memory > 1Gi quota).

Live cortex-eks observation:
```
requests.cpu:    1/500m    (2 pods × 500m = 1 CPU)
requests.memory: 2Gi/1Gi   (2 pods × 1Gi = 2Gi)
```

Existing pods continue running (Kubernetes does not retroactively
evict over-quota pods), but new pods would be denied — including
rollout surges and OOMKill replacements.

#### Fix

Bumped quota to give 50% headroom over steady state for safe rolling
updates (3 pods during surge):
```
requests.cpu:    500m  → 1500m
requests.memory: 1Gi   → 3Gi
limits.cpu:      2     → 4
limits.memory:   2Gi   → 4Gi
```
ALB controller quota is unchanged — its chart defaults
(`requests.cpu=10m, requests.memory=64Mi`) leave the v0.37.0 quota
generous already (live: 20m/500m, 128Mi/512Mi).

## [0.37.0] — 2026-04-25

### Added — `aws-load-balancer-controller` and `karpenter` namespaces in policy/quota coverage

The `aws-load-balancer-controller` and `karpenter` namespaces were never
listed in the platform's three exclusion/coverage layers, leaving them
exposed to:
- Kyverno background-generated `default-deny-all` NetworkPolicy from the
  `default-deny-network-policy` ClusterPolicy (unconditional generate
  rule, ignores the `kyverno.io/exclude` namespace label which only
  affects admission webhooks).
- `inject-pss-labels`, `require-limit-ranges`, `require-resource-quotas`
  ClusterPolicies' Audit hits.
- Zero `allow-*` NetworkPolicy compensating the deny-all (would block
  AWS API egress on any cluster with NetworkPolicy enforcement enabled).
- Zero `ResourceQuota` / `LimitRange` (no resource starvation guards).

Today the live cortex-eks cluster is unaffected because EKS VPC CNI
does not enforce NetworkPolicy by default and the Kyverno policies run
in Audit mode. This release closes the gap proactively.

#### Changes

1. **`components/kyverno-policies/templates/_helpers.tpl`** — add
   `aws-load-balancer-controller` and `karpenter` to the
   `kyverno-policies.excluded-namespace-list` helper. Affects the four
   ClusterPolicies that use it (`default-deny-network-policy`,
   `inject-pss-labels`, `require-limit-ranges`, `require-resource-quotas`).
2. **`components/network-policies/`** — declare both namespaces in the
   `components` and `policies` maps + new `allow-aws-load-balancer-controller`
   and `allow-karpenter` NetworkPolicy templates. Each allows broad egress
   (AWS APIs over HTTPS + DNS + Kubernetes API), webhook callback ingress
   on the chart's default port (9443 / 8443), and Alloy metrics scraping
   from the `grafana` namespace.
3. **`components/resource-quotas/`** — declare both namespaces in the
   `components` and `namespaces` maps with quotas sized for the chart
   defaults (ALB controller: 2 replicas × small footprint; karpenter:
   2 replicas × moderate memory for cache).

#### Provider-aware default-off (defensive)

All three components default to `false` for `aws-load-balancer-controller`
and `karpenter` in the chart values. The upstream platform-root
forwarding template (>= v0.27.0, paired) only flips them to `true` on
AWS deployments where the relevant feature flag is set
(`ingress_controller=alb` for ALB controller, `autoscaler=karpenter|hybrid`
for karpenter). On Azure the namespaces don't exist (Application
templates are gated on `global.provider == "aws"`) and these toggles
stay `false`, so this chart never tries to apply policies/quotas to
non-existent namespaces.

#### Pairing

This release pairs with `estabilis-platform v0.27.0` which lands the
filtered components forwarding in
`bootstrap/platform-root/templates/network-policies.yaml` and
`resource-quotas.yaml`. Operators bumping just one of the two:
- `gitops v0.37.0` alone with `platform v0.26.x`: chart defaults
  produce `false`, but upstream platform-root forwards `true` for these
  components on every cluster regardless of provider, so the new
  policies/quotas DO render — same outcome as before this release on
  AWS, latent OutOfSync risk on Azure (workaround: explicit
  `aws-load-balancer-controller: false, karpenter: false` in
  `overrides/platform-root/values.yaml`).
- `platform v0.27.0` alone with `gitops v0.36.1`: provider-aware
  filter applies but the gitops chart never had ALB/karpenter coverage.
  No regression.

## [0.36.1] — 2026-04-25

### Re-released as 0.36.1

v0.36.0 tag pointed at the release commit BEFORE the feature PR (#28)
landed on main (the operator merged the release commit prematurely).
The tagged commit lacks the `aws-load-balancer-controller` overlay
and `workload-bootstrap` version bump. v0.36.1 supersedes v0.36.0;
the v0.36.0 tag remains in history but should not be referenced by
downstreams.

## [0.36.0] — 2026-04-25 (DO NOT USE — tag points at incomplete commit)

### Added — `values/platform/aws-load-balancer-controller.yaml`

Companion to `estabilis-platform v0.23.0`, which adds the AWS Load
Balancer Controller Application gated on
`ingress_controller == "alb"`. This release ships the values overlay
consumed by that Application via `$values/values/platform/aws-load-balancer-controller.yaml`.

Defaults mirror the legacy `cortex-eks-prod` configuration (chart
`1.17.1`, controller `v2.17.1`):
- Resources: requests cpu=10m mem=64Mi / limits cpu=100m mem=128Mi
- ServiceAccount created by the chart, IRSA role-arn injected via
  helm.parameters from the platform-root template.
- `podDisruptionBudget.maxUnavailable: 1` for the chart's default 2
  replicas.

`clusterName` and `vpcId` are NOT set in this overlay — they MUST be
injected via helm.parameters from `platform-infrastructure` ConfigMap
(`global.clusterName`, `global.vpcId`). Leaving them unset here makes
the chart fail loud if a downstream forgets to wire them.

### Migration

Bump `workload-bootstrap/Chart.yaml` `version` + `appVersion` to
`0.36.0`, `workload-bootstrap/values.yaml` `repoVersion` to `v0.36.0`.

Consumers (Estabilis client downstreams on AWS adopting `alb` ingress):
set `platformGitopsVersion: "v0.36.0"` in
`overrides/platform-root/values.yaml`. Required by
`estabilis-platform v0.23.0`+ when `ingress_controller = "alb"`.

### Azure impact

Zero. AWS-only overlay, never referenced by Azure-gated Applications.

## [0.35.1] — 2026-04-25

### Fixed — Karpenter `controller.resources` path (was top-level `resources`, silently ignored)

The Karpenter chart (verified on both 1.9.x and 1.12.x) nests the
controller container resources under `controller.resources` — NOT
top-level `resources`. v0.35.0 of this repo had requests/limits at the
top level, so when the platform-root karpenter Application rendered
on cortex-eks-platform-prd, the chart silently dropped the values and
the live Deployment shipped with `resources: {}`.

Confirmed by reading `helm show values oci://public.ecr.aws/karpenter/karpenter`
for both versions; the only `resources:` definition in the schema is
indented under `controller:`.

### Fix

Re-nest under `controller.resources` and also bump to the values that
match the legacy `cortex-eks-prod` LIVE Deployment (requests
`500m / 1Gi`, limits `1 / 1Gi`) — the legacy `helm get values` output
showed lower numbers (`250m / 500m / 512Mi`) at the wrong path,
overridden by a manual patch later. We pin the actually-running
configuration as the platform default.

### Migration

Operators on `v0.35.0` on AWS: bump `platformGitopsVersion` to
`v0.35.1`, refresh + sync `karpenter` Application. Live Karpenter
Deployment will roll its pods picking up the new requests/limits.
No CRD changes; no impact on workloads scheduled by Karpenter.

### Azure impact

Zero — `karpenter` Application is gated on `provider == "aws"`.

## [0.35.0] — 2026-04-24

### Added — `components/karpenter-resources/` chart + `values/platform/{metrics-server,karpenter}.yaml` overlays (AWS)

Companion release to `estabilis-platform v0.21.0`, which adds Karpenter
v1.12.0 + metrics-server Applications for AWS. This release ships the
chart and value overlays consumed by those Applications, following ADR
0002 Phase 3 (gitops repo as single source of truth for new components).

#### `components/karpenter-resources/`

Estabilis-authored chart that renders the two Karpenter custom
resources for AWS:

- `NodePool/default` — limits cpu=32 mem=64Gi, disruption
  `WhenEmptyOrUnderutilized` after 1m, requirements amd64 +
  spot/on-demand, instance categories c/m/r/t, generation > 4, sizes
  medium/large/xlarge, `expireAfter: 720h`. Mirrors the legacy
  `cortex-eks-prod` configuration.
- `EC2NodeClass/default` — AMI alias `al2023@latest`, BDM `/dev/xvda`
  30Gi gp3 encrypted, **IMDSv2 enforcement** (`httpTokens: required`,
  `httpPutResponseHopLimit: 1`, `httpProtocolIPv6: disabled`),
  Subnet/SG selection via `<discoveryTagKey>=<clusterName>` tags
  (Terraform-applied; default tag key `estabilis.io/discovery`).

Cluster-specific wiring (`clusterName`, `nodeRole`, `discoveryTagKey`)
is injected via helm parameters from the platform-root template's
AWS branch. NodePool/EC2NodeClass shape (instance families, sizes,
limits) is configurable in this chart's `values.yaml` so downstream
can tune capacity without forking.

The chart's `appVersion` tracks the upstream Karpenter controller
version we pin (currently 1.12.0). Schemas have remained stable
across 1.x releases.

#### `values/platform/metrics-server.yaml`

Defaults for the upstream `metrics-server` chart on hub clusters.
Consumed by `estabilis-platform/bootstrap/platform-root/templates/metrics-server.yaml`
via the `$values/values/platform/metrics-server.yaml` ref. Mirrors
legacy production: 2 replicas, podAntiAffinity by hostname,
`--kubelet-insecure-tls`, tight resource limits.

#### `values/platform/karpenter.yaml`

Defaults for the upstream `karpenter` controller chart on hub
clusters. Mirrors legacy production: controller resources, fargate
toleration, `featureGates.spotToSpotConsolidation: true`. Cluster
endpoint, name, and IRSA role are injected via helm parameters from
the platform-root template, NOT this overlay.

### Migration

Bump `workload-bootstrap/Chart.yaml` `version` + `appVersion` to
`0.35.0`, `workload-bootstrap/values.yaml` `repoVersion` to `v0.35.0`.

Consumers (Estabilis client downstreams on AWS): set
`platformGitopsVersion: "v0.35.0"` in
`overrides/platform-root/values.yaml`. Required by
`estabilis-platform v0.21.0`+ on AWS.

### Azure impact

Zero. All overlays and the chart are AWS-only — neither is referenced
by any Application gated on `provider == "azure"`.

## [0.34.0] — 2026-04-24

### Added — `components/cluster-secret-store` chart now supports AWS provider

The chart had a single Azure template (`cluster-secret-store-azure.yaml`)
that unconditionally rendered an `azurekv`-backed ClusterSecretStore.
This release adds:

- A new `provider` top-level value. Defaults to `"azure"` for
  backcompat — existing Azure downstreams see zero change.
- `cluster-secret-store-aws.yaml`: rendered when `provider: aws`,
  produces an ExternalSecrets `ClusterSecretStore` using the AWS
  Secrets Manager provider, authenticated via IRSA (JWT/
  `serviceAccountRef`).
- New values fields:
  - `region` (required on AWS; falls back per-store when `stores` is set)
  - `aws.serviceAccount.{name,namespace}` — defaults `external-secrets/external-secrets`

### Migration

- Azure downstreams: no action. `provider` defaults to `azure`.
- AWS downstreams: set `provider: aws`, `region: <aws-region>` in
  `overrides/platform-root/values.yaml` (or equivalent) and ensure the
  `external-secrets` ServiceAccount carries the IRSA annotation
  (already wired by `providers/aws/iam.tf` →
  `module.external_secrets_irsa`).

### Consumer alignment

`estabilis-platform` v0.19.0+ passes `provider: {{ .Values.global.provider }}`
as a helm parameter from `bootstrap/platform-root/templates/cluster-secret-store.yaml`.
Older `estabilis-platform` versions send no `provider` parameter and the
chart falls back to Azure — still safe for Azure-only deployments.

## [0.33.0] — 2026-04-24

### Added — AWS provider overlays for platform hub components

Introduces two new per-provider overlay files under `values/platform/`
loaded by the hub's `platform-root` Application via the existing
`$values/values/platform/<component>-{{ .Values.global.provider }}.yaml`
convention. Both files wire the respective ServiceAccount for IRSA so
the controller pods can authenticate against AWS APIs via the IAM
roles already provisioned by `estabilis-platform/providers/aws/iam.tf`.

- `values/platform/cert-manager-aws.yaml` — cert-manager controller SA
  IRSA annotation. Paired with `module.cert_manager_irsa` (gated on
  `dns_provider = "route53"`). Enables Route53 DNS-01 solving for the
  `letsencrypt-production` ClusterIssuer on EKS hub clusters.

- `values/platform/external-secrets-aws.yaml` — external-secrets
  controller SA IRSA annotation. Paired with
  `module.external_secrets_irsa`. Enables the ClusterSecretStore
  (already AWS-aware in `cluster-secret-store.yaml`) to read from AWS
  Secrets Manager.

Both overlays expose `serviceAccount.annotations.eks.amazonaws.com/role-arn`
as an injection point. The value is injected per-cluster by
`platform-root` as a Helm parameter (wired in PR #2 of
`Estabilis/estabilis-platform-tools#186`).

Files are additive — Azure overlays (`cert-manager-azure.yaml`,
`external-secrets-azure.yaml`) remain unchanged; the upstream
`platform-root` template selects exactly one overlay per render based
on `global.provider`.

### Version

`v0.32.0 → v0.33.0`. Minor bump — new provider support, no breaking
changes. Existing Azure deployments continue rendering identically.

## [0.32.0] — 2026-04-22

### Fixed — `inject-pss-labels` infinite drift (Kyverno CRD defaults)

The `kyverno-policies/templates/inject-pss-labels.yaml` template
omitted three fields that Kyverno's CRD defaults populate on admission:

- `admission: true`
- `emitWarning: false`
- `validationFailureAction: Audit`

When ArgoCD applied the git manifest without these fields, Kyverno
admitted the resource and added them; ArgoCD then compared git
(3 fields missing) vs live (3 fields present) → infinite
`OutOfSync Healthy`. The policy functioned correctly throughout
— only the reconciliation status was broken.

Declaring the defaults explicitly in the template matches the
admitted form, closing the drift. Behavior unchanged.

Observed on Transfero HML 2026-04-22 after ADR 0020 migration
triggered a mass re-render: `kyverno-policies-transfero-workload-hml-eastus2`
reported OutOfSync with one failing resource (ClusterPolicy/inject-pss-labels).

### Version

`v0.31.0 → v0.32.0`. Minor bump — no behavior change, but consumer
clusters render a slightly different (now fully-declared) manifest,
which ArgoCD will apply on next reconcile.

## [0.31.0] — 2026-04-22

### Added — `clientGitopsRepoRevision` and `configRepoRevision` values

Part of ADR 0020 (GitOps-native continuous reconciliation). Lets
consumers track a branch (e.g. `main`, `release/prod`) instead of
pinning a specific tag for **own-content repos** (client gitops +
config overrides). Tag pinning for **external dependencies**
(upstream Estabilis versions, container images, external helm
charts) is unchanged.

Changes:

- `workload-bootstrap/values.yaml`: add `clientGitopsRepoRevision`
  and `configRepoRevision`. Legacy `clientGitopsRepoVersion` and
  `configRepoVersion` are **retained for backcompat** — when both
  are set, the `*Revision` wins. When both are empty but the
  corresponding URL is set, the helpers fail loudly.
- `workload-bootstrap/templates/_helpers.tpl`: new helpers
  `clientGitopsRefRequired`, `configRepoRefRequired`, and private
  resolvers `clientGitopsRef` / `configRepoRef`. `overrideEnabled`
  / `overrideSource` / `overrideValueFile` /
  `ignoreMissingValueFiles` updated to consume `configRepoRef`
  instead of `configRepoVersion` directly. `gitopsSource` consumes
  `clientGitopsRefRequired`.
- `workload-bootstrap/templates/client-apps.yaml`: ApplicationSet
  generator `revision` and generated Application `targetRevision`
  both use `clientGitopsRefRequired`.
- `workload-bootstrap/templates/client-kyverno-exceptions.yaml`:
  ApplicationSet source `targetRevision` uses
  `clientGitopsRefRequired`.

### Migration path

- **No action required**: continue setting the legacy `*Version`
  values. Chart renders identically to v0.30.1.
- **Adopt branch tracking**: set `clientGitopsRepoRevision: main`
  (or `release/prod` etc.), leave `clientGitopsRepoVersion` empty.
  Same for `configRepoRevision`. Enables continuous reconciliation
  per ADR 0020.

### Compatibility

100% backward-compatible. Verified via `helm template` in four
modes: legacy-only, revision-only, both-set (revision wins), empty
(fail loud with descriptive message).

### Companion bump

`estabilis-platform` v0.13.0 introduces the matching values at the
platform-root chart level. Use both together when adopting
continuous reconciliation.

## [0.30.1] — 2026-04-22

### Added — `values/platform/acr-image-updater-credentials.yaml` overlay

Empty platform-level overlay file for `acr-image-updater-credentials`.
Referenced by the Application template in estabilis-platform v0.12.4,
which adds `valueFiles` to this Application so per-cluster overrides
(e.g. `secretStoreName: shared-infra-secret-store`) can be declared
without upstream changes.

Patch bump: adds a new overlay file; no API change to the component
chart itself. Lockstep across workload-bootstrap Chart.yaml + values.yaml.

## [0.30.0] — 2026-04-22

### Added — multi-store `ClusterSecretStore` + parametrized `secretStoreName`

Two small but related additions that enable a cluster to read secrets
from more than one Azure Key Vault, eliminating the need for a
single-KV coupling between unrelated Terraform modules.

**`components/cluster-secret-store`** — new `stores` list value.

When `stores` is non-empty, the component renders one
`ClusterSecretStore` per entry instead of the single hardcoded
`platform-secret-store`. Each entry has its own `name` +
`vaultUrl` + (optional) `tenantId`. When `stores` is empty
(default), the legacy single-store behavior is preserved exactly
— `vaultUrl` + `tenantId` at the top level produce the
`platform-secret-store` used by every existing consumer.

**`components/acr-image-updater-credentials`** — new
`secretStoreName` value.

Replaces the hardcoded `name: platform-secret-store` in three
template locations (`external-secret.yaml` ×2,
`git-creds-external-secret.yaml` ×1) with
`{{ .Values.secretStoreName | default "platform-secret-store" }}`.
Default preserves prior behavior; override when the 4 consumed KV
secrets (`acr-shared-sp-client-id`, `acr-shared-sp-client-secret`,
`acr-shared-token`, `image-updater-git-pat`) live in a separate
Key Vault (e.g. a shared-infra KV owned by its own Terraform
module).

### Why

Before this release, any code that stored secrets the cluster had
to read was forced to write to the platform-owned KV — the only
vault bound to the `external-secrets` managed identity in a single
`ClusterSecretStore`. This created cross-module ownership coupling
(observed in `transfero-acr-shared-hml`, which wrote 4 secrets
into the platform KV `kv-transfero-hml-lmj060` simply because the
cluster had no other way to read them).

With multi-store + `secretStoreName`, a downstream module can own
its own KV, provision a second `ClusterSecretStore` pointing at
that KV, and have `acr-image-updater-credentials` read through it
— without any platform code change. Companion PR in
`estabilis-platform` v0.12.3 exposes the MI principal ID so the
downstream module can grant `Key Vault Secrets User` on its own
vault without duplicating the MI.

### Compatibility

- 100% backward compatible. Every existing consumer continues to
  render identical YAML: `stores: []` falls back to single-store,
  omitted `secretStoreName` defaults to `platform-secret-store`.
- No template API breaks; no value renamed or removed.

### Upgrade notes

None required. The new capabilities activate only when the
operator explicitly sets `stores` and/or `secretStoreName`.

Companion repo bump: `estabilis-platform` v0.12.3 adds the
`external_secrets_principal_id` output that shared-infra modules
consume when wiring role assignments on their own KVs.

## [0.29.0] — 2026-04-22

### Added — `acr-image-updater-credentials` emits git write-back PAT Secret

Image Updater v0.x cannot push git write-back commits via AAD
authentication — only via HTTPS Basic (username:password). Add a
third ExternalSecret to the component that reads a PAT from Key
Vault (`image-updater-git-pat`) and produces an Opaque Secret
readable by Image Updater via `git:secret:argocd/<name>`.

- `templates/git-creds-external-secret.yaml` — new, gated by
  `gitCreds.enabled` (defaults to `true` — Image Updater always needs
  write-back for this component to be useful).
- `values.yaml` — new `gitCreds.*` section.
- Component chart `0.3.0` → `0.4.0` (MINOR — new feature, default-on).

Paired Terraform: `transfero-acr-shared-hml` gained `image_updater_git_pat`
variable (sensitive) + `azurerm_key_vault_secret.image_updater_git_pat`
resource.

Consumer Application annotation (set by app author, not this chart):

```yaml
argocd-image-updater.argoproj.io/write-back-method: git:secret:argocd/image-updater-git-creds
argocd-image-updater.argoproj.io/git-repository: https://dev.azure.com/.../transfero-gitops
```

WIF migration (replaces PAT) tracked by
[estabilis-platform-tools#160](https://github.com/Estabilis/estabilis-platform-tools/issues/160).

## [0.28.0] — 2026-04-21

### Changed — `acr-image-updater-credentials` credential mode defaults to SP

The component now supports two credential modes for the shared ACR:

- **`sp` (default)** — Azure AD Service Principal with `AcrPull` RBAC.
  ExternalSecret reads `(clientId, clientSecret)` from two KV secrets
  and renders both the docker-config (`auth: base64(clientId:clientSecret)`)
  and the repo-creds Secret (`username: clientId` + `password: clientSecret`).
- **`token` (legacy)** — scope-map token + fixed username. Retained for
  rollback; NOT recommended because ArgoCD Image Updater asks for the
  standard Docker Registry `:pull` scope which maps only to `content/read`
  under ACR scope-maps. Listing tags (`/v2/<repo>/tags/list`) needs
  `metadata/read`, so the legacy path returns 401 on tag listing even
  when the scope-map grants both actions.

The SP path sidesteps the scope issue entirely: ACR resolves the AAD
identity's RBAC role and issues access tokens covering the full pull
surface without client-side scope negotiation.

Requires the paired Terraform change in `transfero-acr-shared-hml`
(new `image_updater_sp_enabled` variable, creates the SP + RBAC +
KV secrets). See ADR follow-up / commit message in that repo for
details.

## [0.27.2] — 2026-04-21

### Fixed — `acr-image-updater-credentials` dockerconfig uses `auth` field

The docker-config Secret was generated with `username` + `password` fields:

```json
{"auths":{"<host>":{"username":"<u>","password":"<p>"}}}
```

Image Updater v0.17 expects the `auth` field (base64 of `u:p`) and errors:

```
Could not set registry endpoint credentials: invalid auth token for
registry entry <host> ('auth' should be string')
```

Switched the ExternalSecret template to compute `auth` at render time via
sprig `b64enc`. The ArgoCD repo-server credential Secret already works
with `username` + `password` fields and is unchanged.

Component v0.2.1 → v0.2.2 (patch).

## [0.27.1] — 2026-04-21

### Fixed — `acrTokenUsername` default now matches Terraform token name

`components/acr-image-updater-credentials/values.yaml` defaulted
`acrTokenUsername` to `"acr-token"` — but the token resource created
by `transfero-acr-shared-hml` Terraform is `name = "image-updater"`.
ACR login uses the token *resource name* as the username; the old
default returned `401 unauthorized`.

Verified 2026-04-21 from inside `argocd-repo-server`:
- `helm registry login -u acr-token` → `401`
- `helm registry login -u image-updater` → `Login Succeeded` + chart
  pulled.

This bug was invisible until v0.27.0 began exercising the credential
(the repo-server only calls it when an Application pulls from the
shared ACR). Image Updater has the same bug in its docker-config
Secret but was never observed failing because no image pull had
been attempted since the v0.x restore (ADR 0019).

Patch-level bump; no API surface change. Downstream deployments pick
up the fix automatically after `terraform apply` + promote.

## [0.27.0] — 2026-04-21

### Added — `acr-image-updater-credentials` emits ArgoCD repo-creds

The `acr-image-updater-credentials` component (v0.1.0 → v0.2.0) now
creates **two** ExternalSecrets from the same Key Vault token:

1. `acr-image-updater-credentials` (existing) — docker config for
   ArgoCD Image Updater's registry pulls.
2. `cred-acr-shared-charts` (new) — ArgoCD repo-creds so the
   **repo-server** can pull OCI Helm charts from the same ACR.

Rationale: deployments that publish Helm charts to the same shared
ACR that Image Updater watches (e.g., Transfero HML publishing
`common-app` to `acrtransferosharedhml`) need ArgoCD to authenticate
OCI chart pulls. Without this second Secret, chart pulls fail with
`401 unauthorized` (observed 2026-04-21 on partner-service-hml).

Always rendered alongside (1) when `acrLoginServer` is set — harmless
when no Application pulls charts from this host. Opt-out is not
exposed: the incremental runtime cost (one K8s Secret, same KV lookup)
does not justify the configuration surface.

No consumer-side change required. Deployments with `sharedAcrLoginServer`
set in their platform-root override get the new Secret automatically
on next sync.

Paired with:
- `estabilis-platform` no change (template passes `acrLoginServer`,
  which is already wired).
- Downstream `transfero-platform-azure-eastus2-hml` bumps
  `platformGitopsVersion` to v0.27.0 — propagates the new Secret.

## [0.26.1] — 2026-04-21

### Fixed — `argocd-image-updater` values schema reverted to v0.x keys

`values/platform/argocd-image-updater.yaml` used `config.log.level`
(dotted key, v1.x chart schema). Paired commit in `estabilis-platform`
v0.12.2 pins the chart to `0.14.0` (app v0.17.0, annotation-based),
which expects `config.logLevel` (camelCase). Reverted the key.

No behavior change on a running cluster — the ConfigMap values are
equivalent at runtime.

Paired change with **estabilis-platform v0.12.2**. See
`estabilis-platform-tools/docs/adr/0019-argocd-image-updater-v0x-correction.md`
for the full postmortem.

## [0.26.0] — 2026-04-18

### Added

- `components/kyverno-policies` — `policies.inject_pss_labels.privilegedNamespaces`
  and `.extraPrivilegedNamespaces` values. Platform-managed defaults
  (`grafana`, `node-exporter`, `trivy-system`) live under
  `privilegedNamespaces`; downstream overrides append cluster-specific
  entries via `extraPrivilegedNamespaces` (e.g. `ado-build-agent`,
  `harbor`, `jfrog-platform`). Helm replaces arrays on merge, so the
  two-key split keeps platform defaults intact regardless of client
  overrides.

  The `inject-pss-privileged` rule now iterates the concatenated list,
  and `inject-pss-baseline-platform` excludes the same list so the two
  mutation rules never contend for the same namespace.

  Motivation: BuildKit rootless (and similar privileged sidecars)
  require `seccomp: Unconfined`, which violates PSS `baseline` admission.
  Previously the privileged list was hardcoded in the template, forcing
  any new privileged namespace to go through a platform bump.

### Component chart versions

- `components/kyverno-policies`: `0.2.0` → `0.3.0`

### Notes

- Version metadata skips from `0.24.1` directly to `0.26.0` to re-align
  with the `v0.25.0` git tag, which was pushed without bumping
  `workload-bootstrap/Chart.yaml` or `workload-bootstrap/values.yaml`
  (see `[0.25.0]` entry below, added retroactively).

## [0.25.0] — 2026-04-17

> Retroactive entry — the `v0.25.0` tag was pushed without bumping
> `workload-bootstrap/Chart.yaml` or `workload-bootstrap/values.yaml`
> at the time. Documented here to keep the changelog consistent with
> the tag history. `v0.26.0` fixes the metadata drift.

### Added

- `components/argocd-image-updater-base` — base ArgoCD Image Updater
  configuration (registry list sourced from `global.sharedAcrLoginServer`).
- `components/acr-image-updater-credentials` — ExternalSecret that
  mounts the ACR repository-scoped token into the `argocd-image-updater`
  namespace.

### Fixed

- Remove `estabilis.metadata` from the standalone
  `acr-image-updater-credentials` component rendering path (chart can
  now `helm template` without a parent context).

## [0.24.1] — 2026-04-18

### Changed

- Replace `default "HEAD"` fallbacks on four client-gitops git
  references with `required "..."` expressions. When a cluster sets
  `clientGitopsRepoUrl` (and/or `deploymentId`) but does not set
  `clientGitopsRepoVersion`, `helm template` now fails at render time
  with a clear message — previously the chart silently fell back to
  tracking `HEAD`, defeating reproducibility, audit, and blast-radius
  control. Production deployments always pin the version and are
  unaffected.

  Affected templates:
  - `workload-bootstrap/templates/_helpers.tpl` (`gitopsSource` helper)
  - `workload-bootstrap/templates/client-kyverno-exceptions.yaml`
  - `workload-bootstrap/templates/client-apps.yaml` (two occurrences)

### Added

- `scripts/lint-pin-git-refs.sh` — gate that flags
  `default "(HEAD|main|master|latest)"` in templates under
  `workload-bootstrap/templates/`. Wired into pre-commit, CI, and
  `just lint`.

### Documentation

- `.agent-notes/2026-04-18-pin-git-refs.md` — audit note with full
  Classification (Runtime law) per the ADR-0015 framework.

## [0.24.0] — 2026-04-17

### Added

- Dynamic Alloy push URLs via bridge annotations.

### Fixed

- Alloy template trim marker + YAML escaping.

### Changed

- Wire the `lint-ignore-missing-inline` gate into pre-commit, CI
  workflow, and `just lint`. The script shipped in v0.23.1; v0.24.0
  is when it became an enforced gate.

### Documentation

- `.agent-notes/2026-04-18-ignore-missing-values-helper-consolidation.md`
  — audit note for the ignoreMissingValueFiles helper refactor
  (Classification: Convention / uniformity-amplifier).

## [0.23.1] — 2026-04-17

### Changed

- Route all `ignoreMissingValueFiles: true` through the existing
  `workload-bootstrap.ignoreMissingValueFiles` helper. 17 ApplicationSet
  templates previously used the inline form, silencing ANY missing
  valueFile unconditionally. The helper emits the key only when
  `configRepoUrl` + `configRepoVersion` are both set.

  **Behavior change** — clusters without the config-repo pair now
  run in strict mode: a missing valueFile fails the ArgoCD Sync
  instead of being silently skipped. Production deployments
  (Estabilis, Transfero) set both values and are unaffected.

### Fixed

- Disable the `allow-alloy` network policy on hub clusters. Hub
  Alloy runs in the `grafana` namespace (covered by `allow-grafana`);
  the `allow-alloy` policy targets the `alloy` namespace which only
  exists on workload clusters.

### Added

- `scripts/lint-ignore-missing-inline.sh` — gate that flags any
  literal `ignoreMissingValueFiles: true` in
  `workload-bootstrap/templates/*.yaml`. Every occurrence must route
  through the helper.

## Versioning

- **Major** (`v1.0.0`) — breaking chart interface changes
- **Minor** (`v0.X.0`) — new components or values, backward-compatible
- **Patch** (`v0.X.Y`) — bug fixes, value tweaks, documentation

Consumers pin the version via `repoVersion: "vX.Y.Z"` in their
`workload-bootstrap` values overlay. See
[CONTRIBUTING.md](CONTRIBUTING.md#release-process) for the release
workflow.
