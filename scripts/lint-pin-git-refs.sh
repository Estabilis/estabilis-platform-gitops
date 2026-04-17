#!/usr/bin/env bash
# lint-pin-git-refs.sh
#
# Flags `default "X"` fallbacks applied to git references where X is an
# unpinned name — `HEAD`, `main`, `master`, `latest`. ArgoCD accepts
# these as valid `targetRevision` / `revision` values, which silently
# couples the cluster's live state to whatever the upstream branch
# happens to point at. That coupling defeats:
#
#   - Reproducibility: no way to say "this cluster ran chart X at time Y"
#   - Blast-radius control: a force-push or bad merge rewrites every
#     cluster that resolved HEAD at that moment
#   - Audit: compliance reviews cannot pin production to a known-good
#     artefact
#
# Rule: every git reference in an ApplicationSet template must be
# pinned to a semver tag or a commit SHA. If the upstream may be
# unset, fail loudly via `required`, not silently via `default "HEAD"`.
#
# See: .agent-notes/2026-04-18-pin-git-refs.md

set -euo pipefail

TEMPLATE_DIR="${LINT_TEMPLATE_DIR:-workload-bootstrap/templates}"

if [ ! -d "$TEMPLATE_DIR" ]; then
    echo "lint-pin-git-refs: directory not found: $TEMPLATE_DIR" >&2
    exit 2
fi

exit_code=0
checked=0

# Match `default "X"` where X is one of the unpinned tokens. Case-
# sensitive by design — semver tags (v1.2.3) and commit SHAs do not
# collide with these tokens.
PATTERN='default[[:space:]]+"(HEAD|main|master|latest)"'

for file in "$TEMPLATE_DIR"/*.yaml "$TEMPLATE_DIR"/*.tpl; do
    [ -f "$file" ] || continue
    checked=$((checked + 1))

    violations=$(grep -nE "$PATTERN" "$file" || true)

    if [ -n "$violations" ]; then
        echo "[FAIL] $file"
        printf '%s\n' "$violations" | sed 's|^|        unpinned git ref (use `required`, not `default`): |'
        echo
        exit_code=1
    fi
done

if [ "$exit_code" -eq 0 ]; then
    echo "lint-pin-git-refs: OK (checked=$checked files)"
else
    echo "lint-pin-git-refs: FAIL — see violations above" >&2
    echo "Reference: .agent-notes/2026-04-18-pin-git-refs.md" >&2
fi

exit $exit_code
