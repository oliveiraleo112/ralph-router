#!/usr/bin/env bash
# Ralph — Autonomous AI Agent Loop
# https://github.com/snarktank/ralph
#
# Usage: ./ralph.sh [OPTIONS] [max_iterations]
#
# Options:
#   --tool <name>       AI tool: auto|copilot|codex|qwen|cline|gemini|claude (default: auto)
#   --retries <n>       Retries per tool before fallback in auto mode (default: 2)
#   --parallel <n>      Run N parallel agents via git worktrees (default: 1)
#   --max-turns <n>     Max agentic turns per iteration (default: unlimited)
#   --budget <usd>      Max USD to spend per iteration (default: unlimited)
#   --branch <name>     Override branch name from prd.json
#   --dry-run           Show what would be done without executing
#   --verbose           Enable verbose logging
#   -h, --help          Show this help

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Defaults ---
TOOL="auto"
MAX_ITERATIONS=10
PARALLEL=1
MAX_TURNS=""
BUDGET=""
BRANCH_OVERRIDE=""
DRY_RUN=false
VERBOSE=false
MAX_RETRIES_PER_TOOL=2

# Smart Router: priority fallback chain (first = preferred, last = emergency)
TOOL_CHAIN=("copilot" "codex" "qwen" "cline" "gemini" "claude")
declare -A TOOL_TIER=(
    [copilot]="💰 Paid (GPT-5 mini)"
    [codex]="🆓 Free tier"
    [qwen]="🆓 Free tier"
    [cline]="🆓 Free tier"
    [gemini]="💰 Paid (large model)"
    [claude]="💎 Premium (emergency only)"
)

PRD_FILE="${SCRIPT_DIR}/prd.json"
PROGRESS_FILE="${SCRIPT_DIR}/progress.txt"
LOG_FILE="/dev/null"
WORKER_PIDS=()

# --- Colors ---
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

log()     { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
log_ok()  { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $*${NC}" | tee -a "$LOG_FILE"; }
log_warn(){ echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $*${NC}" | tee -a "$LOG_FILE"; }
log_err() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*${NC}" | tee -a "$LOG_FILE"; }
log_info(){ echo -e "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')] $*${NC}" | tee -a "$LOG_FILE"; }
vlog()    { [[ "$VERBOSE" == "true" ]] && log "$*" || true; }

usage() {
    cat <<'EOF'
Ralph — Autonomous AI Agent Loop

Usage: ./ralph.sh [OPTIONS] [max_iterations]

Options:
  --tool <name>       AI tool: auto|copilot|codex|qwen|cline|gemini|claude (default: auto)
  --retries <n>       Retries per tool before fallback in auto mode (default: 2)
  --parallel <n>      Run N parallel agents via git worktrees (default: 1)
  --max-turns <n>     Max agentic turns per iteration (default: unlimited)
  --budget <usd>      Max USD per iteration (default: unlimited)
  --branch <name>     Override branch name from prd.json
  --dry-run           Show what would be done without executing
  --verbose           Enable verbose logging
  -h, --help          Show this help

Smart Router (--tool auto):
  Tries tools in priority order: copilot → codex → qwen → cline → gemini → claude
  Skips tools not installed. Retries each tool N times before falling back.
  Claude is always last resort (emergency only).

Examples:
  ./ralph.sh                              # Auto mode, 10 iterations
  ./ralph.sh 20                           # Auto mode, 20 iterations
  ./ralph.sh --tool claude 15             # Claude only, 15 iterations
  ./ralph.sh --tool codex --parallel 3    # Codex, 3 parallel workers
  ./ralph.sh --retries 3 --verbose        # 3 retries per tool, verbose output
  ./ralph.sh --dry-run                    # Preview without running

Requirements:
  - prd.json in the same directory
  - At least one AI tool installed (copilot/codex/qwen/cline/gemini/claude)
  - jq and git

See README.md for full documentation.
EOF
}

# --- Argument parsing ---
ARGS_PROVIDED=false
[[ $# -gt 0 ]] && ARGS_PROVIDED=true

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tool)        TOOL="$2"; shift 2 ;;
        --retries)     MAX_RETRIES_PER_TOOL="$2"; shift 2 ;;
        --parallel)    PARALLEL="$2"; shift 2 ;;
        --max-turns)   MAX_TURNS="$2"; shift 2 ;;
        --budget)      BUDGET="$2"; shift 2 ;;
        --branch)      BRANCH_OVERRIDE="$2"; shift 2 ;;
        --dry-run)     DRY_RUN=true; shift ;;
        --verbose)     VERBOSE=true; shift ;;
        -h|--help)     usage; exit 0 ;;
        [0-9]*)        MAX_ITERATIONS="$1"; shift ;;
        *)             log_err "Unknown option: $1"; usage; exit 1 ;;
    esac
done

ALLOWED_TOOLS="auto copilot codex qwen cline gemini claude"
if [[ ! " $ALLOWED_TOOLS " =~ " $TOOL " ]]; then
    log_err "Invalid tool: $TOOL. Allowed: $ALLOWED_TOOLS"
    exit 1
fi


# --- Prerequisite checks ---
check_prereqs() {
    local missing=false

    for cmd in jq git; do
        if ! command -v "$cmd" &>/dev/null; then
            log_err "Required command not found: $cmd"
            missing=true
        fi
    done

    if [[ "$TOOL" == "auto" ]]; then
        local any_found=false
        for t in "${TOOL_CHAIN[@]}"; do
            command -v "$t" &>/dev/null && any_found=true && break || true
        done
        if [[ "$any_found" == "false" ]]; then
            log_err "No AI tool found. Install one of: ${TOOL_CHAIN[*]}"
            missing=true
        fi
    else
        if ! command -v "$TOOL" &>/dev/null; then
            log_err "AI tool not found: $TOOL (install it or use --tool auto)"
            missing=true
        fi
    fi

    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_err "Not a git repository. Ralph requires git."
        missing=true
    fi

    if [[ ! -f "$PRD_FILE" ]]; then
        log_err "prd.json not found at: $PRD_FILE"
        log_err "Create one from prd.json.example or use the /prd skill."
        missing=true
    fi

    [[ "$missing" == "true" ]] && return 1 || return 0
}


# --- Select prompt file based on tool name ---
get_prompt_file() {
    local tool_name="${1:-$TOOL}"
    case "$tool_name" in
        claude) echo "${SCRIPT_DIR}/CLAUDE.md" ;;
        *)      echo "${SCRIPT_DIR}/prompt.md" ;;
    esac
}


# --- Run AI tool (tool_name as 3rd arg) ---
run_tool() {
    local prompt_file="$1" logfile="$2" tool_name="${3:-$TOOL}"
    local _rc=0

    # Auto-switch prompt if claude was selected but prompt.md was passed
    if [[ "$tool_name" == "claude" && "$prompt_file" == *"/prompt.md" ]]; then
        local claude_prompt="${prompt_file/prompt.md/CLAUDE.md}"
        [[ -f "$claude_prompt" ]] && prompt_file="$claude_prompt" || true
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would run: $tool_name < $prompt_file"
        return 0
    fi

    case "$tool_name" in
        copilot)
            copilot -p "$(cat "$prompt_file")" --model gpt-5-mini --allow-all-tools 2>&1 | tee -a "$logfile"
            _rc=${PIPESTATUS[0]}
            ;;
        codex)
            codex exec --full-auto "$(cat "$prompt_file")" 2>&1 | tee -a "$logfile"
            _rc=${PIPESTATUS[0]}
            ;;
        qwen)
            qwen -p "$(cat "$prompt_file")" --yolo 2>&1 | tee -a "$logfile"
            _rc=${PIPESTATUS[0]}
            ;;
        cline)
            cline -y "$(cat "$prompt_file")" 2>&1 | tee -a "$logfile"
            _rc=${PIPESTATUS[0]}
            ;;
        gemini)
            gemini -p "$(cat "$prompt_file")" --yolo 2>&1 | tee -a "$logfile"
            _rc=${PIPESTATUS[0]}
            ;;
        claude)
            local cmd_args=(claude --dangerously-skip-permissions)
            [[ -n "$MAX_TURNS" ]] && cmd_args+=(--max-turns "$MAX_TURNS") || true
            "${cmd_args[@]}" -p "$(cat "$prompt_file")" 2>&1 | tee -a "$logfile"
            _rc=${PIPESTATUS[0]}
            ;;
        *)
            log_err "Unknown tool: $tool_name"
            return 1
            ;;
    esac
    return $_rc
}


# --- Smart Router: try each tool in priority order with per-tool retries ---
smart_route() {
    local base_logfile="$1"

    for tool_name in "${TOOL_CHAIN[@]}"; do
        if ! command -v "$tool_name" &>/dev/null; then
            vlog "Skipping $tool_name (not installed)"
            continue
        fi

        local tier="${TOOL_TIER[$tool_name]:-unknown}"
        log_info "Trying: $tool_name ($tier)"

        local pf
        pf=$(get_prompt_file "$tool_name")
        [[ ! -f "$pf" ]] && pf="${SCRIPT_DIR}/prompt.md"

        local attempt=1
        while [[ $attempt -le $MAX_RETRIES_PER_TOOL ]]; do
            local tool_log="${base_logfile%.log}-${tool_name}-attempt${attempt}.log"

            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY-RUN] Would run: $tool_name (attempt $attempt/$MAX_RETRIES_PER_TOOL)"
                return 0
            fi

            run_tool "$pf" "$tool_log" "$tool_name"
            local rc=$?

            # Detect false-positive success (tool exits 0 but actually failed)
            if grep -qi "argument missing\|error:\|FATAL\|panic\|command not found" "$tool_log" 2>/dev/null; then
                log_warn "$tool_name returned rc=0 but output contains errors (attempt $attempt)"
                rc=1
            fi

            if [[ $rc -eq 0 ]] && [[ -s "$tool_log" ]]; then
                log_ok "Success with $tool_name (attempt $attempt)"
                cat "$tool_log" >> "$base_logfile" 2>/dev/null || true
                echo "$tool_name" > "${SCRIPT_DIR}/.last-tool-used"
                return 0
            fi

            if grep -qi "rate.limit\|too many requests\|429\|quota.*exceeded" "$tool_log" 2>/dev/null; then
                local wait=$(( attempt * 20 ))
                log_warn "$tool_name rate limited (attempt $attempt). Waiting ${wait}s..."
                sleep "$wait"
            else
                log_warn "$tool_name failed (attempt $attempt/$MAX_RETRIES_PER_TOOL, rc=$rc)"
                sleep 3
            fi

            attempt=$(( attempt + 1 ))
        done

        log_warn "$tool_name exhausted ($MAX_RETRIES_PER_TOOL attempts). Trying next in chain..."
    done

    log_err "ALL tools in chain failed."
    return 1
}


# --- Dispatcher: smart route or direct tool ---
run_tool_with_routing() {
    local prompt_file="$1" logfile="$2"

    if [[ "$TOOL" == "auto" ]]; then
        smart_route "$logfile"
        return $?
    fi

    # Direct tool mode with retry on rate limit
    local attempt=1
    while [[ $attempt -le $MAX_RETRIES_PER_TOOL ]]; do
        run_tool "$prompt_file" "$logfile" "$TOOL"
        local rc=$?

        [[ $rc -eq 0 ]] && return 0

        if grep -qi "rate.limit\|too many requests\|429\|quota.*exceeded" "$logfile" 2>/dev/null; then
            local wait=$(( attempt * 30 ))
            log_warn "Rate limit (attempt $attempt/$MAX_RETRIES_PER_TOOL). Waiting ${wait}s..."
            sleep "$wait"
        else
            log_warn "$TOOL failed (attempt $attempt/$MAX_RETRIES_PER_TOOL, rc=$rc)"
            [[ $attempt -lt $MAX_RETRIES_PER_TOOL ]] && sleep 3 || true
        fi
        attempt=$(( attempt + 1 ))
    done
    return 1
}


# --- Archive previous run if branch changed ---
maybe_archive() {
    local current_branch="$1"
    local branch_file="${SCRIPT_DIR}/.last-branch"
    local last_branch=""

    [[ -f "$branch_file" ]] && last_branch=$(cat "$branch_file")

    if [[ -n "$last_branch" && "$current_branch" != "$last_branch" ]]; then
        log_info "Branch changed: $last_branch → $current_branch. Archiving previous run..."
        if [[ -x "${SCRIPT_DIR}/scripts/archive.sh" ]]; then
            bash "${SCRIPT_DIR}/scripts/archive.sh" "$last_branch" || true
        fi
    fi
    echo "$current_branch" > "$branch_file"
}


# --- Ensure on correct branch ---
ensure_branch() {
    local target_branch="$1"
    local current_branch
    current_branch=$(git branch --show-current)

    if [[ "$current_branch" == "$target_branch" ]]; then
        vlog "Already on branch: $target_branch"
        return 0
    fi

    if git show-ref --verify --quiet "refs/heads/$target_branch"; then
        log_info "Switching to existing branch: $target_branch"
        git checkout "$target_branch"
    else
        log_info "Creating new branch: $target_branch"
        git checkout -b "$target_branch"
    fi
}


# --- Cleanup worktrees ---
cleanup_worktrees() {
    local worker_dir="${SCRIPT_DIR}/.ralph-workers"
    if [[ -d "$worker_dir" ]]; then
        for wt in "$worker_dir"/worker-*; do
            [[ -d "$wt" ]] && git worktree remove --force "$wt" 2>/dev/null || true
        done
        rmdir "$worker_dir" 2>/dev/null || true
    fi
}

trap 'echo ""; log_warn "Interrupted (Ctrl+C)"; if [[ ${#WORKER_PIDS[@]} -gt 0 ]]; then log_info "Killing ${#WORKER_PIDS[@]} worker(s)..."; for wp in "${WORKER_PIDS[@]}"; do kill "$wp" 2>/dev/null || true; done; for wp in "${WORKER_PIDS[@]}"; do wait "$wp" 2>/dev/null || true; done; fi; cleanup_worktrees; exit 130' INT TERM
# trap cleanup_worktrees EXIT  # Disabled: run_parallel handles its own cleanup


# --- Parallel execution via git worktrees ---
run_parallel() {
    local n="$1" prompt_file="$2" prd_branch="$3"
    local worker_dir="${SCRIPT_DIR}/.ralph-workers"
    local main_branch
    main_branch=$(git branch --show-current)
    mkdir -p "$worker_dir"

    log_info "Starting $n parallel workers..."
    local pids=()
    WORKER_PIDS=()
    local worker_branches=()

    for (( i=1; i<=n; i++ )); do
        local wt_path="$worker_dir/worker-$i"
        local wt_branch="ralph-worker-${i}-$(date +%s)"
        worker_branches+=("$wt_branch")

        # Create a real branch for each worker (not detached HEAD)
        git branch -f "$wt_branch" HEAD 2>/dev/null || true
        git worktree add "$wt_path" "$wt_branch" 2>/dev/null || {
            log_warn "Failed to create worktree for worker $i"
            continue
        }

        # Copy prd.json and progress.txt into the worktree so tools can read/update them
        cp -f "$PRD_FILE" "$wt_path/prd.json" 2>/dev/null || true
        cp -f "$PROGRESS_FILE" "$wt_path/progress.txt" 2>/dev/null || true

        # Define worker log OUTSIDE the subshell so it survives worktree cleanup and is available to safety checks
        local wt_log="${SCRIPT_DIR}/ralph-worker${i}-$(date +%Y%m%d-%H%M%S).log"

        (
            if [[ ! -d "$wt_path" ]]; then echo "ERROR: worktree missing" >> "$wt_log"; exit 1; fi
            cd "$wt_path" || exit 1
            run_tool_with_routing "$prompt_file" "$wt_log" || true
            # Stage and commit any changes the tool made
            git add -A 2>/dev/null || true
            if ! git diff --cached --quiet 2>/dev/null; then
                git commit -m "feat: worker-$i changes (auto-parallel)"                     --author="Ralph <ralph@bot>" 2>/dev/null || true
            fi
        ) &
        pids+=($!); WORKER_PIDS+=($!)
        log_info "Worker $i started (pid ${pids[-1]})"
    done

    # Wait for ALL workers to finish BEFORE touching worktrees
    local failed=0
    for pid in "${WORKER_PIDS[@]}"; do
        wait "$pid" || failed=$(( failed + 1 ))
    done

    # Now merge results back into the main branch (workers are done, safe to proceed)
    log_info "Merging worker results..."
    for (( i=0; i<${#worker_branches[@]}; i++ )); do
        local wb="${worker_branches[$i]}"
        local wt_path="$worker_dir/worker-$((i+1))"

        # Check if worker branch has new commits vs main
        if git log "${main_branch}..${wb}" --oneline 2>/dev/null | grep -q .; then
            log_info "Merging worker $((i+1)) branch: $wb"
            git merge "$wb" --no-edit -m "merge: worker-$((i+1)) results" 2>/dev/null || {
                # On conflict, accept theirs for prd.json and progress.txt
                log_warn "Merge conflict from worker $((i+1)), resolving..."
                git checkout --theirs prd.json progress.txt 2>/dev/null || true
                git add -A 2>/dev/null || true
                git commit --no-edit -m "merge: worker-$((i+1)) results (resolved)" 2>/dev/null || true
            }
        else
            vlog "Worker $((i+1)) made no new commits"
        fi
    done

    # Consolidate prd.json: pick the version with the most passes
    # (In case multiple workers updated different stories)
    local best_prd="" best_passes=0
    for (( i=1; i<=n; i++ )); do
        local wt_path="$worker_dir/worker-$i"
        if [[ -f "$wt_path/prd.json" ]]; then
            local p
            p=$(jq '[.userStories[] | select(.passes == true)] | length' "$wt_path/prd.json" 2>/dev/null) || p=0
            if [[ $p -gt $best_passes ]]; then
                best_passes=$p
                best_prd="$wt_path/prd.json"
            fi
        fi
    done
    # Also check main branch version
    local main_passes
    main_passes=$(jq '[.userStories[] | select(.passes == true)] | length' "$PRD_FILE" 2>/dev/null) || main_passes=0

    if [[ -n "$best_prd" && $best_passes -gt $main_passes ]]; then
        log_info "Updating prd.json: $main_passes → $best_passes passes (from worker)"
        # Smart merge: set passes=true for any story that ANY worker completed
        python3 - "$PRD_FILE" "$worker_dir" "$n" << 'PYMERGE'
import json, sys, os

main_prd = sys.argv[1]
worker_dir = sys.argv[2]
num_workers = int(sys.argv[3])

with open(main_prd) as f:
    prd = json.load(f)

# Collect all passes from all workers
for i in range(1, num_workers + 1):
    worker_prd = os.path.join(worker_dir, f"worker-{i}", "prd.json")
    if os.path.exists(worker_prd):
        try:
            with open(worker_prd) as f:
                wprd = json.load(f)
            for ws in wprd.get("userStories", []):
                if ws.get("passes"):
                    for ms in prd.get("userStories", []):
                        if ms["id"] == ws["id"]:
                            ms["passes"] = True
                            if ws.get("notes"):
                                ms["notes"] = ws["notes"]
        except Exception:
            pass

with open(main_prd, "w") as f:
    json.dump(prd, f, indent=2)

passed = sum(1 for s in prd["userStories"] if s.get("passes"))
print(f"PRD merged: {passed}/{len(prd['userStories'])} stories passed")
PYMERGE
        # Commit the merged prd.json
        git add -f "$PRD_FILE" 2>/dev/null || true
        if ! git diff --cached --quiet 2>/dev/null; then
            git commit -m "chore: merge prd.json from parallel workers ($best_passes passes)" 2>/dev/null || true
        fi
    fi

    # Consolidate progress.txt: append unique lines from workers
    for (( i=1; i<=n; i++ )); do
        local wt_progress="$worker_dir/worker-$i/progress.txt"
        if [[ -f "$wt_progress" ]]; then
            # Append lines that don't exist in main progress
            while IFS= read -r line; do
                if ! grep -qF "$line" "$PROGRESS_FILE" 2>/dev/null; then
                    echo "$line" >> "$PROGRESS_FILE"
                fi
            done < "$wt_progress"
        fi
    done

    # NOW remove worktrees (all workers done, all merges done)
    for (( i=1; i<=n; i++ )); do
        local wt_path="$worker_dir/worker-$i"
        local wb="${worker_branches[$i-1]}"
        if [[ -d "$wt_path" ]]; then
            git worktree remove --force "$wt_path" 2>/dev/null || rm -rf "$wt_path"
        fi
        git branch -D "$wb" 2>/dev/null || true
    done
    git worktree prune 2>/dev/null || true
    rmdir "$worker_dir" 2>/dev/null || true
    WORKER_PIDS=()

    [[ $failed -gt 0 ]] && log_warn "$failed worker(s) failed" || log_ok "All $n workers completed"
}


# ============================================================
# INTERACTIVE MENU FUNCTIONS
# ============================================================

show_header() {
    local project branch completed total pending

    if [[ -f "$PRD_FILE" ]]; then
        project=$(jq -r '.project // "No project"' "$PRD_FILE" 2>/dev/null) || project="No PRD"
        branch=$(jq -r '.branchName // "N/A"' "$PRD_FILE" 2>/dev/null) || branch="N/A"
        total=$(jq '.userStories | length' "$PRD_FILE" 2>/dev/null) || total=0
        completed=$(jq '[.userStories[] | select(.passes == true)] | length' "$PRD_FILE" 2>/dev/null) || completed=0
        pending=$(( total - completed ))
    else
        project="No PRD found"; branch="N/A"; total=0; completed=0; pending=0
    fi

    # Build color-coded chain status
    local chain_display=""
    for t in "${TOOL_CHAIN[@]}"; do
        if command -v "$t" &>/dev/null; then
            chain_display+="${GREEN}${t}${NC} "
        else
            chain_display+="${RED}${t}${NC} "
        fi
    done

    local mode_display
    if [[ "$TOOL" == "auto" ]]; then
        mode_display="${CYAN}AUTO (smart router)${NC}"
    elif command -v "$TOOL" &>/dev/null; then
        mode_display="${GREEN}${TOOL} ✅${NC}"
    else
        mode_display="${RED}${TOOL} ❌${NC}"
    fi

    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}              🤖 ${CYAN}RALPH${NC} — AI Agent Loop                ${CYAN}║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  PRD:      ${project}"
    echo -e "${CYAN}║${NC}  Branch:   ${branch}"
    echo -e "${CYAN}║${NC}  Stories:  ${completed}/${total} complete (${pending} pending)"
    echo -e "${CYAN}║${NC}  Mode:     ${mode_display}"
    echo -e "${CYAN}║${NC}  Chain:    ${chain_display}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  [1] 🚀 Start Ralph Loop"
    echo -e "${CYAN}║${NC}  [2] 🔧 Select AI Tool"
    echo -e "${CYAN}║${NC}  [3] 📋 View PRD Status"
    echo -e "${CYAN}║${NC}  [4] 📝 Create New PRD"
    echo -e "${CYAN}║${NC}  [5] 🔄 Convert PRD to JSON"
    echo -e "${CYAN}║${NC}  [6] 📊 View Progress Log"
    echo -e "${CYAN}║${NC}  [7] 🧹 Clean & Archive Current Run"
    echo -e "${CYAN}║${NC}  [8] ⚙️  Settings"
    echo -e "${CYAN}║${NC}  [9] 🩺 Health Check"
    echo -e "${CYAN}║${NC}  [0] ❌ Exit"
    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
}

menu_start_loop() {
    echo ""
    read -r -p "Max iterations [$MAX_ITERATIONS]: " input
    [[ -n "$input" ]] && MAX_ITERATIONS="$input"
    read -r -p "Parallel workers [$PARALLEL]: " input
    [[ -n "$input" ]] && PARALLEL="$input"
    echo ""
    if [[ "$TOOL" == "auto" ]]; then
        echo -e "${GREEN}Starting Ralph: AUTO mode, $MAX_ITERATIONS iterations, $PARALLEL worker(s)...${NC}"
    else
        echo -e "${GREEN}Starting Ralph: $TOOL, $MAX_ITERATIONS iterations, $PARALLEL worker(s)...${NC}"
    fi
    sleep 1
    run_main_loop
    echo ""
    read -r -p "Press Enter to return to menu..."
}

menu_select_tool() {
    echo ""
    echo "Select AI Tool:"
    echo ""
    local marker=""
    [[ "$TOOL" == "auto" ]] && marker=" ${YELLOW}← current${NC}" || marker=""
    echo -e "  [0] AUTO ${CYAN}(smart router — recommended)${NC}${marker}"

    local idx=1
    for t in "${TOOL_CHAIN[@]}"; do
        local tier="${TOOL_TIER[$t]:-}"
        local status
        if command -v "$t" &>/dev/null; then
            status="${GREEN}✅${NC}"
        else
            status="${RED}❌${NC}"
        fi
        marker=""
        [[ "$t" == "$TOOL" ]] && marker=" ${YELLOW}← current${NC}"
        echo -e "  [$idx] $t $status  ${tier}${marker}"
        idx=$(( idx + 1 ))
    done
    echo ""
    read -r -p "Select [0-6]: " input
    if [[ "$input" == "0" ]]; then
        TOOL="auto"
        echo -e "${GREEN}Tool set to: AUTO (smart router)${NC}"
    elif [[ "$input" =~ ^[1-6]$ ]]; then
        TOOL="${TOOL_CHAIN[$((input-1))]}"
        echo -e "${GREEN}Tool set to: $TOOL${NC}"
    fi
    sleep 1
}

menu_view_prd() {
    echo ""
    if [[ ! -f "$PRD_FILE" ]]; then
        echo -e "${RED}No prd.json found${NC}"
    else
        echo -e "${CYAN}=== PRD Status ===${NC}"
        echo ""
        jq -r '.userStories[] | "\(.id) | \(if .passes then "✅ PASS" else "⏳ PEND" end) | \(.title)"' "$PRD_FILE" 2>/dev/null || echo "Error reading PRD"
        echo ""
        local pend
        pend=$(jq '[.userStories[] | select(.passes == false)] | length' "$PRD_FILE" 2>/dev/null) || pend=0
        if [[ "$pend" -gt 0 ]]; then
            echo -e "${YELLOW}--- Pending Acceptance Criteria ---${NC}"
            jq -r '.userStories[] | select(.passes == false) | "\n\(.id): \(.title)" + "\n" + (.acceptanceCriteria | map("  • " + .) | join("\n"))' "$PRD_FILE" 2>/dev/null || true
        fi
    fi
    echo ""
    read -r -p "Press Enter to continue..."
}

menu_create_prd() {
    echo ""
    if ! command -v claude &>/dev/null; then
        echo -e "${RED}Claude Code not installed. Install: npm install -g @anthropic-ai/claude-code${NC}"
        read -r -p "Press Enter to continue..."; return
    fi
    read -r -p "Describe your feature: " feature_desc
    [[ -z "$feature_desc" ]] && return
    echo -e "${CYAN}Launching Claude with /prd skill...${NC}"
    claude -p "Load the prd skill and create a PRD for: $feature_desc" --allowedTools "Read,Write,Edit" 2>&1 || true
    echo ""
    read -r -p "Press Enter to continue..."
}

menu_convert_prd() {
    echo ""
    local prds=()
    while IFS= read -r -d '' f; do
        prds+=("$f")
    done < <(find "${SCRIPT_DIR}" -name "prd-*.md" -print0 2>/dev/null)

    if [[ ${#prds[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No PRD markdown files found. Create one first with option [4].${NC}"
        read -r -p "Press Enter to continue..."; return
    fi
    echo "Available PRDs:"
    for i in "${!prds[@]}"; do
        echo "  [$((i+1))] ${prds[$i]}"
    done
    read -r -p "Select [1-${#prds[@]}]: " input
    if [[ "$input" =~ ^[0-9]+$ ]] && (( input >= 1 && input <= ${#prds[@]} )); then
        local sel="${prds[$((input-1))]}"
        echo -e "${CYAN}Converting $sel to prd.json...${NC}"
        claude -p "Load the ralph skill and convert $sel to prd.json" --allowedTools "Read,Write,Edit" 2>&1 || true
    fi
    echo ""
    read -r -p "Press Enter to continue..."
}

menu_view_progress() {
    echo ""
    if [[ -f "$PROGRESS_FILE" ]]; then
        echo -e "${CYAN}=== Progress Log ===${NC}"
        cat "$PROGRESS_FILE"
    else
        echo "(No progress file yet)"
    fi
    echo ""
    read -r -p "Press Enter to continue..."
}

menu_archive() {
    echo ""
    if [[ -x "${SCRIPT_DIR}/scripts/archive.sh" ]]; then
        echo -e "${CYAN}Archiving current run...${NC}"
        bash "${SCRIPT_DIR}/scripts/archive.sh" || true
        echo -e "${GREEN}Done.${NC}"
    else
        echo -e "${RED}archive.sh not found or not executable${NC}"
    fi
    echo ""
    read -r -p "Press Enter to continue..."
}

menu_settings() {
    echo ""
    echo -e "${CYAN}=== Current Settings ===${NC}"
    echo "  Tool:               $TOOL"
    echo "  Retries per tool:   $MAX_RETRIES_PER_TOOL"
    echo "  Max iterations:     $MAX_ITERATIONS"
    echo "  Parallel:           $PARALLEL"
    echo "  Max turns:          ${MAX_TURNS:-unlimited}"
    echo "  Budget:             ${BUDGET:-unlimited}"
    echo ""
    read -r -p "Max iterations [$MAX_ITERATIONS]: " input
    [[ -n "$input" ]] && MAX_ITERATIONS="$input"
    read -r -p "Parallel workers [$PARALLEL]: " input
    [[ -n "$input" ]] && PARALLEL="$input"
    read -r -p "Retries per tool [$MAX_RETRIES_PER_TOOL]: " input
    [[ -n "$input" ]] && MAX_RETRIES_PER_TOOL="$input"
    read -r -p "Max turns [${MAX_TURNS:-unlimited}]: " input
    [[ -n "$input" ]] && MAX_TURNS="$input"
    read -r -p "Budget USD [${BUDGET:-unlimited}]: " input
    [[ -n "$input" ]] && BUDGET="$input"
    echo -e "${GREEN}Settings updated.${NC}"
    sleep 1
}

menu_health_check() {
    echo ""
    echo -e "${CYAN}=== Health Check ===${NC}"
    echo ""
    echo "Core Tools:"
    for cmd in jq git; do
        if command -v "$cmd" &>/dev/null; then
            echo -e "  ${GREEN}✅ $cmd${NC} — $(command -v "$cmd")"
        else
            echo -e "  ${RED}❌ $cmd${NC} — NOT FOUND"
        fi
    done
    echo ""
    echo "AI Tools (priority order):"
    local idx=1
    for t in "${TOOL_CHAIN[@]}"; do
        local tier="${TOOL_TIER[$t]:-}"
        local marker=""
        [[ "$t" == "$TOOL" ]] && marker=" ${YELLOW}← active${NC}"
        if command -v "$t" &>/dev/null; then
            local ver
            ver=$("$t" --version 2>/dev/null | head -1) || ver="installed"
            echo -e "  ${GREEN}[$idx] ✅ $t${NC} — ${tier} — ${ver}${marker}"
        else
            echo -e "  ${YELLOW}[$idx] -- $t${NC} — ${tier} — not installed"
        fi
        idx=$(( idx + 1 ))
    done
    if [[ "$TOOL" == "auto" ]]; then
        echo -e "  ${CYAN}Mode: AUTO — will use first available tool in order above${NC}"
    fi
    echo ""
    echo "Git:"
    if git rev-parse --git-dir > /dev/null 2>&1; then
        echo -e "  ${GREEN}✅ Repo${NC}:   $(git rev-parse --show-toplevel 2>/dev/null)"
        echo -e "  ${GREEN}✅ Branch${NC}: $(git branch --show-current 2>/dev/null)"
    else
        echo -e "  ${RED}❌ Not a git repository${NC}"
    fi
    echo ""
    echo "Ralph Files:"
    for f in prd.json prd.json.example progress.txt CLAUDE.md prompt.md AGENTS.md README.md; do
        if [[ -f "${SCRIPT_DIR}/$f" ]]; then
            echo -e "  ${GREEN}✅ $f${NC}"
        else
            echo -e "  ${YELLOW}-- $f${NC}"
        fi
    done
    local old_logs
    old_logs=$(find "$SCRIPT_DIR" -name "ralph-*.log" -mtime +7 2>/dev/null | wc -l)
    if [[ "$old_logs" -gt 0 ]]; then
        echo ""
        echo -e "  ${YELLOW}🧹 $old_logs log(s) older than 7 days — cleaning...${NC}"
        find "$SCRIPT_DIR" -name "ralph-*.log" -mtime +7 -delete 2>/dev/null || true
    fi
    echo ""
    read -r -p "Press Enter to continue..."
}

interactive_menu() {
    while true; do
        show_header
        read -r -p "Choose [0-9]: " choice
        case "$choice" in
            1) menu_start_loop ;;
            2) menu_select_tool ;;
            3) menu_view_prd ;;
            4) menu_create_prd ;;
            5) menu_convert_prd ;;
            6) menu_view_progress ;;
            7) menu_archive ;;
            8) menu_settings ;;
            9) menu_health_check ;;
            0) echo ""; echo "Bye! 👋"; exit 0 ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}


# ============================================================
# RUN MAIN LOOP
# ============================================================
run_main_loop() {
    check_prereqs || return 1

    local TOTAL_STORIES PROJECT_NAME PRD_BRANCH CURRENT_BRANCH PROMPT_FILE
    local COMPLETED PENDING

    TOTAL_STORIES=$(jq '.userStories | length' "$PRD_FILE")
    PROJECT_NAME=$(jq -r '.project // .projectName // "Project"' "$PRD_FILE")
    PRD_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE")

    [[ -n "$BRANCH_OVERRIDE" ]] && PRD_BRANCH="$BRANCH_OVERRIDE" || true

    CURRENT_BRANCH=$(git branch --show-current)

    # Create log file only when actually running the loop
    LOG_FILE="${SCRIPT_DIR}/ralph-$(date +%Y%m%d-%H%M%S).log"
    touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/dev/null"

    log_info "Ralph — $PROJECT_NAME"
    log      "  Mode:       $TOOL"
    log      "  Max iter:   $MAX_ITERATIONS"
    log      "  Parallel:   $PARALLEL"
    log      "  Retries:    $MAX_RETRIES_PER_TOOL per tool"
    [[ -n "$MAX_TURNS" ]] && log "  Max turns:  $MAX_TURNS" || true
    [[ -n "$BUDGET" ]]    && log "  Budget:     \$$BUDGET" || true
    [[ "$DRY_RUN" == "true" ]] && log_warn "DRY-RUN mode — no changes will be made" || true

    maybe_archive "$CURRENT_BRANCH" || true

    if [[ -n "$PRD_BRANCH" && "$CURRENT_BRANCH" != "$PRD_BRANCH" ]]; then
        ensure_branch "$PRD_BRANCH" || {
            log_err "Failed to switch to branch: $PRD_BRANCH"
            return 1
        }
    fi

    # Determine prompt file; smart_route selects per-tool internally
    if [[ "$TOOL" == "auto" ]]; then
        PROMPT_FILE="${SCRIPT_DIR}/prompt.md"  # placeholder; smart_route uses get_prompt_file()
    else
        PROMPT_FILE=$(get_prompt_file "$TOOL")
        if [[ ! -f "$PROMPT_FILE" ]]; then
            log_err "Prompt file not found: $PROMPT_FILE"
            return 1
        fi
    fi
    vlog "Prompt mode: $PROMPT_FILE"

    COMPLETED=$(jq '[.userStories[] | select(.passes == true)] | length' "$PRD_FILE")
    PENDING=$(( TOTAL_STORIES - COMPLETED ))
    log "  Stories:    $COMPLETED/$TOTAL_STORIES complete, $PENDING pending"

    if [[ $PENDING -eq 0 ]]; then
        log_ok "All $TOTAL_STORIES stories already complete. Nothing to do."
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would run $MAX_ITERATIONS iterations (mode: $TOOL) on $PENDING pending stories"
        if [[ "$TOOL" == "auto" ]]; then
            log_info "[DRY-RUN] Tool chain: ${TOOL_CHAIN[*]}"
        else
            log_info "[DRY-RUN] Prompt file: $PROMPT_FILE"
        fi
        log_info "[DRY-RUN] Branch: ${PRD_BRANCH:-$CURRENT_BRANCH}"
        return 0
    fi

    if [[ ! -f "$PROGRESS_FILE" ]]; then
        { echo "# Ralph Progress Log"; echo "Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"; echo "---"; } > "$PROGRESS_FILE"
    fi

    log_ok "Starting Ralph loop..."
    local loop_start i ITER_LOG COMPLETED_AFTER COMPLETED_FINAL PENDING_FINAL
    loop_start=$(date +%s)
    i=0

    for (( i=1; i<=MAX_ITERATIONS; i++ )); do
        log ""
        log "=== Iteration $i/$MAX_ITERATIONS ==="

        COMPLETED=$(jq '[.userStories[] | select(.passes == true)] | length' "$PRD_FILE")
        PENDING=$(( TOTAL_STORIES - COMPLETED ))

        if [[ $PENDING -eq 0 ]]; then
            log_ok "All stories complete after $((i-1)) iterations!"
            break
        fi

        log "  Pending stories: $PENDING"
        ITER_LOG="${SCRIPT_DIR}/ralph-iter${i}-$(date +%H%M%S).log"

        local iter_start iter_elapsed
        iter_start=$(date +%s)

        if [[ $PARALLEL -gt 1 ]]; then
            run_parallel "$PARALLEL" "$PROMPT_FILE" "${PRD_BRANCH:-$CURRENT_BRANCH}"
        else
            run_tool_with_routing "$PROMPT_FILE" "$ITER_LOG" || {
                log_warn "Tool(s) failed on iteration $i"
            }
        fi

        iter_elapsed=$(( $(date +%s) - iter_start ))
        log "  Iteration completed in ${iter_elapsed}s"

        if [[ -f "$ITER_LOG" ]] && grep -q "<promise>COMPLETE</promise>" "$ITER_LOG"; then
            log_ok "Agent signaled COMPLETE"
            break
        fi

        COMPLETED_AFTER=$(jq '[.userStories[] | select(.passes == true)] | length' "$PRD_FILE")
        if [[ $COMPLETED_AFTER -gt $COMPLETED ]]; then
            log_ok "Progress: $COMPLETED_AFTER/$TOTAL_STORIES stories complete (+$((COMPLETED_AFTER - COMPLETED)))"
        else
            log_warn "No new stories completed in iteration $i"
        fi

        [[ $i -lt $MAX_ITERATIONS ]] && sleep 2 || true
    done

    local total_elapsed
    total_elapsed=$(( $(date +%s) - loop_start ))
    COMPLETED_FINAL=$(jq '[.userStories[] | select(.passes == true)] | length' "$PRD_FILE")
    PENDING_FINAL=$(( TOTAL_STORIES - COMPLETED_FINAL ))

    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║       RALPH RUN SUMMARY              ║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  Stories:    ${COMPLETED_FINAL}/${TOTAL_STORIES} complete"
    echo -e "${CYAN}║${NC}  Pending:    ${PENDING_FINAL}"
    echo -e "${CYAN}║${NC}  Iterations: ${i}/${MAX_ITERATIONS}"
    echo -e "${CYAN}║${NC}  Time:       ${total_elapsed}s"
    if [[ $PENDING_FINAL -eq 0 ]]; then
        echo -e "${CYAN}║${NC}  Status:     ${GREEN}✅ SUCCESS${NC}"
    else
        echo -e "${CYAN}║${NC}  Status:     ${YELLOW}⚠️  INCOMPLETE${NC}"
    fi
    echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"

    [[ $PENDING_FINAL -eq 0 ]]
}


# ============================================================
# MAIN — Route to interactive menu or CLI mode
# ============================================================

if [[ "$ARGS_PROVIDED" == "false" ]] && [[ -t 0 ]]; then
    interactive_menu
else
    run_main_loop
    exit $?
fi
