# claude-code-status-line

A semantic, color-coded status line for [Claude Code](https://docs.claude.com/en/docs/claude-code).

It turns the status line into a glanceable dashboard: git working-tree state, the
context-window token budget, rate-limit traffic lights, and a clear warning
whenever you are running with a non-default model or reasoning-effort setting.

## Example

```
my-app  feature/login  ∆: 2+1  δ +47/-12  Sonnet 4.6  <low>  420k  5h:88% 7d:97%
```

Left to right: directory `my-app`; on branch `feature/login` (not main); 2 modified
and 1 new uncommitted file; +47/-12 uncommitted lines; running on `Sonnet 4.6` with
`low` effort (both flagged); 420k tokens of context used; rate limits at 88% (5h)
and 97% (7d).

## Design: one color, one meaning

The palette is organized into three layers so that no single color is overloaded.

| Color | Meaning | Appears on |
| --- | --- | --- |
| orange | approaching a limit (warn) | context tokens, rate limits |
| red | at the limit (critical) | context tokens, rate limits |
| yellow | modified tracked files | `∆` C |
| green | addition: new files, added lines | `∆` N, `δ` +A |
| bold magenta | run configured off the safe default | model below Opus, non-default effort |
| cyan | not on the main branch | branch |
| default | safe / informational | everything else |

"Traffic light" (orange/red) signals a quantitative approach to a hard ceiling.
"Attention" (bold magenta) is a categorical flag that the run is configured off its
safe default. Everything else is plain information. Keeping these layers on separate
colors is the whole point: a color you see always means the same thing.

## Segments

| Segment | Shows | Coloring |
| --- | --- | --- |
| `dir` | current directory name | default |
| `branch` | current git branch | cyan when not `main` |
| `∆: C+N` | uncommitted files: C changed (tracked), N new (untracked) | C yellow, N green; shown whenever inside a repo |
| `δ +A/-D` | uncommitted line diff vs `HEAD` | +A green, -D default |
| `model` | active model | bold magenta when below Opus |
| `<eff>` | reasoning-effort level | bold magenta when not `high`/`xhigh` |
| `NNNk` | context tokens used | orange above 300k, red above 500k |
| `5h` / `7d` | rate-limit usage | orange above 80%, red above 95% |

The `∆` and `δ` counters are shown whenever the current directory is a git
repository, including `∆: 0+0` / `δ +0/-0` on a clean tree, so the layout stays
stable and you always know where to look.

## Requirements

`bash`, `jq`, `git`, and `awk`. Works on macOS and Linux.

## Installation

Clone the repository:

```sh
git clone https://github.com/al-siv/claude-code-status-line.git
```

Point Claude Code at the script in `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash /absolute/path/to/claude-code-status-line/statusline.sh"
  }
}
```

Alternatively, run `./install.sh` to copy the script into `~/.claude/` and print the
exact snippet to add. The status line updates on the next render; no restart needed.

## Configuration

Every threshold is an environment variable with a sensible default. Override it
inline in the command, for example:

```json
"command": "STATUSLINE_CTX_WARN_K=250 bash /path/to/statusline.sh"
```

| Variable | Default | Meaning |
| --- | --- | --- |
| `STATUSLINE_CTX_WARN_K` | `300` | context tokens (thousands) that turn the counter orange |
| `STATUSLINE_CTX_CRIT_K` | `500` | context tokens (thousands) that turn it red |
| `STATUSLINE_RL_WARN` | `80` | rate-limit percentage that turns a bucket orange |
| `STATUSLINE_RL_CRIT` | `95` | rate-limit percentage that turns it red |
| `STATUSLINE_SAFE_EFFORT` | `high xhigh` | space-separated effort levels that are not flagged |
| `STATUSLINE_WEAK_MODEL_RE` | `sonnet\|haiku` | case-insensitive regex of model names flagged as below Opus |
| `STATUSLINE_MAIN_BRANCH` | `main` | branch treated as home (no highlight) |
| `NO_COLOR` | unset | set to any value to disable all coloring (see <https://no-color.org/>) |

## How the token count works

Claude Code's status-line JSON exposes `context_window.used_percentage` and
`context_window.context_window_size`, but no absolute token count. This script
computes:

```
tokens = used_percentage / 100 * context_window_size
```

The printed `kN` figure is therefore always accurate. The orange/red thresholds,
however, only trigger if your context window is large enough to reach them — the
default 300k/500k thresholds assume a 1M-token window. Adjust
`STATUSLINE_CTX_WARN_K` / `STATUSLINE_CTX_CRIT_K` to match your window.

## License

MIT — see [LICENSE](LICENSE).
