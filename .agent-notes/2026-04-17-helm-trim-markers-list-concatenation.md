---
date: 2026-04-17
category: helm-template-quirk / silent-failure
severity: high-runtime
related-commits:
  - 5b79a2c  # v0.22.3 — removed the offending comment, external-dns
             # cloudflare values now load correctly
related-files:
  - workload-bootstrap/templates/external-dns.yaml (pre-v0.22.3)
gate:
  - scripts/lint-helm-trim-markers.sh
  - .pre-commit-config.yaml
  - .github/workflows/lint.yml
---

# Helm trim-marker comments concatenate YAML list items

## What happened

A Go template comment with both trim markers — `{{- /* ... */ -}}` —
was placed between two YAML list items inside an ApplicationSet
`valueFiles` list:

```yaml
valueFiles:
  - $values/values/workload/external-dns.yaml
  {{- /* Provider-specific values file selected by bridge annotation */ -}}
  - $values/values/workload/external-dns-{{ `{{ index .metadata.annotations "estabilis.io/bridge.dns-provider" }}` }}.yaml
```

Helm rendered the comment to empty and consumed the whitespace on both
sides, producing:

```yaml
valueFiles:
  - $values/values/workload/external-dns.yaml- $values/values/workload/external-dns-cloudflare.yaml
```

ArgoCD parsed that as a single `valueFiles` entry — a path that does
not exist. With `ignoreMissingValueFiles: true` the error was swallowed
silently. The upstream `external-dns` chart fell back to its default
`provider: aws`, and the running pod tried to authenticate to the AWS
IMDS endpoint while holding Cloudflare credentials. No DNS record was
ever created in Cloudflare for the workload cluster.

## Root cause

Three compounding decisions produced a silent failure:

1. **Template output**: `{{- ... -}}` trim markers on a comment render
   to empty and remove all surrounding whitespace — including the
   newlines that keep YAML list items separate.
2. **ArgoCD setting**: `ignoreMissingValueFiles: true` suppresses the
   "file not found" error that would otherwise fail the Application.
3. **Chart default**: the upstream `external-dns` chart defaults to
   `provider: aws`. Without the cloudflare values file loading, the
   provider silently reverted to AWS.

Each individually is a reasonable, documented behavior. The sum is a
production Application reported `Synced / Healthy` while doing nothing
useful.

## Why prompts or review wouldn't catch it

- `helm lint` accepts the template — the Go template syntax is valid.
- `helm template` produces YAML that is *syntactically* valid; it
  takes attention to notice that one list entry contains two paths
  mashed together.
- ArgoCD's UI shows `Synced / Healthy` for the Application because the
  apply succeeded; the misbehavior is inside the workload pod.
- Reviewers scan diffs line by line and treat `{{- ... -}}` as
  "whitespace control" without simulating the render mentally in list
  contexts.
- A prompt like "be careful with trim markers" is aspirational — there
  is no signal at commit or PR time when the rule is violated.

## Mechanical gate created

- `scripts/lint-helm-trim-markers.sh` — greps each file under
  `workload-bootstrap/templates/` for the exact pattern
  `{{- /* ... */ -}}` (comment with both trim markers). A comment with
  both trim markers renders to empty and consumes whitespace on both
  sides — almost never useful, and dangerous in YAML list contexts.
- Hooks: runs from `.pre-commit-config.yaml` locally and
  `.github/workflows/lint.yml` in CI.

## Verification performed

- `./scripts/lint-helm-trim-markers.sh` on current HEAD (post-fix
  `5b79a2c`): 19 files checked, 0 violations → exit 0.
- `./scripts/lint-helm-trim-markers.sh` against the file state at the
  parent commit (`4ebecee`): correctly flags
  `workload-bootstrap/templates/external-dns.yaml:33` with the exact
  offending line.
- Synthetic test with a minimal YAML file containing the pattern: the
  lint fails; an adjacent file using `{{/* */}}` without trim markers
  passes (safe alternative documented).

## Residual risk

This gate catches the **template-side** root cause, but the incident
was amplified by two other layers that remain unguarded:

- **`ignoreMissingValueFiles: true` without justification.** Many
  templates use this setting for legitimate optional overlays. A
  future gate should require an inline `# justify: ...` comment
  explaining why silent skip is the correct behavior for each
  occurrence — forcing the author to acknowledge the silencing.
- **No render-time validation in CI.** A `helm template` step that
  parsed the output and asserted structural invariants (every
  `valueFiles` entry is a single path, each list item is well-formed)
  would catch this plus an entire class of similar concatenation and
  indentation bugs. Deferred to a dedicated render-check spike because
  it requires `helm` in CI, chart dependency setup, and defining the
  invariants.

Both are candidates for follow-up spikes.

## Classification

| | |
|---|---|
| Convention or runtime law | **Runtime law** — production silently ran with the wrong DNS provider; no records were created, endpoints were unreachable by FQDN. |
| Catches real bugs too? | Yes — catches the exact class that produced v0.22.3; narrow enough to have zero false positives on current templates. |
| Cost to add | ~30 minutes (script + hooks + this note). |
| Reversibility | `git revert` of the spike commits removes all artefacts; no persistent state. |
| ADR reference | Second reference case for ADR-0015. A runtime-law gate, complementing the convention gate from the first spike. |
