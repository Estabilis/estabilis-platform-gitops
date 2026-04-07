# estabilis-platform-gitops

GitOps manifests that the **hub's ArgoCD** applies to workload
clusters registered by the `estabilis-workload-operator`.

This repo does NOT contain:
- Terraform / IaC (lives in `estabilis-platform` and `estabilis-workload`)
- Hub platform components (lives in `estabilis-platform/core/components/` — for now; see ADR 0001 for the migration plan)
- Client application manifests (lives in each `{client}-gitops` repo)

## Mental model

```
           ┌────────────────────────── hub cluster ──────────────────────────┐
           │                                                                  │
           │   ArgoCD                                                         │
           │     │                                                            │
           │     ├── platform-root  (source: estabilis-platform)              │
           │     │     └── ... hub components (grafana, argocd, kyverno-hub,  │
           │     │             external-secrets, etc.)                        │
           │     │                                                            │
           │     └── workload-bootstrap  (source: THIS repo)                  │
           │           └── ApplicationSet   (selector: estabilis.io/managed-by │
           │                 │                 = workload-operator)            │
           │                 │                                                 │
           │                 └─► renders 1 Application per workload cluster   │
           │                       (multi-source: upstream chart + our values) │
           └──────────────────────────────────────────────────────────────────┘
                                            │
                                            ▼
                  ┌─────────── workload cluster (spoke) ───────────┐
                  │   Kyverno + estabilis labels/annotations       │
                  │   (v0.1.0 — only this, nothing else yet)       │
                  └────────────────────────────────────────────────┘
```

## Layout

```
workload-bootstrap/            Helm chart that renders the ApplicationSet
  Chart.yaml
  values.yaml                  defaults (cluster selector, component versions)
  templates/
    _helpers.tpl               estabilis.labels / annotations / metadata
    applicationset.yaml        the ApplicationSet with cluster generator

workload-components/           per-component values overlays
  kyverno/
    values.yaml                injected as $values into the upstream Kyverno chart

docs/
  architecture.md              this diagram + how to add a new component
```

## Versioning

Semver, starting from `v0.1.0`. Pinned in downstream overrides via
`platform_gitops_version` (analog to `platform_version`). See
`estabilis-platform-tools/docs/adr/0001-workload-bootstrap-strategy.md`.

## How the hub consumes this repo

The `estabilis-platform/bootstrap/platform-root/` chart has one
Application template (`workload-bootstrap.yaml`) that points here:

```yaml
spec:
  source:
    repoURL: https://github.com/Estabilis/estabilis-platform-gitops.git
    targetRevision: v0.1.0
    path: workload-bootstrap
    helm:
      valueFiles:
        - values.yaml
```

Downstream clients override via
`overrides/workload-bootstrap/values.yaml` in their own config repo,
following the same pattern as `overrides/platform-root/values.yaml`.

## Scope of v0.1.0

**Kyverno only** on workload clusters, with estabilis labels and
annotations applied consistently with the platform v0.1.36 convention.

Not in v0.1.0 (tracked in roadmap):
- Alloy DaemonSet (needs auth decision for workload→hub remote_write)
- OTel Operator
- OpenCost on workload
- kyverno-policies (the actual policies — v0.2.x)
- Trivy Operator on workload

## References

- [ADR 0001 — Workload bootstrap strategy](https://github.com/Estabilis/estabilis-platform-tools/blob/main/docs/adr/0001-workload-bootstrap-strategy.md)
- [estabilis-workload-operator](https://github.com/Estabilis/estabilis-workload-operator) — provides the CRD and the hub-side reconciliation that registers workload clusters in ArgoCD
