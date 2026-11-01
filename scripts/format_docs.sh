#!/usr/bin/env bash
# Formats Markdown specification documents using mdformat (CommonMark + GFM)
set -euo pipefail

CHECK_ONLY=false
if [[ "${1:-}" == "--check" ]]; then
    CHECK_ONLY=true
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

# Collect portal markdown specification files
FILES=(
    ReadMe.md
    $(find content -name "*.md" | sort)
    model-runner/docs/crates/index.md
    $(find model-runner/docs/crates -name "muobserve*.md" | sort)
)

if [ "$CHECK_ONLY" = true ]; then
    echo "Checking Markdown formatting with mdformat..."
    mdformat --check --wrap keep "${FILES[@]}"
    echo "All Markdown specification documents are cleanly formatted."
else
    echo "Formatting Markdown specification documents with mdformat..."
    mdformat --wrap keep "${FILES[@]}"
    echo "Formatting complete."
fi
