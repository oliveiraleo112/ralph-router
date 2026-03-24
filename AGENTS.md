# Ralph — Autonomous AI Agent Loop

## Commands

```bash
# Auto mode (smart router — default)
./ralph.sh [max_iterations]

# Specify a specific tool
./ralph.sh --tool claude 15
./ralph.sh --tool gemini 20
./ralph.sh --tool codex 10
./ralph.sh --tool cline 10
./ralph.sh --tool qwen 10
./ralph.sh --tool copilot 10

# Control retries per tool in auto mode
./ralph.sh --retries 3

# Run with parallel workers (git worktrees)
./ralph.sh --parallel 3 15

# Dry run — preview without executing
./ralph.sh --dry-run

# Verbose output
./ralph.sh --verbose 5

# Setup check
bash scripts/setup.sh

# Archive current run manually
bash scripts/archive.sh
```

## Key Files

| File | Purpose |
|------|---------|
| `ralph.sh` | Main loop script with smart router |
| `CLAUDE.md` | Prompt template for Claude Code |
| `prompt.md` | Prompt template for all other tools |
| `prd.json` | User stories with `passes` status |
| `progress.txt` | Append-only learnings log |
| `skills/prd/SKILL.md` | PRD generation skill |
| `skills/ralph/SKILL.md` | PRD→JSON conversion skill |
| `.claude/agents/qa-reviewer.md` | QA subagent |
| `.claude/agents/researcher.md` | Research subagent |

## Architecture

Each iteration spawns a **fresh AI instance** with clean context. Memory persists only via:

- **Git history** (commits with story IDs)
- **`progress.txt`** (append-only learnings)
- **`prd.json`** (story status, `passes: true/false`)
- **`CLAUDE.md` / `AGENTS.md`** (discovered patterns)

## Smart Router

When `--tool auto` (default), Ralph tries tools in priority order:

```
copilot → codex → qwen → cline → gemini → claude
```

- Skips tools not installed
- Retries each tool `--retries` times (default: 2) before falling back
- Claude is last resort (emergency only — most expensive)
- Tool tier labels: 💰 Paid, 🆓 Free tier, 💎 Premium

## Patterns

- Stories must be small enough to complete in one context window
- Order stories by dependency: schema → backend → frontend → dashboard
- Always include "Typecheck passes" in acceptance criteria
- UI stories must include browser verification
- Commit after each story — don't batch multiple stories in one commit
- Keep `progress.txt` Codebase Patterns section updated with reusable findings
- When cloning external repositories non-interactively, use GIT_TERMINAL_PROMPT=0 and git clone --depth=1 to avoid interactive prompts and reduce transfer size.
- Python runtime environments may be managed by the OS (PEP 668). Installation scripts should detect this and prefer virtual environments (python3 -m venv) or pipx rather than system-wide pip installs.
- Frontend Dockerfile should expose build args for Vite envs (VITE_API_URL, VITE_CHATWOOT_URL) so CI can set runtime endpoints at build time.
- Nginx in frontend image should proxy /api/ to the backend service name (use 'dashboard-api' in this project) to keep frontend runtime URLs relative and avoid CORS complexity.
- Backend Dockerfiles should use a builder stage to install Python dependencies to an install prefix and set PYTHONPATH in the final image to reduce runtime image footprint and keep build tools out of the final image.
- Pattern: Trap handlers should kill worker PIDs and wait before removing worktrees to avoid ENOENT/uv_cwd errors.

## Deploy patterns
- When upstream frontend build is unavailable, provide a static placeholder under `frontend-dist/` so nginx can serve a health page during initial deploys.
- Mount custom nginx config at `/etc/nginx/conf.d/default.conf` to enable api proxying to `dashboard-api:8000`.

## Setup scripts
- scripts/setup-env.sh: collects env vars, validates Chatwoot token against /api/v1/profile and optionally validates Redis with redis-cli. Writes .env and .env.example with restricted permissions.

## Deployment patterns
- Deployment ports: frontend 3010, backend 8000
- Docker network: minha_rede for inter-service comms

