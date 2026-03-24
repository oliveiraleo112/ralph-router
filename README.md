# Ralph

An autonomous AI agent loop that runs AI coding tools repeatedly until all items in a PRD (Product Requirements Document) are complete.

Based on the [Ralph pattern](https://github.com/snarktank/ralph) by Geoffrey Huntley ([ghuntley.com/ralph](https://ghuntley.com/ralph/)).

## How It Works

Ralph spawns a fresh AI instance each iteration with no memory of previous work. Each iteration:

1. Reads `prd.json` to find the next story where `passes: false`
2. Implements that single story
3. Runs quality checks (typecheck, lint, tests)
4. Commits if checks pass, marks the story `passes: true`
5. Appends learnings to `progress.txt`
6. Repeats until all stories are complete or max iterations reached

Memory between iterations persists only via: git history, `progress.txt`, `prd.json`, and `CLAUDE.md`/`AGENTS.md`.

## Prerequisites

- At least one AI tool: `claude`, `gemini`, `codex`, `cline`, or `amp`
- `jq` and `git`
- A git repository for your project

```bash
bash scripts/setup.sh
```

## Quick Start

```bash
# 1. Create a PRD (use the /prd skill in Claude)
# 2. Convert PRD to prd.json (use the /ralph skill in Claude)
# 3. Run Ralph
./ralph.sh
```

## Usage

```bash
# Auto mode (smart router — default), 10 iterations
./ralph.sh

# Specify max iterations
./ralph.sh 20

# Use a specific AI tool
./ralph.sh --tool gemini 15
./ralph.sh --tool codex 10
./ralph.sh --tool cline 10
./ralph.sh --tool qwen 10
./ralph.sh --tool copilot 10
./ralph.sh --tool claude 15

# Control retries per tool in auto mode
./ralph.sh --retries 3

# Run parallel workers (git worktrees)
./ralph.sh --parallel 3

# Preview without running
./ralph.sh --dry-run

# Verbose output
./ralph.sh --verbose 5

# Override branch
./ralph.sh --branch my-feature-branch
```

## Smart Router

By default, Ralph uses `--tool auto` which tries AI tools in priority order:

```
copilot → codex → qwen → cline → gemini → claude
```

- **Skips** tools not installed on the system
- **Retries** each tool N times (`--retries`, default: 2) before falling back
- **Falls back** to the next tool in the chain on failure or rate limit
- **Claude** is always last resort — most capable but most expensive

Tool tiers:
- `copilot` — 💰 Paid (GPT-5 mini)
- `codex` — 🆓 Free tier
- `qwen` — 🆓 Free tier
- `cline` — 🆓 Free tier
- `gemini` — 💰 Paid (large model)
- `claude` — 💎 Premium (emergency only)

## Creating PRDs

Use the `/prd` skill in Claude Code to generate a PRD:

```
/prd Add a task priority system to the app
```

This asks clarifying questions and produces a structured PRD saved to `tasks/prd-[feature].md`.

## Converting PRDs to JSON

Use the `/ralph` skill to convert your PRD to `prd.json`:

```
/ralph
```

This reads your PRD and produces `prd.json` with properly sized, ordered user stories.

## prd.json Format

```json
{
  "project": "MyApp",
  "branchName": "ralph/task-priority",
  "description": "Task Priority System",
  "userStories": [
    {
      "id": "US-001",
      "title": "Add priority field to database",
      "description": "As a developer, I need to store task priority.",
      "acceptanceCriteria": [
        "Add priority column: 'high'|'medium'|'low' (default 'medium')",
        "Migration runs successfully",
        "Typecheck passes"
      ],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
```

See `prd.json.example` for a complete example.

## Subagents

Ralph includes two Claude subagents in `.claude/agents/`:

- **qa-reviewer** — verifies acceptance criteria after implementation
- **researcher** — explores codebase patterns before implementation

Invoke them from within Claude Code:
```
Use qa-reviewer to verify the last completed story.
```

## Story Sizing Tips

Each story should be completable in one AI context window:

- Add a database column and migration
- Add a UI component to an existing page
- Update a server action with new logic
- NOT "Build the entire dashboard" — split this up
- NOT "Add authentication" — split into schema, middleware, login UI, sessions

## File Structure

```
ralph/
├── ralph.sh                  # Main loop
├── CLAUDE.md                 # Prompt for Claude Code
├── AGENTS.md                 # Agent reference
├── README.md                 # Documentation
├── prompt.md                 # Prompt for Amp and other tools
├── prd.json.example          # PRD format example
├── progress.txt              # Append-only learnings log
├── .claude/agents/
│   ├── qa-reviewer.md        # QA subagent
│   └── researcher.md         # Research subagent
├── skills/
│   ├── prd/SKILL.md          # PRD generation skill
│   └── ralph/SKILL.md        # PRD→JSON conversion skill
└── scripts/
    ├── setup.sh              # Setup / prerequisite check
    └── archive.sh            # Archive previous run
```

## References

- [snarktank/ralph](https://github.com/snarktank/ralph) — official Ralph repo
- [ghuntley.com/ralph](https://ghuntley.com/ralph/) — Geoffrey Huntley's explanation
