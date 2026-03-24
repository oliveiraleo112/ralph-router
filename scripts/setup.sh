#!/usr/bin/env bash
# Ralph setup check — verifies prerequisites and initializes files
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

check_command() {
    local cmd="$1" install_hint="$2"
    if ! command -v "$cmd" &>/dev/null; then
        echo "  MISSING: $cmd  (install: $install_hint)"
        return 1
    fi
    echo "  OK:      $cmd  ($(command -v "$cmd"))"
}

echo "=== Ralph Setup Check ==="
echo ""

echo "Required tools:"
MISSING=false
check_command "jq"  "brew install jq / apt install jq"  || MISSING=true
check_command "git" "brew install git / apt install git" || MISSING=true

echo ""
echo "AI tools (at least one required):"
FOUND_TOOL=false
for tool in claude gemini codex cline amp; do
    if command -v "$tool" &>/dev/null; then
        echo "  OK:      $tool  ($(command -v "$tool"))"
        FOUND_TOOL=true
    else
        echo "  -        $tool  (not found)"
    fi
done

if [[ "$FOUND_TOOL" == "false" ]]; then
    echo "  MISSING: No AI tool found."
    echo "  Install at least one: claude, gemini, codex, cline, or amp"
    MISSING=true
fi

echo ""
echo "Initializing files..."

cd "$SCRIPT_DIR"

if [[ ! -f "prd.json" ]]; then
    echo "  Created: prd.json (empty)"
    echo '{}' > prd.json
else
    echo "  Exists:  prd.json"
fi

if [[ ! -f "progress.txt" ]]; then
    echo "  Created: progress.txt"
    { echo "# Ralph Progress Log"; echo "Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"; echo "---"; } > progress.txt
else
    echo "  Exists:  progress.txt"
fi

mkdir -p archive scripts skills/prd skills/ralph .claude/agents

echo ""
if [[ "$MISSING" == "true" ]]; then
    echo "=== Setup INCOMPLETE — fix missing dependencies above ==="
    exit 1
else
    echo "=== Setup complete ==="
fi
