# .agent-notes/

Audit trail for AI-agent-assisted and human-authored development.

Each note documents a specific incident, investigation, or convention
and the **mechanical gate** (lint, test, schema, CI check) created in
response. The note is the *why* that prevents a future agent or
reviewer from removing the gate without understanding its purpose.

## When to add a note

- An incident, regression, or bug that could plausibly recur
- A subtle convention that a new lint now enforces
- An investigation that produced a reusable rule

Do NOT add a note for one-off fixes with no pattern worth enforcing.

## Format

One file per incident, named `YYYY-MM-DD-<slug>.md`. Required sections:

1. **What happened** — factual description
2. **Root cause** — the structural reason, not the symptom
3. **Why prompts or review wouldn't catch it** — the argument for a gate
4. **Mechanical gate created** — files/tools, where they run
5. **Verification performed** — how the gate was validated
6. **Residual risk** — what the gate does NOT catch
7. **Classification** — see framework below; include the verdict as a
   table with one-sentence justification

## Classification framework

Every note MUST declare which class of gate it creates:

**Runtime law.** Without the gate, the code fails at runtime — parse
error, wrong behavior, data loss, security hole, outage. The gate
prevents regression of a real bug.

**Convention.** The code works either way, but the gate enforces
uniformity. Value comes from reducing cognitive load across the
codebase and from catching the subset of same-class violations that
*are* runtime bugs.

Both classes are legitimate and worth enforcing. The risk appears when
they are mixed without labels:

- Treating a convention as a law → false confidence that the gate
  prevents bugs it does not catch.
- Removing a convention because "the code works anyway" → drift that
  eventually lets a real runtime-law violation hide behind acceptable
  style noise.

Required table in the Classification section of every note:

```markdown
| | |
|---|---|
| Convention or runtime law | <Convention \| Runtime law> — <one-sentence justification> |
| Catches real bugs too? | <Yes: list of classes \| No, pure style> |
| Cost to add | <rough estimate> |
| Reversibility | <how to undo the gate> |
```

## Relation to ADRs

- **ADRs** live centrally in `estabilis-platform-tools/docs/adr/` and
  codify cross-repo decisions and principles.
- **Agent notes** live per-repo and document specific incidents and
  the local gates derived from them. An ADR may reference multiple
  agent notes as its evidence base.

## Relation to commits

The commit that introduces a gate should reference its agent note in
the body. The agent note, in turn, lists the commit(s) that motivated
the gate.
