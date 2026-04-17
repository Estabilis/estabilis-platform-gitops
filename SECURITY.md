# Security Policy

## Reporting a vulnerability

Please **do not** open a public issue for security-sensitive reports.

Use GitHub's [private vulnerability reporting](https://github.com/Estabilis/estabilis-platform-gitops/security/advisories/new)
feature. This creates a private advisory that only repository maintainers
can see. Include:

- A description of the issue
- Steps to reproduce (if applicable)
- The affected chart version(s) — see
  [`workload-bootstrap/Chart.yaml`](workload-bootstrap/Chart.yaml)
- Your contact information for follow-up

We aim to acknowledge receipt within 5 business days and will work with
you on a coordinated disclosure timeline.

## Scope

This repository contains ArgoCD GitOps manifests and Helm templates that
are applied to managed Kubernetes clusters. The following issue classes
fall within scope:

- Templates that would grant excessive or unintended RBAC
- Manifests that could leak credentials, tokens, or other secrets
- Values referencing untrusted sources (images, charts, repositories)
- Supply-chain issues — unpinned references, compromised upstream
  dependencies, missing provenance or integrity guarantees
- Template-injection or parameter-passing bugs that a malicious input
  could exploit

## Out of scope

- Issues in upstream Helm charts consumed by this repository — please
  report those directly to their maintainers
- Issues in ArgoCD itself — see the
  [Argo CD security policy](https://github.com/argoproj/argo-cd/security)
- Misconfiguration in downstream client overlays — those are the
  respective client's responsibility

## Supported versions

Only the latest minor release line receives security fixes. See
[`CHANGELOG.md`](CHANGELOG.md) for the current release.
