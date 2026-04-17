# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

For versions prior to the introduction of this changelog, see the
[tag history](https://github.com/Estabilis/estabilis-platform-gitops/tags)
and the corresponding commit messages.

## [Unreleased]

## Versioning

- **Major** (`v1.0.0`) — breaking chart interface changes
- **Minor** (`v0.X.0`) — new components or values, backward-compatible
- **Patch** (`v0.X.Y`) — bug fixes, value tweaks, documentation

Consumers pin the version via `repoVersion: "vX.Y.Z"` in their
`workload-bootstrap` values overlay. See
[CONTRIBUTING.md](CONTRIBUTING.md#release-process) for the release
workflow.
