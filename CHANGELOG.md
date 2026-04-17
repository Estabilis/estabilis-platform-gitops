# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

For versions prior to the introduction of this changelog, see the
[tag history](https://github.com/Estabilis/estabilis-platform-gitops/tags)
and the corresponding commit messages.

## [Unreleased]

### Changed

- Wire the new `lint-ignore-missing-inline` gate into pre-commit,
  CI workflow, and `just lint`. The lint itself shipped in v0.23.1
  but was not integrated into the automation layer until this entry.
  No behavior change — the script was always runnable manually.

### Documentation

- `.agent-notes/2026-04-18-ignore-missing-values-helper-consolidation.md`
  — audit note for the ignoreMissingValueFiles helper refactor that
  shipped in v0.23.1. Documents the Classification (Convention /
  uniformity-amplifier), verification performed, and residual risk.

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
