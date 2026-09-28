#!/usr/bin/env bash
#
# claude-code-status-line -- a semantic, color-coded status line for Claude Code.
#
# Reads the status-line JSON on stdin and prints a single line to stdout.
# Wire it into Claude Code via ~/.claude/settings.json:
#
#   "statusLine": { "type": "command", "command": "bash /path/to/statusline.sh" }
#
# Segments:
#   dir  <branch>  ∆:C+N  δ:+A/-D  <model>•<eff>  NNNk  5h:X% 7d:Y%
#
# 5h / 7d show the share of each rate-limit window still left (100 - used).
#
# Color layers -- every color carries exactly one meaning:
#
#   TRAFFIC LIGHT (approaching a hard ceiling, a quantitative gradient):
#     - context tokens NNNk : orange > CTX_WARN_K, red > CTX_CRIT_K
#     - rate limits 5h / 7d : orange < RL_WARN_LEFT% left, red < RL_CRIT_LEFT% left
#     orange and red are used nowhere else.
#
#   ATTENTION (the run is configured off the safe default, a categorical flag),
#   shown in bold magenta:
#     - model : flagged when its class is below Opus (matches WEAK_MODEL_RE)
#     - eff   : flagged when the effort level is not listed in SAFE_EFFORT
#
#   INFORMATION (data, not an alarm):
#     - branch  : cyan when not on the main branch
#     - ∆:C+N   : C changed tracked files (yellow), N new/untracked files (green)
#     - δ:+A/-D : +A added lines (green), -D removed lines (neutral)
#   green means "addition" (new files, added lines); yellow means "modified".
#
# Token-count note: the figure is the input-side context size from
# context_window.current_usage (input + cache creation + cache read tokens),
# falling back to used_percentage / 100 * context_window_size. The thresholds are
# absolute token counts, not a share of the window: they mark context sizes past
# which processing cost grows faster, so on windows of 300k or less they never fire.
#
# Honors NO_COLOR (https://no-color.org/): set NO_COLOR to disable all coloring.
#
# Dependencies: bash, jq, git, awk.

input=$(cat)

# ---- Configuration (override via environment) ------------------------------
CTX_WARN_K="${STATUSLINE_CTX_WARN_K:-300}"                # context tokens (k) -> orange
CTX_CRIT_K="${STATUSLINE_CTX_CRIT_K:-500}"                # context tokens (k) -> red
RL_WARN_LEFT="${STATUSLINE_RL_WARN_LEFT:-20}"             # rate-limit % left -> orange
RL_CRIT_LEFT="${STATUSLINE_RL_CRIT_LEFT:-5}"              # rate-limit % left -> red
SAFE_EFFORT="${STATUSLINE_SAFE_EFFORT:-high xhigh}"       # effort levels not flagged
WEAK_MODEL_RE="${STATUSLINE_WEAK_MODEL_RE:-sonnet|haiku}" # models flagged below Opus
MAIN_BRANCH="${STATUSLINE_MAIN_BRANCH:-main}"             # branch treated as "home"

# ---- ANSI palette (256-color) ----------------------------------------------
ORANGE=$'\033[38;5;208m'       # traffic light: warn
RED=$'\033[38;5;196m'          # traffic light: critical
GREEN=$'\033[38;5;40m'         # information: addition (new files, added lines)
YELLOW=$'\033[38;5;220m'       # information: modified tracked files
CYAN=$'\033[38;5;45m'          # information: off main branch
MAGENTA_B=$'\033[1;38;5;201m'  # attention: run config off default
RESET=$'\033[0m'
if [ -n "${NO_COLOR:-}" ]; then ORANGE=""; RED=""; GREEN=""; YELLOW=""; CYAN=""; MAGENTA_B=""; RESET=""; fi

# ---- Fields from the status JSON -------------------------------------------
cwd=$(jq -r '.workspace.current_dir // .cwd // "."' <<<"$input")
dir=$(basename "$cwd" 2>/dev/null)
model=$(jq -r '.model.display_name // empty' <<<"$input" | sed 's/ context)/)/')
eff=$(jq -r '.effort.level // empty' <<<"$input")
# Context tokens: exact input-side count from current_usage (the same formula
# Claude Code uses for used_percentage); null before the first API call.
ctx=$(jq -r '.context_window.current_usage
  | if . == null then empty
    else (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)
    end' <<<"$input")
used=$(jq -r '.context_window.used_percentage // empty' <<<"$input")
size=$(jq -r '.context_window.context_window_size // empty' <<<"$input")
five=$(jq -r '.rate_limits.five_hour.used_percentage // empty' <<<"$input")
week=$(jq -r '.rate_limits.seven_day.used_percentage // empty' <<<"$input")

branch=$(git -C "$cwd" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null)

out="$dir"

# Colors a number only when it is greater than 0; otherwise leaves it neutral.
col_n() {  # $1=number  $2=color
  if [ "$1" -gt 0 ] 2>/dev/null; then printf '%s%s%s' "$2" "$1" "$RESET"
  else printf '%s' "$1"; fi
}

# ---- git: branch + uncommitted counters ------------------------------------
if [ -n "$branch" ]; then
  if [ "$branch" = "$MAIN_BRANCH" ]; then out="$out  $branch"
  else out="$out  ${CYAN}${branch}${RESET}"; fi

  # ∆:C+N  (always shown; C changed = yellow, N new = green)
  porc=$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)
  if [ -n "$porc" ]; then
    n=$(grep -c '^??' <<<"$porc")     # new (untracked)
    c=$(grep -vc '^??' <<<"$porc")    # changed/deleted/staged (tracked)
  else n=0; c=0; fi
  out="$out  ∆:$(col_n "$c" "$YELLOW")+$(col_n "$n" "$GREEN")"

  # δ:+A/-D  (uncommitted diff against HEAD; +A green, -D neutral)
  diffstat=$(git -C "$cwd" --no-optional-locks diff HEAD --numstat 2>/dev/null)
  la=$(awk '$1 ~ /^[0-9]+$/ {a+=$1} END{print a+0}' <<<"$diffstat")
  lr=$(awk '$2 ~ /^[0-9]+$/ {d+=$2} END{print d+0}' <<<"$diffstat")
  if [ "$la" -gt 0 ] 2>/dev/null; then ap="${GREEN}+${la}${RESET}"; else ap="+${la}"; fi
  out="$out  δ:${ap}/-${lr}"
fi

# ---- model (bold magenta when its class is below Opus) ---------------------
if [ -n "$model" ]; then
  if grep -qiE "$WEAK_MODEL_RE" <<<"$model"; then out="$out  ${MAGENTA_B}${model}${RESET}"
  else out="$out  $model"; fi
fi

# ---- effort •eff, glued to the model (bold magenta when not in SAFE_EFFORT) -
# Displayed compactly: low=L medium=M high=H xhigh=XH max=X (unknown as-is)
if [ -n "$eff" ]; then
  case "$eff" in
    low)    ef="L";;
    medium) ef="M";;
    high)   ef="H";;
    xhigh)  ef="XH";;
    max)    ef="X";;
    *)      ef="$eff";;
  esac
  if [ -n "$model" ]; then sep="•"; else sep="  "; fi
  case " $SAFE_EFFORT " in
    *" $eff "*) out="$out$sep$ef";;
    *)          out="$out$sep${MAGENTA_B}${ef}${RESET}";;
  esac
fi

# ---- TRAFFIC LIGHT: context tokens in thousands ----------------------------
# Falls back to used_percentage * context_window_size when current_usage is null.
if [ -z "$ctx" ] && [ -n "$used" ] && [ -n "$size" ]; then
  ctx=$(awk -v u="$used" -v s="$size" 'BEGIN{printf "%.0f", u/100*s}')
fi
if [ -n "$ctx" ]; then
  tk=$(awk -v t="$ctx" 'BEGIN{printf "%.0f", t/1000}')
  col=""
  if   [ "$tk" -gt "$CTX_CRIT_K" ]; then col="$RED"
  elif [ "$tk" -gt "$CTX_WARN_K" ]; then col="$ORANGE"
  fi
  if [ -n "$col" ]; then out="$out  ${col}${tk}k${RESET}"; else out="$out  ${tk}k"; fi
fi

# ---- TRAFFIC LIGHT: rate limits, as the share left -------------------------
rl_seg() {  # $1=label  $2=used percent
  [ -z "$2" ] && return
  local p col=""
  p=$(( 100 - $(printf '%.0f' "$2") ))
  [ "$p" -lt 0 ] && p=0
  if   [ "$p" -lt "$RL_CRIT_LEFT" ]; then col="$RED"
  elif [ "$p" -lt "$RL_WARN_LEFT" ]; then col="$ORANGE"
  fi
  if [ -n "$col" ]; then printf '%s%s:%s%%%s' "$col" "$1" "$p" "$RESET"
  else printf '%s:%s%%' "$1" "$p"; fi
}
rl=""
seg=$(rl_seg 5h "$five"); [ -n "$seg" ] && rl="$seg"
seg=$(rl_seg 7d "$week"); [ -n "$seg" ] && rl="$rl${rl:+ }$seg"
[ -n "$rl" ] && out="$out  $rl"

printf '%s\n' "$out"
