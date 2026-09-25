_git_log_format='%C(auto)%h %C(blue)%cr%C(auto)%d %s'
_git_pager='bat --language=diff --style=plain --paging=always'

function gs {
  git status -- . || return
  local n=$(git status --porcelain -- ':/' ':!.' | wc -l)
  if (( n > 0 )); then
    printf '\n\033[1;33m⚠  %d files not shown (outside this directory)\033[0m\n' "$n"
  fi
}

_git_pick_branch() {
  local prompt=$1 skip=$2
  shift 2
  git for-each-ref --sort=-committerdate \
    --format='%(HEAD) %(committerdate:relative)%09%(refname:short)' refs/heads |
    awk -F'\t' -v skip="$skip" 'BEGIN { split(skip, names, " "); for (i in names) hidden[names[i]] } !($2 in hidden)' |
    fzf --layout=reverse --delimiter='\t' --prompt="$prompt" \
      --preview="git log --graph --color=always -20 --format='$_git_log_format' {2}" "$@" |
    cut -f2
}

gbdel() {
  git rev-parse --git-dir >/dev/null || return
  local base selected reply
  git symbolic-ref --quiet refs/remotes/origin/HEAD >/dev/null ||
    git remote set-head origin --auto || return
  base=$(git symbolic-ref --short refs/remotes/origin/HEAD) || return
  selected=$(
    _git_pick_branch 'Delete branches> ' "$(git branch --show-current) ${base#origin/}" --tac --multi \
      --header="TAB mark · preview: not in $base" \
      --preview="git log --color=always --format='$_git_log_format' ${(qq)base}..{2}"
  )
  [ -z "$selected" ] && return 0

  sed 's/^/  /' <<< "$selected"
  read -r "reply?Force-delete these branches? [y/N] "
  [[ $reply == [yY]* ]] && xargs git branch -D <<< "$selected"
}

gbsel() {
  git rev-parse --git-dir >/dev/null || return
  local branch
  branch=$(_git_pick_branch 'Switch branch> ' '')
  [ -z "$branch" ] && return 0
  git switch "$branch"
}

_git_pick_file() {
  awk 'NR == FNR { keep[$0]; next } $0 in keep && !seen[$0]++' \
    <(git -c core.quotePath=false ls-files) <(git -c core.quotePath=false log --relative --name-only --format=) |
    fzf --scheme=path --tiebreak=index --prompt='Log file> ' \
      --preview="git log --color=always -10 --format='$_git_log_format' -- {}"
}

glog() {
  git rev-parse --git-dir >/dev/null || return
  local file pathspec
  while file=${1:-$(_git_pick_file)}; [ -n "$file" ]; do
    pathspec=${(j: :)${(@qq)${@:-$file}}}
    git log --color=always --format="$_git_log_format" -- "${@:-$file}" |
      fzf --ansi --no-sort --layout=reverse --prompt='Log> ' \
        --header='ENTER open diff · ESC/CTRL-C back to files' \
        --preview="git show --color=always --stat --patch --format='$_git_log_format' {1} -- $pathspec" \
        --bind="enter:execute:git show --stat --patch --format='$_git_log_format' {1} -- $pathspec | $_git_pager"
    (( $# == 0 )) || return 0
  done
}

_git_diff_rows() {
  awk -F'\t' -v short="$1" '
    /^:/ { paths[++n] = $2; status[$2] = substr($1, length($1)); next }
    NF { counts[$3] = sprintf("\033[32m+%-4s\033[31m-%-4s\033[0m", $1, $2) }
    END {
      for (i = 1; i <= n; i++) {
        path = paths[i]; s = status[path]; color = s == "A" ? 32 : s == "D" ? 31 : 33
        name = path; if (short) sub(".*/", "", name)
        printf "%s\t\033[%sm%s\033[0m %s %s\n", path, color, s, path in counts ? counts[path] : sprintf("%10s", ""), name
      }
    }'
}

gbmerge() {
  git rev-parse --git-dir >/dev/null || return
  local current target result tree conflicts header changes
  current=$(git rev-parse --abbrev-ref HEAD) || return
  while target=${1:-$(_git_pick_branch "Merge into $current> " "$current")}; [ -n "$target" ]; do
    result=$(git merge-tree --write-tree --name-only --no-messages HEAD "$target")
    [ -n "$result" ] || return 1
    tree=${result%%$'\n'*}
    conflicts=${result#"$tree"}
    [ -n "$conflicts" ] && header="CONFLICTS:${conflicts//$'\n'/ }" || header=clean
    changes=$(git -c core.quotePath=false diff --raw --numstat --no-renames HEAD "$tree") || return
    _git_diff_rows short <<< "$changes" |
      fzf --ansi --no-sort --layout=reverse --delimiter='\t' --with-nth=2 \
        --prompt="Merge $target into $current> " --header="$header" \
        --preview="git diff --color=always --stat --patch HEAD $tree -- :/{1}" \
        --bind="enter:execute:git diff --stat --patch HEAD $tree -- :/{1} | $_git_pager"
    (( $# == 0 )) || return 0
  done
}

gadd() {
  git rev-parse --git-dir >/dev/null || return
  local index selected
  index=$(mktemp) || return
  {
    cp "$(git rev-parse --git-path index)" "$index" 2>/dev/null || rm -f "$index"
    GIT_INDEX_FILE=$index git add --ignore-errors --ignore-removal --intent-to-add .
    selected=$(
      {
        GIT_INDEX_FILE=$index git -c core.quotePath=false diff --raw --numstat --no-renames --relative --diff-filter=a
        GIT_INDEX_FILE=$index git -c core.quotePath=false diff --raw --no-renames --relative --diff-filter=A
      } |
        _git_diff_rows |
        fzf --ansi --multi --no-sort --layout=reverse --delimiter='\t' --with-nth=2 \
          --prompt='Add files> ' --header='TAB mark · ENTER add' \
          --preview="GIT_INDEX_FILE='$index' git diff --color=always --stat --patch -- {1}" |
        cut -f1
    )
  } always {
    rm -f "$index"
  }
  [ -z "$selected" ] && return 0
  git add --pathspec-from-file=- <<< "$selected"
  gs
}