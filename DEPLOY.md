# Deployment Guide

## Overview
This document describes how to deploy the dashboard and API locally or in Docker Compose for the Ralph project.

## Prerequisites
- Docker & Docker Compose
- Bash, git, and basic Unix tools
- (Optional) Access to Chatwoot instance and a user access token

## Quick start (Docker Compose)
1. Copy example env: cp prd.json.example .env (or use scripts/setup-env.sh as needed)
2. Build and start services:

```bash
docker compose build --quiet && docker compose up -d
```

3. Frontend will be served on port 3010 (host). API listens on internal port 8000.

## Environment and secrets
- Use scripts/setup-env.sh to collect env vars and validate Chatwoot token.
- Chatwoot URL used in this project: https://chatwoot.agrofel.com.br
- Provide Chatwoot user_access_token as BEARER token in .env; validated via GET /api/v1/profile

## Ports and network
- Frontend: 3010 (host)
- Backend (dashboard-api): 8000 (internal)
- Docker network: minha_rede (services should join this network to communicate)

## Authentication flow
1. Frontend obtains API endpoints from runtime env (VITE_API_URL).
2. User authenticates and the backend stores Bearer token (configured via .env).
3. Backend validates Chatwoot token by calling GET /api/v1/profile.

## Troubleshooting
- If frontend cannot reach API: ensure docker compose network `minha_rede` is active and frontend proxies /api/ to dashboard-api.
- If workers or build scripts produce __pycache__ or .pyc files: ensure .gitignore contains those patterns and remove tracked caches with `git rm -r --cached __pycache__`.
- If you see ENOENT / uv_cwd errors during parallel runs: ensure worker PIDs are killed and waited-for before removing worktrees (see ralph.sh patterns).

## Notes
- Use `./ralph.sh --dry-run` for a dry run of the orchestration tool.
- This file is intentionally concise; expand sections with deployment-specific commands or cloud instructions as needed.
