#!/usr/bin/env bash
set -euo pipefail

# Ralph Router - Remote Installer
# Usage: curl -sSL <raw-url> | bash
#    or: bash install-remote.sh [target-dir]

TARGET="${1:-$HOME/ralph}"
REPO="https://github.com/oliveiraleo112/ralph-router.git"

echo "=============================="
echo "  Ralph Router — Installer"
echo "=============================="
echo ""

# 1. Check prerequisites
echo "[1/5] Checking prerequisites..."
for cmd in git jq; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "  ❌ $cmd not found. Installing..."
        if command -v apt-get &>/dev/null; then
            sudo apt-get update -qq && sudo apt-get install -y -qq "$cmd"
        elif command -v yum &>/dev/null; then
            sudo yum install -y -q "$cmd"
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y -q "$cmd"
        else
            echo "  ⚠️  Cannot auto-install $cmd. Please install manually."
            exit 1
        fi
    else
        echo "  ✅ $cmd"
    fi
done

# 2. Clone
echo ""
echo "[2/5] Cloning ralph-router..."
if [[ -d "$TARGET" ]]; then
    echo "  ⚠️  $TARGET already exists. Pulling latest..."
    cd "$TARGET" && git pull origin main
else
    git clone "$REPO" "$TARGET"
    cd "$TARGET"
fi

# 3. Make executable
echo ""
echo "[3/5] Setting permissions..."
chmod +x ralph.sh scripts/*.sh
echo "  ✅ ralph.sh is executable"

# 4. Detect AI tools
echo ""
echo "[4/5] Detecting AI tools..."
TOOLS_FOUND=0
for tool in copilot codex qwen cline gemini claude; do
    if command -v "$tool" &>/dev/null; then
        echo "  ✅ $tool"
        TOOLS_FOUND=$((TOOLS_FOUND + 1))
    else
        echo "  ⬚  $tool (not installed)"
    fi
done

if [[ "$TOOLS_FOUND" -eq 0 ]]; then
    echo ""
    echo "  ⚠️  No AI tools found! Install at least one:"
    echo "     copilot : gh extension install github/gh-copilot"
    echo "     claude  : npm install -g @anthropic-ai/claude-code"
    echo "     codex   : npm install -g @openai/codex"
    echo "     gemini  : pip install gemini-cli"
fi

# 5. Summary
echo ""
echo "[5/5] Installation complete!"
echo "=============================="
echo "  Location : $TARGET"
echo "  Tools    : $TOOLS_FOUND detected"
echo "  Usage    :"
echo "    cd $TARGET"
echo "    cp prd.json.example prd.json"
echo "    # Edit prd.json with your stories"
echo "    ./ralph.sh --dry-run"
echo "    ./ralph.sh --tool auto 10"
echo "=============================="
