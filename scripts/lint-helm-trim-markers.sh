#!/usr/bin/env bash
# lint-helm-trim-markers.sh
#
# Flags Go template comments that use BOTH trim markers — `{{- /* */ -}}`.
# A trim-marked comment renders to empty and consumes all surrounding
# whitespace (including newlines). When placed between two YAML list
# items, the two items collapse into a single (invalid) line, e.g.:
#
#   - $values/values/workload/external-dns.yaml        ─┐
#   {{- /* Provider-specific file */ -}}                │  renders as:
#   - $values/values/workload/external-dns-foo.yaml    ─┘  "- ...yaml- $values/..."
#
# That output is consumed by ArgoCD as a single valueFile path, which
# does not exist; with `ignoreMissingValueFiles: true` the error is
# swallowed silently and the chart falls back to defaults.
#
# Rule: never use `{{- /* */ -}}` (both trim markers on a comment).
# If you need a comment, use `{{/* */}}` without trim markers, which is
# safe in YAML list contexts. If you need to suppress a specific blank
# line, use only one trim marker on a non-empty template construct.
#
# See: .agent-notes/2026-04-17-helm-trim-markers-list-concatenation.md

set -euo pipefail

TEMPLATE_DIR="${LINT_TEMPLATE_DIR:-workload-bootstrap/templates}"

if [ ! -d "$TEMPLATE_DIR" ]; then
    echo "lint-helm-trim-markers: directory not found: $TEMPLATE_DIR" >&2
    exit 2
fi

exit_code=0
checked=0

for file in "$TEMPLATE_DIR"/*.yaml; do
    [ -f "$file" ] || continue
    checked=$((checked + 1))

    # Match: {{-  /*  ... */  -}}
    # Space-tolerant around the trim markers; comment body ignored.
    violations=$(grep -nE '\{\{-[[:space:]]*/\*.*\*/[[:space:]]*-\}\}' "$file" || true)

    if [ -n "$violations" ]; then
        echo "[FAIL] $file"
        printf '%s\n' "$violations" | sed 's/^/        trim-marked empty template eats surrounding whitespace: /'
        echo
        exit_code=1
    fi
done

if [ "$exit_code" -eq 0 ]; then
    echo "lint-helm-trim-markers: OK (checked=$checked files)"
else
    echo "lint-helm-trim-markers: FAIL — see violations above" >&2
    echo "Reference: .agent-notes/2026-04-17-helm-trim-markers-list-concatenation.md" >&2
fi

exit $exit_code
