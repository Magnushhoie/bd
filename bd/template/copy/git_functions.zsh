# Git + fzf helpers. Source from ~/.zshrc or ~/.bashrc.
_git_log_format='%C(auto)%h %C(blue)%cr%C(auto)%d %s'
_git_pager='bat --language=diff --style=plain --paging=always'

# Helpers

function _git_diff_rows {
  awk -F'\t' '
    /^:/ { paths[++n] = $2; status[$2] = substr($1, length($1)); next }
    NF { counts[$3] = sprintf("\033[32m+%-4s\033[31m-%-4s\033[0m", $1, $2) }
    END {
      for (i = 1; i <= n; i++) {
        path = paths[i]; s = status[path]; color = s == "A" ? 32 : s == "D" ? 31 : 33
        row = sprintf("%s\t\033[%sm%s\033[0m %s %s\n", path, color, s, path in counts ? counts[path] : sprintf("%10s", ""), path)
        if (s == "A") added = added row; else changed = changed row
      }
      printf "%s%s", changed, added
    }'
}

# Runs a command with a throwaway index where untracked files count as added, so git diff shows them.
function _git_including_untracked {
  (
    local real_index
    real_index=$(git rev-parse --git-path index) || exit
    export GIT_INDEX_FILE
    GIT_INDEX_FILE=$(mktemp) || exit
    trap 'rm -f "$GIT_INDEX_FILE"' EXIT
    # Makes Ctrl-C run the EXIT trap in zsh too.
    trap 'exit 130' INT TERM HUP
    if [ -f "$real_index" ]; then
      cp "$real_index" "$GIT_INDEX_FILE" || exit
    else
      rm "$GIT_INDEX_FILE"
    fi
    git add --ignore-removal --intent-to-add :/ || exit
    "$@"
  )
}

# Usage: _git_changes_menu open|pick <prompt> <header> [git diff args...]
function _git_changes_menu {
  local mode=$1 prompt=$2 header=$3 outside
  local -a enter_key preview
  shift 3
  case $mode in
    open)
      enter_key=(--bind="enter:execute:git diff --stat --patch $* -- {1} | $_git_pager")
      preview=(--preview="git diff --color=always --stat --patch $* -- {1}")
      ;;
    pick) enter_key=(--multi) ;;
    *) echo "_git_changes_menu: unknown mode: $mode" >&2; return 2 ;;
  esac
  outside=$(git diff --name-only --no-renames "$@" -- ':/' ':!.' | wc -l)
  (( outside > 0 )) && header+=$'\n'"⚠ $outside more changed file(s) outside this folder"
  git -c core.quotePath=false diff --raw --numstat --no-renames --relative "$@" |
    _git_diff_rows |
    fzf --ansi --no-sort --layout=reverse --delimiter='\t' --with-nth=2 \
      --prompt="$prompt" --header="$header" \
      "${preview[@]}" \
      "${enter_key[@]}" |
    cut -f1
}

function _git_pick_commit {
  local prompt=$1
  shift
  git log --color=always --format="$_git_log_format" |
    fzf --ansi --no-sort --layout=reverse --prompt="$prompt" \
      --preview="git show --color=always --stat --patch --format='$_git_log_format' {1}" "$@" |
    cut -d' ' -f1
}

function _git_pick_file {
  awk 'NR == FNR { keep[$0]; next } $0 in keep && !seen[$0]++' \
    <(git -c core.quotePath=false ls-files) <(git -c core.quotePath=false log --relative --name-only --format=) |
    fzf --scheme=path --tiebreak=index --prompt='Log file> ' \
      --preview="git log --color=always -10 --format='$_git_log_format' -- {}"
}

function _git_pick_branch {
  local prompt=$1 skip=$2
  shift 2
  git for-each-ref --sort=-committerdate \
    --format='%(HEAD) %(committerdate:relative)%09%(refname:short)' refs/heads |
    awk -F'\t' -v skip="$skip" 'BEGIN { split(skip, names, " "); for (i in names) hidden[names[i]] } !($2 in hidden)' |
    fzf --layout=reverse --delimiter='\t' --prompt="$prompt" \
      --preview="git log --graph --color=always -20 --format='$_git_log_format' {2}" "$@" |
    cut -f2
}

# Working tree

function gs {
  local outside
  git status -- . || return
  outside=$(git status --porcelain -- ':/' ':!.' | wc -l)
  if (( outside > 0 )); then
    printf '\n\033[1;33m⚠  %d files not shown (outside this directory)\033[0m\n' "$outside"
  fi
}

function gstat {
  _git_including_untracked _git_changes_menu open 'Status> ' 'ENTER open · ESC quit'
}

function gadd {
  local files
  files=$(_git_including_untracked _git_changes_menu pick 'Add files> ' 'TAB mark · ENTER add') || return
  [ -z "$files" ] && return 0
  git add --pathspec-from-file=- <<< "$files"
  gs
}

function gdiff {
  local target commit
  git rev-parse --git-dir >/dev/null || return
  while target=${1:-$(_git_pick_commit 'Diff against> ')}; [ -n "$target" ]; do
    commit=$(git rev-parse --verify --quiet "$target^{commit}") || { echo "gdiff: not a commit: $target" >&2; return 1; }
    _git_including_untracked _git_changes_menu open "Diff $target> " 'ENTER open · ESC back' "$commit"
    (( $# == 0 )) || return 0
  done
}

# History

function glog {
  local file pathspec
  git rev-parse --git-dir >/dev/null || return
  while file=${1:-$(_git_pick_file)}; [ -n "$file" ]; do
    pathspec=$(printf '%q ' "${@:-$file}")
    git log --color=always --format="$_git_log_format" -- "${@:-$file}" |
      fzf --ansi --no-sort --layout=reverse --prompt='Log> ' \
        --header='ENTER open diff · ESC/CTRL-C back to files' \
        --preview="git show --color=always --stat --patch --format='$_git_log_format' {1} -- $pathspec" \
        --bind="enter:execute:git show --stat --patch --format='$_git_log_format' {1} -- $pathspec | $_git_pager"
    (( $# == 0 )) || return 0
  done
}

# Branches

function gbsel {
  local branch
  git rev-parse --git-dir >/dev/null || return
  branch=$(_git_pick_branch 'Switch branch> ' '')
  [ -z "$branch" ] && return 0
  git switch "$branch"
}

function gbmerge {
  local repo_root current target result tree conflicts header
  git rev-parse --git-dir >/dev/null || return
  repo_root=$(git rev-parse --show-toplevel) || return
  current=$(git rev-parse --abbrev-ref HEAD) || return
  while target=${1:-$(_git_pick_branch "Merge into $current> " "$current")}; [ -n "$target" ]; do
    result=$(git -C "$repo_root" merge-tree --write-tree --name-only --no-messages HEAD "$target")
    [ -n "$result" ] || return 1
    tree=${result%%$'\n'*}
    conflicts=${result#"$tree"}
    [ -n "$conflicts" ] && header="CONFLICTS:${conflicts//$'\n'/ }" || header=clean
    (cd "$repo_root" && _git_changes_menu open "Merge $target into $current> " "$header" HEAD "$tree")
    (( $# == 0 )) || return 0
  done
}

function gbdel {
  local base branches reply
  git rev-parse --git-dir >/dev/null || return
  git symbolic-ref --quiet refs/remotes/origin/HEAD >/dev/null ||
    git remote set-head origin --auto || return
  base=$(git symbolic-ref --short refs/remotes/origin/HEAD) || return
  branches=$(
    _git_pick_branch 'Delete branches> ' "$(git branch --show-current) ${base#origin/}" --tac --multi \
      --header="TAB mark · preview: not in $base" \
      --preview="git log --color=always --format='$_git_log_format' $(printf %q "$base")..{2}"
  )
  [ -z "$branches" ] && return 0
  sed 's/^/  /' <<< "$branches"
  printf 'Force-delete these branches? [y/N] '
  read -r reply
  [[ $reply == [yY]* ]] && xargs git branch -D <<< "$branches"
}

function gpush {
  if git rev-parse --abbrev-ref @{u} >/dev/null 2>&1; then
    git push "$@"
  else
    git push -u origin HEAD "$@"
  fi
}