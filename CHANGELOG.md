# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

For versions prior to the introduction of this changelog, see the
[tag history](https://github.com/Estabilis/estabilis-platform-gitops/tags)
and the corresponding commit messages.

## [Unreleased]

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
