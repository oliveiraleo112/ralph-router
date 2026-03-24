#!/usr/bin/env bash
# Archive the current Ralph run (prd.json + progress.txt) to archive/
# Usage: bash scripts/archive.sh [branch_name]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRD_FILE="${SCRIPT_DIR}/prd.json"
PROGRESS_FILE="${SCRIPT_DIR}/progress.txt"
ARCHIVE_DIR="${SCRIPT_DIR}/archive"

# Determine branch name
if [[ $# -gt 0 ]]; then
    BRANCH="$1"
elif [[ -f "$PRD_FILE" ]]; then
    BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
else
    BRANCH=""
fi

if [[ -z "$BRANCH" ]]; then
    BRANCH=$(git -C "$SCRIPT_DIR" branch --show-current 2>/dev/null || echo "unknown")
fi

DATE=$(date +%Y-%m-%d)
FOLDER=$(echo "$BRANCH" | sed 's|^ralph/||' | tr '/' '-')
DEST="${ARCHIVE_DIR}/${DATE}-${FOLDER}"

mkdir -p "$DEST"

ARCHIVED=false
if [[ -f "$PRD_FILE" ]]; then
    cp "$PRD_FILE" "$DEST/"
    ARCHIVED=true
fi
if [[ -f "$PROGRESS_FILE" ]]; then
    cp "$PROGRESS_FILE" "$DEST/"
    ARCHIVED=true
fi

if [[ "$ARCHIVED" == "true" ]]; then
    echo "Archived run to: $DEST"
else
    echo "Nothing to archive (no prd.json or progress.txt found)"
    exit 0
fi

# Reset progress.txt for the new run
{ echo "# Ralph Progress Log"; echo "Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"; echo "---"; } > "$PROGRESS_FILE"
echo "Reset progress.txt"
