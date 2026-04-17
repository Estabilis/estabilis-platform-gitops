---
date: 2026-04-17
category: template-convention
severity: low-runtime / medium-future-risk
related-commits:
  - c7f7b06  # v0.19.2 — add spaces in `{{ index ... }}`
  - c48bfec  # v0.19.3 — enable goTemplate, `{{name}}` → `{{ .name }}`
related-files:
  - workload-bootstrap/templates/client-apps.yaml
gate:
  - scripts/lint-applicationset-templates.sh
  - .pre-commit-config.yaml
  - .github/workflows/lint.yml
---

# ApplicationSet goTemplate syntax consistency

## What happened

Two production fixes (`c7f7b06`, `c48bfec`) resolved failures where the
ArgoCD ApplicationSet controller could not render templates that used:

1. `{{ index ... }}` without spaces under `goTemplate: true`
2. `{{name}}` / `{{server}}` legacy placeholders under `goTemplate: true`
   (undefined variable — needs `.name` / `.server`)

The fixes established a convention: under `goTemplate: true`, every
backtick-escaped inner template uses spaces after `{{` and before `}}`
and a `.`-prefixed cluster-generator variable.

One file, `workload-bootstrap/templates/client-apps.yaml`, predates that
convention and uses `{{.path.basename}}`, `{{.name}}`, `{{.path.path}}` —
correct dot prefix but no spaces. Go template parses this successfully.

## Production verification

Checked against a production hub cluster on 2026-04-17 (pre-fix state):

```
NAME                              SYNC STATUS   HEALTH STATUS
dapr-<workload-cluster>           Synced        Healthy
kong-<workload-cluster>           Synced        Healthy
kong-plugins-<workload-cluster>   OutOfSync     Healthy
```

All ApplicationSet-generated wrappers render with the expected
`{basename}-{clustername}` pattern. **No runtime failure was caused by
the inconsistent syntax.** The `OutOfSync` on `kong-plugins-...` is
unrelated manifest drift.

## Root cause

Convention was established retroactively, after `client-apps.yaml` was
authored. No mechanical gate existed, so the divergence survived code
review. Review could not catch it because:

- Helm renders both `{{.X}}` and `{{ .X }}` identically (the controller
  parses the inner template, not Helm)
- ArgoCD logs no warning for either form
- A reviewer mentally normalizes style differences across 10 files
- A prompt like "use spaces under goTemplate" is aspirational — there is
  no signal when it is violated

## Why this is still worth a gate

The lint enforces a convention that is not a runtime law, but it is the
same gate that catches the genuinely broken patterns (`{{name}}` under
goTemplate, `{{index ... "y"}}` that parses ambiguously in the controller).
Maintaining a single style prevents future drift where a real bug hides
behind visible style inconsistency.

## Mechanical gate created

- `scripts/lint-applicationset-templates.sh` — scoped to
  `workload-bootstrap/templates/*.yaml`. Only lints files declaring
  `goTemplate: true` (legacy-mode files legitimately use `{{name}}`).
  Flags three classes:
  1. `` `{{X `` (no space after `{{` inside a backtick-escaped string)
  2. `` X}}` `` (no space before `}}` inside a backtick-escaped string)
  3. `` `{{name}}` `` / `` `{{server}}` `` (legacy placeholder without
     leading dot)
- `.pre-commit-config.yaml` — local hook gated on changes to
  `workload-bootstrap/templates/*.yaml`.
- `.github/workflows/lint.yml` — CI on pull_request and push to main.
  Catches `--no-verify` bypasses of the local hook.

## Verification performed

- `./scripts/lint-applicationset-templates.sh` passes on HEAD after four
  stylistic whitespace changes to `client-apps.yaml` (no semantic change).
- Running the same script against the pre-fix historical state reproduces
  the original failures — confirming the regex matches the real bug, not
  just the post-fix cleanup.
- Running the script against a synthetic template that declares
  `goTemplate: true` with `{{name}}` violations fails with a clear
  report.

## Residual risk

- The lint accepts legacy-mode files (no `goTemplate: true` declaration)
  using `{{name}}` / `{{server}}` without spaces or dots, because those
  work under ApplicationSet's legacy substitution. Five templates remain
  in this mode: `cert-manager.yaml`, `resource-quotas.yaml`,
  `network-policies.yaml`, `kube-state-metrics.yaml`,
  `client-kyverno-exceptions.yaml`. Migrating them to `goTemplate: true`
  for uniformity is a candidate for a **follow-up spike**.
- A template declaring `goTemplate: true` but still using `{{name}}` *is*
  caught by this gate.
- The lint does not validate that the rendered YAML is deployable — only
  that its inner-template syntax is consistent. Runtime validation would
  require a kind-based integration test, which is out of scope for this
  spike.

## Classification

| | |
|---|---|
| Convention or runtime law | Convention (the specific violations found caused no runtime failure) |
| Catches real bugs too? | Yes — `{{name}}` under goTemplate and `{{index ...}}` parse ambiguity |
| Cost | ~1 hour of spike work, <50 ms per CI run |
| Reversibility | `git revert` of the spike commit removes all artifacts |
| ADR reference | Candidate primary example for ADR-0015 (agent-safe platform) |
