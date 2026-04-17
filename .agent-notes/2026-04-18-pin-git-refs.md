---
date: 2026-04-18
category: supply-chain / reproducibility
severity: high-runtime
related-commits:
  - (this spike — bumps v0.24.1)
related-notes:
  - 2026-04-17-applicationset-gotemplate-syntax.md  # first Convention gate
  - 2026-04-17-helm-trim-markers-list-concatenation.md  # first Runtime-law gate
  - 2026-04-18-ignore-missing-values-helper-consolidation.md  # uniformity-amplifier
related-files:
  - workload-bootstrap/templates/_helpers.tpl                  # gitopsSource helper
  - workload-bootstrap/templates/client-kyverno-exceptions.yaml
  - workload-bootstrap/templates/client-apps.yaml
gate:
  - scripts/lint-pin-git-refs.sh
  - .pre-commit-config.yaml
  - .github/workflows/lint.yml
---

# Pin all git references — no HEAD, main, or master fallbacks

## What happened

Four ApplicationSet template locations used the pattern
`{{ .Values.clientGitopsRepoVersion | default "HEAD" }}` (or the
`| quote`d form) as the `targetRevision` / `revision` value for a
client's gitops repository:

```yaml
targetRevision: {{ .Values.clientGitopsRepoVersion | default "HEAD" | quote }}
```

Affected templates:

| File | Line | Context |
|---|---|---|
| `workload-bootstrap/templates/_helpers.tpl` | 170 | `gitopsSource` helper used by all client-gitops Applications |
| `workload-bootstrap/templates/client-kyverno-exceptions.yaml` | 44 | Per-cluster Application for client Kyverno exceptions |
| `workload-bootstrap/templates/client-apps.yaml` | 40 | `git` generator `revision` |
| `workload-bootstrap/templates/client-apps.yaml` | 59 | Template source `targetRevision` |

If a cluster had `clientGitopsRepoUrl` set but the operator forgot to
pin `clientGitopsRepoVersion`, the chart silently rendered
`targetRevision: "HEAD"` — ArgoCD dutifully tracked whatever the
upstream branch pointed at, with no indication that pinning was
missing.

## Why this is a runtime law, not a convention

Running on `HEAD` is observable, but the failure modes are supply-chain
material:

1. **Reproducibility collapses.** There is no way to answer "what chart
   version was running in cluster X at time Y?" after the fact, because
   the answer depends on `HEAD` resolution order at the moment of
   sync. A rollback target does not exist.
2. **Audit trail is unverifiable.** Compliance or security reviews that
   pin production to a known-good artefact cannot do so. Every sync
   potentially upgrades to untested code.
3. **Blast radius is unbounded.** A force-push, a bad merge, or a
   mistaken commit to the upstream branch propagates immediately to
   every cluster resolving `HEAD`. There is no canary, no phased
   rollout, no opportunity to revert before impact.
4. **Silent failure.** The cluster reports `Synced / Healthy` while
   running untracked code. The ArgoCD UI shows the branch name but
   not the SHA as a problem.

The user's long-standing memory rule (`feedback_pin_all_refs`) already
prohibited unpinned targetRevisions. This spike moves the rule from
operator-memory (prose) to chart-contract (mechanical gate + render-time
`required` failure).

## Root cause

Early authors of the client-gitops helpers added the `default "HEAD"`
as a convenience for testing. The convenience was never removed. The
helpers are inherited by every client-gitops Application, so the
anti-pattern was invisibly replicated.

## Why prompts or review wouldn't catch it

- Helm renders `default "HEAD"` correctly — no lint warning.
- ArgoCD accepts `targetRevision: "HEAD"` without complaint.
- Code review treats `| default "HEAD"` as a defensive fallback
  rather than as the explicit removal of pinning.
- An operator's prose rule ("always pin refs") is an aspiration until a
  gate rejects the pattern at commit time.

## Mechanical gate created

### Template-level: `required` instead of `default`

The four occurrences now use:

```yaml
targetRevision: {{ required "clientGitopsRepoVersion is required when clientGitopsRepoUrl is set" .Values.clientGitopsRepoVersion | quote }}
```

This shifts detection from ArgoCD sync time (silent) to
`helm template` / `helm lint` time (loud). A misconfigured cluster
fails to render long before it can mis-sync.

### Repo-level: `scripts/lint-pin-git-refs.sh`

Flags any `default "(HEAD|main|master|latest)"` in
`workload-bootstrap/templates/*.{yaml,tpl}`. Narrow and targeted: semver
tags (`v1.2.3`) and commit SHAs do not collide with these tokens.

Wired into `.pre-commit-config.yaml` (local), `.github/workflows/lint.yml`
(CI), and `justfile` (`just lint`).

## Verification performed

- `./scripts/lint-pin-git-refs.sh` on post-fix HEAD: 20 files checked
  (19 `.yaml` + 1 `.tpl`), 0 violations → exit 0.
- Same script against the file tree at `main` before this spike:
  correctly flags `_helpers.tpl:170`, `client-kyverno-exceptions.yaml:44`,
  `client-apps.yaml:40`, `client-apps.yaml:59`.
- `helm template` with `clientGitopsRepoUrl=<test> deploymentId=<test>`
  (but no `clientGitopsRepoVersion`): fails with
  `Error: execution error ... clientGitopsRepoVersion is required when clientGitopsRepoUrl is set`.
- `helm template` with all three set: renders 53 `targetRevision`
  entries cleanly.
- `helm template` with none set: client templates gated-off correctly;
  no error; no `targetRevision: HEAD` in the output.
- The three pre-existing lints continue to pass.

## Residual risk

- **Scope limited to ApplicationSet templates in `workload-bootstrap/`.**
  Other repositories (estabilis-platform, estabilis-workload) have
  their own Applications with `targetRevision`. Each repo needs this
  gate independently — not copied from here, installed per repo.
- **Literal tokens only.** The lint flags `default "HEAD"`,
  `default "main"`, etc. A variable-driven fallback
  (`default .Values.someDefault`) where `someDefault` evaluates to
  `HEAD` is not caught. None of this pattern exists today; a future
  author attempting the bypass is caught at code review.
- **No enforcement that values files pin semver tags.** The gate
  enforces the *mechanism* (no default fallback), not the *value* set
  by the consumer. A consumer setting `clientGitopsRepoVersion: main`
  is still allowed. Defending against that is a separate spike, likely
  requiring a JSON Schema or value validation helper.

## Classification

| | |
|---|---|
| Convention or runtime law | **Runtime law** — `targetRevision: HEAD` produces supply-chain material failure modes (lost reproducibility, broken audit, unbounded blast radius). The gate prevents regression of a real class. |
| Catches real bugs too? | Yes — four active occurrences flagged against pre-fix `main`; each was a latent vulnerability for any cluster that set `clientGitopsRepoUrl` without `clientGitopsRepoVersion`. |
| Cost to add | ~45 minutes total (recon, four template edits, lint script, integration, CHANGELOG, audit note). |
| Reversibility | `git revert` of the spike commit restores the `default "HEAD"` fallbacks. The lint script is removed in the same revert. |
| ADR reference | ADR-0015 Known open work #5 (pin-all-references lint). First runtime-law gate at the supply-chain layer (previous runtime-law gate was at the template-engine layer). |
