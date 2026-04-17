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
                  │   Baseline components (Kyverno, cert-manager,  │
                  │   external-dns, Alloy, Traefik, …) rendered    │
                  │   from this repo + estabilis labels            │
                  └────────────────────────────────────────────────┘
```

## Layout

```
workload-bootstrap/            Helm chart that renders the ApplicationSets
  Chart.yaml                   version + appVersion (bumped on every release)
  values.yaml                  defaults (cluster selector, component toggles, repoVersion)
  templates/
    _helpers.tpl               estabilis.labels / annotations / metadata
    *.yaml                     one ApplicationSet per workload component

components/                    per-component Helm charts (values overlays + policies)
values/                        platform/ and workload/ values files injected as $values
docs/                          architecture notes
```

## Versioning

Semver. Pinned in downstream overrides via `repoVersion` in the
`workload-bootstrap` values overlay. See [CHANGELOG.md](CHANGELOG.md) for
the release history and [CONTRIBUTING.md](CONTRIBUTING.md#release-process)
for the release workflow.

## How the hub consumes this repo

The `estabilis-platform/bootstrap/platform-root/` chart contains one
Application template (`workload-bootstrap.yaml`) that points here:

```yaml
spec:
  source:
    repoURL: https://github.com/Estabilis/estabilis-platform-gitops.git
    targetRevision: vX.Y.Z        # pinned per cluster (see CHANGELOG)
    path: workload-bootstrap
    helm:
      valueFiles:
        - values.yaml
```

Downstream clients override via
`overrides/workload-bootstrap/values.yaml` in their own config repo,
following the same pattern as `overrides/platform-root/values.yaml`.

## Current scope

The canonical list of components and their versions lives in
[`workload-bootstrap/values.yaml`](workload-bootstrap/values.yaml) and
the per-component templates under `workload-bootstrap/templates/`.
Recent additions are tracked in [CHANGELOG.md](CHANGELOG.md).

## References

- [ADR 0001 — Workload bootstrap strategy](https://github.com/Estabilis/estabilis-platform-tools/blob/main/docs/adr/0001-workload-bootstrap-strategy.md)
- [estabilis-workload-operator](https://github.com/Estabilis/estabilis-workload-operator) — provides the CRD and the hub-side reconciliation that registers workload clusters in ArgoCD
