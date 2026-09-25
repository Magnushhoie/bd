_git_blame_rows() {
  setopt local_options pipe_fail
  git blame --line-porcelain -w -C -- "$1" |
    awk -v now="$(date +%s)" '
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
}

gblame() {
  git rev-parse --git-dir >/dev/null || return
  (( $+commands[bat] )) || { echo 'gblame: needs bat (brew install bat)' >&2; return 1; }
  local root file rows
  root=$(git rev-parse --show-toplevel) || return
  while file=${1:-$(_git_pick_file 'Blame file> ' git grep -Il '')}; [ -n "$file" ]; do
    rows=$(_git_blame_rows "$file") || return
    LESS="${LESS:-FRX} -+F" fzf --ansi --no-sort --layout=reverse --delimiter=$'\x1f' --with-nth=6 \
      --prompt="Blame $file> " \
      --header='ENTER file at commit · CTRL-L line history · ESC/CTRL-C back to files' \
      --bind="enter:execute(line={3}; { printf '── %s\n── %s\n' {4} {5}; if [ -n {1} ]; then git -C '$root' show {1}:{2}; else cat '$root'/{2}; fi | bat --color=always --paging=never --style=numbers --highlight-line {3} --file-name {2}; } | less -R -j.3 +\$((line + 2))g)" \
      --bind="ctrl-l:execute(if [ -n {1} ]; then git -C '$root' log -L {3},{3}:{2} --format='$_git_log_format' {1}; else git -C '$root' diff HEAD -- {2}; fi)" <<< "$rows"
    [ -n "$1" ] && return 0
  done
}