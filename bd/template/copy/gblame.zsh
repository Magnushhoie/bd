# gblame: interactive git blame with fzf + bat.
# Source from ~/.bashrc or ~/.zshrc. Requires: git, fzf (>= 0.51 for --with-shell), bat, less.
# Also expects _git_pick_file and _git_log_format to be defined (bash/zsh-safe).

# Emits one fzf row per blamed line, fields separated by \037:
#   1 sha  2 file  3 original line  4 status title  5 status hint  6 display text
# Body is a subshell so pipefail and any zsh option reset stay scoped to this call.
_git_blame_rows() (
  [ -n "$ZSH_VERSION" ] && emulate -L zsh
  set -o pipefail
  command git blame --line-porcelain -w -C -- "$1" |
    command awk -v now="$(command date +%s)" '
      function age(time,   days) {
        days = int((now - time) / 86400)
        if (days < 60) return days "d"
        if (days < 365) return int(days / 30) "mo"
        return int(days / 365) "y"
      }
      !in_line {
        # Appending "" keeps the hash as text; awk compares hashes like 123e45... as numbers otherwise.
        commit = $1 ""
        sha = (commit ~ /^0+$/) ? "" : commit
        commit_line = $2; final_line = $3; in_line = 1; next
      }
      /^author / { split(substr($0, 8), author, " "); next }
      /^author-time / { time = $2; next }
      /^filename / { line_file = substr($0, 10); next }
      /^\t/ {
        if (sha == "") {
          status_title = line_file " (uncommitted)"
          status_hint = "compare: git diff -- " line_file
        } else {
          status_title = sprintf("%s @ %.7s (%s, %s)", line_file, sha, age(time), author[1])
          status_hint = sprintf("restore: git checkout %.7s -- %s", sha, line_file)
        }
        if (commit == last_commit) commit_info = ""
        else if (sha == "") commit_info = "uncommitted"
        else commit_info = sprintf("%.7s %4s %.8s", sha, age(time), author[1])
        printf "%s\037%s\037%s\037%s\037%s\037\033[90m%-21s %4d\033[0m %s\n",
          sha, line_file, commit_line, status_title, status_hint, commit_info, final_line, substr($0, 2)
        last_commit = commit
        in_line = 0
      }'
)

gblame() {
  [ -n "$ZSH_VERSION" ] && emulate -L zsh
  command git rev-parse --git-dir >/dev/null || return
  command -v bat >/dev/null 2>&1 || { echo 'gblame: needs bat (brew install bat)' >&2; return 1; }
  local root file rows
  root=$(command git rev-parse --show-toplevel) || return
  while file=${1:-$(_git_pick_file 'Blame file> ' git grep -Il '')}; [ -n "$file" ]; do
    rows=$(_git_blame_rows "$file") || return
    # root and the log format reach the bindings through the environment, never spliced
    # into the command text, so quotes or $ in either can't break (or inject into) them.
    # --with-shell pins the bindings to POSIX sh regardless of the user's $SHELL.
    GBLAME_ROOT=$root GBLAME_FMT=$_git_log_format LESS="${LESS:-FRX} -+F" \
    command fzf --ansi --no-sort --layout=reverse --delimiter=$'\x1f' --with-nth=6 \
      --with-shell='sh -c' \
      --prompt="Blame $file> " \
      --header='ENTER file at commit · CTRL-L line history · ESC/CTRL-C back to files' \
      --bind='enter:execute(line={3}; { printf "── %s\n── %s\n" {4} {5}; if [ -n {1} ]; then git -C "$GBLAME_ROOT" show {1}:{2}; else cat "$GBLAME_ROOT"/{2}; fi | bat --color=always --paging=never --style=numbers --highlight-line {3} --file-name {2}; } | less -R -j.3 +$((line + 2))g)' \
      --bind='ctrl-l:execute(if [ -n {1} ]; then git -C "$GBLAME_ROOT" log -L {3},{3}:{2} --format="$GBLAME_FMT" {1}; else git -C "$GBLAME_ROOT" diff HEAD -- {2}; fi)' \
      <<< "$rows"
    [ -n "$1" ] && return 0
  done
}