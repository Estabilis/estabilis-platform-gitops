# Architecture

## The 3-repo split (target)

| Repo | Purpose | Scope |
|---|---|---|
| `estabilis-platform` | IaC for the hub (Terraform, providers) | Will eventually be IaC-only; GitOps content gets migrated to this repo in a future refactor (see ADR 0001). |
| `estabilis-workload` | IaC for workload clusters (Terraform, providers) | Stays IaC-only. No GitOps content here — the workload does NOT run its own ArgoCD. |
| **`estabilis-platform-gitops`** (this repo) | GitOps manifests applied BY the hub ArgoCD | Today: workload bootstrap only. Future: merges the hub components from `estabilis-platform`. |

Plus per-client downstream repos (`estabilis-{client}-platform-*`)
that hold the tfvars and the `overrides/` values for each deployment.

## How the workload bootstrap reaches a cluster

```
1. Terraform in estabilis-workload provisions AKS + creates a
   WorkloadCluster CR on the hub via kubernetes.hub provider.

2. estabilis-workload-operator (on the hub) reconciles the CR:
   - copies credentials
   - opens authorized_ip_ranges on the workload API for the hub NAT
   - registers the cluster in ArgoCD as a Cluster Secret with labels
     estabilis.io/managed-by=workload-operator

3. ArgoCD's workload-bootstrap Application (managed by platform-root
   in estabilis-platform) pulls this repo and renders the
   workload-bootstrap chart.

4. The chart renders an ApplicationSet per component. The cluster
   generator selects on estabilis.io/managed-by=workload-operator,
   so it matches every workload cluster automatically.

5. The ApplicationSet renders one nested Application per cluster
   with multi-source:
     - upstream chart (ghcr.io/kyverno/charts/kyverno for v0.1.0)
     - $values from THIS repo (workload-components/kyverno/values.yaml)

6. ArgoCD applies the rendered Application on each workload cluster.
   Kyverno comes up with estabilis labels.
```

## Adding a new workload component

For v0.1.x scope, "adding a component" means:

1. Pick an upstream Helm chart available as an OCI artifact (ghcr,
   quay, docker hub OCI, ACR — all work).
2. Create `workload-components/<name>/values.yaml` with the values
   overlay. Include the `estabilis.*` labels via `customLabels` or
   equivalent.
3. Add a new entry under `components:` in
   `workload-bootstrap/values.yaml`:
   ```yaml
   components:
     my-component:
       enabled: true
       chart:
         repoURL: <oci-repo>
         chart: <chart-name>
         targetRevision: <pinned-version>
       namespace: <ns>
       valuesPath: workload-components/my-component/values.yaml
       syncPolicy: { ... }
   ```
4. Bump this repo's chart version (`workload-bootstrap/Chart.yaml`)
   to at least MINOR (new feature), tag, push.
5. Update the downstream client overrides
   (`overrides/workload-bootstrap/values.yaml`) if they need
   anything different from the defaults, and bump
   `platform_gitops_version` in the hub tfvars.

## Why not vendor the upstream charts here?

Two reasons:

1. **Size and churn.** Kyverno alone is several MB. If every
   component lived as a Helm dependency, this repo would grow
   with every bump. OCI multi-source keeps the repo small and
   lets the upstream chart be cached content-addressed by ArgoCD.

2. **Clear ownership of values.** Having `values.yaml` be the only
   thing here makes it obvious what we override and what comes
   from upstream. If we vendored, the line between "our change"
   and "upstream default" would blur.

## Why one ApplicationSet per component instead of one for everything?

Because each component has different chart coordinates, namespaces,
and sync policies. Cramming them into a single ApplicationSet
template means branching per component, which is harder to read and
harder to override per client. One ApplicationSet per component is
cheap (they share the same cluster generator) and keeps each
component independently toggleable.

## Future migration note

When the GitOps content currently in `estabilis-platform/core/components/`
and `estabilis-platform/bootstrap/platform-root/` is migrated into
this repo, the layout becomes:

```
estabilis-platform-gitops/
├── workload-bootstrap/          (today)
├── workload-components/         (today)
├── hub-components/              (future — from estabilis-platform/core/components/)
├── bootstrap/
│   └── platform-root/           (future — from estabilis-platform/bootstrap/)
└── docs/
```

At that point `estabilis-platform` has only Terraform. No rename.
