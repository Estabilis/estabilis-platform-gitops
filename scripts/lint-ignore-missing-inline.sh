#!/usr/bin/env bash
# lint-ignore-missing-inline.sh
#
# Flags inline `ignoreMissingValueFiles: true` in ApplicationSet
# templates. Every occurrence must go through the shared helper
# `workload-bootstrap.ignoreMissingValueFiles` (defined in
# `workload-bootstrap/templates/_helpers.tpl`), which emits the key
# conditionally — only when a cluster has both `configRepoUrl` and
# `configRepoVersion` set. Clusters without a configured override
# repository get strict mode, which surfaces missing valueFile paths
# as errors instead of silencing them (amplifying the class of bugs
# that produced v0.22.3 — see spike 2).
#
# Rule: any literal `ignoreMissingValueFiles: true` line in
# `workload-bootstrap/templates/*.yaml` is a violation. The helper
# definition lives in `_helpers.tpl`, which this lint does not scan.
#
# See: .agent-notes/2026-04-18-ignore-missing-values-helper-consolidation.md

set -euo pipefail

TEMPLATE_DIR="${LINT_TEMPLATE_DIR:-workload-bootstrap/templates}"

if [ ! -d "$TEMPLATE_DIR" ]; then
    echo "lint-ignore-missing-inline: directory not found: $TEMPLATE_DIR" >&2
    exit 2
fi

exit_code=0
checked=0

for file in "$TEMPLATE_DIR"/*.yaml; do
    [ -f "$file" ] || continue
    checked=$((checked + 1))

    # Match literal `ignoreMissingValueFiles: true` (any leading whitespace,
    # any trailing whitespace). Excludes the helper definition file because
    # it is named `_helpers.tpl`, not `.yaml`.
    violations=$(grep -nE '^[[:space:]]*ignoreMissingValueFiles:[[:space:]]*true[[:space:]]*$' "$file" || true)

    if [ -n "$violations" ]; then
        echo "[FAIL] $file"
        printf '%s\n' "$violations" | sed 's|^|        inline ignoreMissingValueFiles must use the helper: |'
        echo "        Replace with: {{- include \"workload-bootstrap.ignoreMissingValueFiles\" . | nindent N }}"
        echo
        exit_code=1
    fi
done

if [ "$exit_code" -eq 0 ]; then
    echo "lint-ignore-missing-inline: OK (checked=$checked files)"
else
    echo "lint-ignore-missing-inline: FAIL — see violations above" >&2
    echo "Reference: .agent-notes/2026-04-18-ignore-missing-values-helper-consolidation.md" >&2
fi

exit $exit_code
