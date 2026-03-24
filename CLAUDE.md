# Ralph Agent Instructions

You are an autonomous coding agent working inside the Ralph loop.

## Your Task

1. Read `prd.json` (same directory as this file)
2. Read `progress.txt` — check the **Codebase Patterns** section FIRST
3. Ensure you're on the correct branch from `prd.json` → `branchName`. If not, check it out or create from main.
4. Pick the **highest priority** user story where `passes: false`
5. Implement that SINGLE user story
6. Run quality checks: typecheck, lint, tests (use whatever the project requires)
7. If checks pass: commit with message `feat: [Story ID] - [Story Title]`
8. Update `prd.json`: set `passes: true` for the completed story
9. Update `CLAUDE.md`/`AGENTS.md` if you discover reusable patterns
10. Append progress to `progress.txt`

## Progress Format

APPEND to `progress.txt` (never overwrite):

```
[ISO-8601 DateTime] - [Story ID]
Implemented: [brief description]
Files changed: [list]
Learnings:
[Pattern/gotcha/context discovered]
---
```

## Codebase Patterns Section

If you discover a reusable pattern, add it to the `## Codebase Patterns` section at the **TOP** of `progress.txt` (create it if it doesn't exist). Only general, reusable patterns — not story-specific details.

```
## Codebase Patterns
- Example: Use `sql<number>` template for aggregations
- Example: Always use `IF NOT EXISTS` for migrations
- Example: Export types from actions.ts for UI components
```

## Quality Gates

- ALL commits MUST pass quality checks
- Do NOT commit broken code
- Keep changes focused and minimal
- Follow existing code patterns and conventions

## Browser Testing (If Available)

For any story that changes UI, verify it works in the browser if browser testing tools are configured (e.g., via MCP):

1. Navigate to the relevant page
2. Verify the UI changes work as expected
3. Note findings in your progress report

If no browser tools are available, note that manual browser verification is needed.

## Stop Condition

After completing a story, check if ALL stories have `passes: true`.

- If **ALL** complete: reply with `<promise>COMPLETE</promise>`
- If stories remain: end normally (the next iteration handles them)

## Rules

- ONE story per iteration
- Commit frequently
- Keep CI green
- Read Codebase Patterns before starting
- Never modify `prd.json` except to set `passes: true` and add `notes`
