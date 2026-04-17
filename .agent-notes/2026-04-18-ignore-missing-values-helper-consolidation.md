---
date: 2026-04-18
category: silent-failure-amplifier / uniformity
severity: medium-runtime
related-commits:
  - 980015c  # v0.23.1 — 17-template refactor + lint script (bundled by another session
             #          with an unrelated allow-alloy policy fix; integration into
             #          pre-commit/CI/justfile landed in the follow-up commit on this
             #          branch)
related-notes:
  - 2026-04-17-helm-trim-markers-list-concatenation.md  # the spike 2 runtime-law that this
                                                        # amplifier reduces blast radius for
related-files:
  - workload-bootstrap/templates/_helpers.tpl  # helper `workload-bootstrap.ignoreMissingValueFiles`
  - 17 templates refactored to route through the helper
gate:
  - scripts/lint-ignore-missing-inline.sh
  - .pre-commit-config.yaml
  - .github/workflows/lint.yml
---

# ignoreMissingValueFiles consolidation through the helper

## What happened

The chart defined a conditional helper
`workload-bootstrap.ignoreMissingValueFiles` (in
`workload-bootstrap/templates/_helpers.tpl`) that emits
`ignoreMissingValueFiles: true` only when both `configRepoUrl` and
`configRepoVersion` are set — the cluster has an override repository
whose files may legitimately be missing. The helper existed and was
documented, but **17 ApplicationSet templates used `ignoreMissingValueFiles: true`
inline, bypassing the helper** and emitting it unconditionally.

The inline pattern silenced ANY missing valueFile, including files
that *must* exist (e.g. the base `$values/values/workload/<component>.yaml`
or a provider-specific file derived from a bridge annotation).

## Connection to spike 2 (trim-marker concatenation, v0.22.3)

The v0.22.3 incident (`{{- /* */ -}}` concatenating two `valueFiles`
entries into a single invalid path) was masked by exactly this: the
inline `ignoreMissingValueFiles: true` silenced the resulting "file not
found" error. Spike 2 installed a gate at the template-engine layer
(catches the concatenation itself). This spike installs the gate at the
**amplifier layer** — removing the blanket silencing for clusters that
do not use the override pattern.

With this refactor, a cluster without `configRepoUrl + configRepoVersion`
now fails loudly when any `valueFile` is missing — which is exactly
where the trim-marker bug would have surfaced first if the helper had
been used consistently.

## Root cause

The helper was added as a refactor target but the migration was never
carried out. Every new template author copied the nearest existing
template as a starting point; every existing template used the inline
form; the inline form propagated by inertia. No mechanical signal
flagged the divergence from the documented helper.

## Why prompts or review wouldn't catch it

- `helm lint` accepts both forms (syntactically identical at Helm
  level).
- `helm template` produces valid YAML in both cases.
- ArgoCD accepts the resulting `ignoreMissingValueFiles: true` without
  complaint.
- Code review treats `ignoreMissingValueFiles: true` as a reasonable,
  documented ArgoCD setting and does not question whether a conditional
  helper should be used.
- A CLAUDE.md or README note saying "use the helper" is aspiration — 17
  templates prove that prompts alone do not enforce it.

## Mechanical gate created

- `scripts/lint-ignore-missing-inline.sh` — flags any literal
  `ignoreMissingValueFiles: true` line in
  `workload-bootstrap/templates/*.yaml`. The helper definition lives
  in `_helpers.tpl` and is not scanned (different extension). Any
  inline occurrence must route through
  `{{- include "workload-bootstrap.ignoreMissingValueFiles" . | nindent N }}`.
- Runs via `.pre-commit-config.yaml` locally and
  `.github/workflows/lint.yml` in CI (third parallel job after
  ApplicationSet syntax and trim-marker lints).

## Verification performed

- `./scripts/lint-ignore-missing-inline.sh` on post-refactor HEAD:
  19 files checked, 0 violations → exit 0.
- Same script against files extracted from `main` at the pre-spike
  commit (`286aec6` tree): correctly flags `kyverno.yaml:61` and
  `external-dns.yaml:36` (sampled two; all 17 would fail).
- `helm template` with `configRepoUrl=<test> configRepoVersion=<test>`:
  17 rendered Applications contain `ignoreMissingValueFiles: true`
  (identical to pre-refactor behavior).
- `helm template` without the two values: 0 rendered Applications
  contain `ignoreMissingValueFiles: true` (the behavior change — strict
  mode for non-override clusters).
- Existing lints (ApplicationSet syntax, trim-marker) continue to
  pass on the refactored templates.

## Behavior change (documented in CHANGELOG)

Clusters with `configRepoUrl + configRepoVersion` set (all current
production deployments): **zero behavior change** — output is
byte-identical to pre-refactor for this subset.

Clusters without those values set (typically test or dev deployments
that do not use the override repo pattern): `ignoreMissingValueFiles`
is now absent from rendered ApplicationSets. A missing `valueFile` now
fails the Application Sync instead of being silently skipped. This is
strictly safer — it surfaces configuration errors early.

## Residual risk

- The helper is still conditional on two specific values
  (`configRepoUrl` + `configRepoVersion`). Future contributors may add
  new templates that need `ignoreMissingValueFiles: true` for reasons
  unrelated to the override pattern (e.g. a bridge-annotation-derived
  file that may legitimately not exist for some providers). The lint
  will force them to either use the existing helper (and accept its
  condition) or extend the helper / add a new variant. That friction
  is intentional.
- The lint catches only inline `ignoreMissingValueFiles: true`. A
  different form (e.g. `ignoreMissingValueFiles: |-` with a block
  scalar, or a variable-driven value) is not flagged. None of these
  forms are currently used in the repository; a future author bypassing
  via that route should be caught in code review or by extending this
  lint.

## Classification

| | |
|---|---|
| Convention or runtime law | **Convention (uniformity-amplifier)** — no single template had a runtime bug before this spike; the gate reduces blast radius of a real runtime-law class (silent "file not found" under ArgoCD + overly permissive silencing). |
| Catches real bugs too? | **Yes** — for clusters without `configRepoUrl + configRepoVersion`, missing valueFiles now fail loudly. The spike-2 class (trim-marker concatenation) would surface first in such clusters even without the trim-marker lint. |
| Cost to add | ~45 minutes (17 mechanical edits, new lint script, audit note, CHANGELOG). |
| Reversibility | `git revert` of the spike commits restores the inline form; helper remains defined but unused until revert is undone. |
| ADR reference | ADR-0015 Known open work #1 (first amplifier gate); validates that the framework's Classification handles amplifier class (convention that reduces blast radius of a runtime law). |
