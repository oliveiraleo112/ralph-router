#!/usr/bin/env bash
set -euo pipefail
TARGET_DIR="/home/ubuntu/servicos/new-dash-chatwoot"
REPO="https://github.com/oliveiraleo112/New_dash_chatwoot.git"
mkdir -p "$(dirname "$TARGET_DIR")"
if [ -d "$TARGET_DIR/.git" ]; then
  echo "Repo already cloned at $TARGET_DIR"
else
  echo "Cloning $REPO -> $TARGET_DIR"
  GIT_TERMINAL_PROMPT=0 git clone --depth=1 "$REPO" "$TARGET_DIR"
fi
# Frontend install
if [ -f "$TARGET_DIR/package.json" ]; then
  cd "$TARGET_DIR"
elif [ -f "$TARGET_DIR/frontend/package.json" ]; then
  cd "$TARGET_DIR/frontend"
elif [ -f "$TARGET_DIR/web/package.json" ]; then
  cd "$TARGET_DIR/web"
else
  echo "No package.json found for frontend; skipping npm install"
  FRONTEND_SKIPPED=1
fi
if [ -z "${FRONTEND_SKIPPED-}" ] && [ -f package.json ]; then
  if command -v npm >/dev/null 2>&1; then
    echo "Installing npm deps in $(pwd)"
    npm ci --no-audit --no-fund || npm install --no-audit --no-fund
  else
    echo "npm not found; skipping frontend install"
  fi
fi
# Backend install
REQ="$TARGET_DIR/agrofel-dashboard-api/requirements.txt"
if [ -f "$REQ" ]; then
  if command -v pip3 >/dev/null 2>&1; then
    echo "Installing Python deps from $REQ"
    pip3 install --user -r "$REQ"
  else
    echo "pip3 not found; skipping backend pip install"
  fi
else
  echo "No backend requirements.txt at $REQ; skipping"
fi

echo "Setup script finished"
