# Contributing

This repository is public but **not currently accepting pull requests**.
Development happens through internal workflows. If you find a problem or
have a suggestion, please open an issue — we read all of them.

## Reporting issues

Open an issue at
[github.com/Estabilis/estabilis-platform-gitops/issues](https://github.com/Estabilis/estabilis-platform-gitops/issues)
and include:

- **What you observed** — ArgoCD logs, Application status, `kubectl` output
  where relevant
- **What you expected** — the behavior you believed correct
- **Environment** — ArgoCD version, workload cluster Kubernetes version,
  chart version (see [`workload-bootstrap/Chart.yaml`](workload-bootstrap/Chart.yaml))
- **How to reproduce** — minimal values overlay or chart snippet if possible

**Security-sensitive issues:** do not open a public issue. See
[SECURITY.md](SECURITY.md).

## Pull requests

External pull requests are not currently accepted. PRs will be closed with
a reference to this document; please open an issue instead so we can
discuss the problem. If we agree that the change is welcome, we may
invite a PR at that point.

---

## Internal development (for maintainers)

This section documents the local setup and gates that apply to anyone
with write access to this repository.

### Prerequisites

| Tool | Purpose | Install |
|------|---------|---------|
| [just](https://just.systems/) | Task runner | `brew install just` / `cargo install just` |
| [pre-commit](https://pre-commit.com/) | Git hooks | `pip install --user pre-commit` |

### Setup

```bash
git clone https://github.com/Estabilis/estabilis-platform-gitops.git
cd estabilis-platform-gitops
just install    # installs pre-commit and activates the git hooks
```

### Local checks

```bash
just lint       # ApplicationSet template lint (scoped to goTemplate files)
just lint-all   # runs all pre-commit hooks on every file in the repo
```

CI (`.github/workflows/lint.yml`) runs the same gates on every pull
request and push to `main`, so `git commit --no-verify` bypasses are
caught at PR time.

### Branch and commit conventions

- Branch from `main`. Prefixes: `feat/`, `fix/`, `chore/`, `docs/`, `spike/`.
- Commit messages follow the Conventional Commits format used in existing
  history: `type(scope): description (vX.Y.Z)`. The version suffix is
  optional for non-release commits.

### Versioning

This repo uses [Semantic Versioning](https://semver.org/). A release bumps
**three artefacts in the same commit**:

1. `workload-bootstrap/Chart.yaml` — both `version` and `appVersion`
2. `workload-bootstrap/values.yaml` — `repoVersion` field
3. A git tag `vX.Y.Z` matching the above

Release cadence:

- **Major** (`v1.0.0`) — breaking chart interface changes (removed values,
  renamed templates, ApplicationSet selector changes)
- **Minor** (`v0.X.0`) — new components, new values, backward-compatible
  features
- **Patch** (`v0.X.Y`) — bug fixes, value tweaks, documentation

### Release process

```bash
# 1. Move [Unreleased] entries in CHANGELOG.md to the new version header
# 2. Bump version + appVersion in workload-bootstrap/Chart.yaml
# 3. Bump repoVersion in workload-bootstrap/values.yaml
# 4. Commit
git add CHANGELOG.md workload-bootstrap/
git commit -m "release: vX.Y.Z"

# 5. Tag
git tag vX.Y.Z

# 6. Push
git push origin main --tags
```

Consumers pin the version via `repoVersion: "vX.Y.Z"` in their
`workload-bootstrap` values overlay. An upstream bump without a
consumer-side version bump has no effect.
