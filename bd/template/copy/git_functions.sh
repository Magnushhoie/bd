_git_log_format='%C(auto)%h %C(blue)%cr%C(auto)%d %s'

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
  base=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD) || {
    echo 'gbdel: origin/HEAD is not set. Run: git remote set-head origin --auto' >&2
    return 1
  }
  selected=$(
    _git_pick_branch 'Delete branches> ' "$(git branch --show-current) ${base#origin/}" --tac --multi \
      --header="TAB mark · preview: not in $base" \
      --preview="git log --color=always --format='$_git_log_format' $base..{2}"
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
  local prompt=$1
  shift
  awk 'NR == FNR { keep[$0]; next } $0 in keep && !seen[$0]++' \
    <("$@") <(git log --relative --name-only --format=) |
    fzf --scheme=path --tiebreak=index --prompt="$prompt" \
      --preview="git log --color=always -10 --format='$_git_log_format' -- {}"
}

glog() {
  git rev-parse --git-dir >/dev/null || return
  local file
  while file=${1:-$(_git_pick_file 'Log file> ' git ls-files)}; [ -n "$file" ]; do
    git log --color=always --format="$_git_log_format" -- "${@:-$file}" |
      fzf --ansi --no-sort --layout=reverse --prompt='Log> ' \
        --header='ENTER open diff · ESC/CTRL-C back to files' \
        --preview="git show --color=always --stat --patch --format='$_git_log_format' {1} -- ${*:-$file}" \
        --bind="enter:execute:git show --stat --patch --format='$_git_log_format' {1} -- ${*:-$file}"
    [ -n "$1" ] && return 0
  done
}

gblame() {
  git rev-parse --git-dir >/dev/null || return
  local file lines
  while file=${1:-$(_git_pick_file 'Blame file> ' git grep -Il '')}; [ -n "$file" ]; do
    lines=$(git blame -f -w -C --root --date=relative "$file") || return
    fzf --no-sort --layout=reverse --prompt='Blame> ' \
      --header='ENTER open diff · ESC/CTRL-C back to files' \
      --preview="git show --color=always --stat --patch --format='$_git_log_format' {1} -- :/{2}" \
      --bind="enter:execute:git show --stat --patch --format='$_git_log_format' {1} -- :/{2}" <<< "$lines"
    [ -n "$1" ] && return 0
  done
}

_git_diff_files() {
  local prompt=$1 header=$2 changes
  shift 2
  changes=$(git diff --raw --numstat --no-renames "$@") || return
  awk -F'\t' '
    /^:/ { status[$2] = substr($1, length($1)); next }
    NF {
      name = $3; sub(".*/", "", name)
      printf "%s\t%s \033[32m+%-4s\033[31m-%-4s\033[0m %s\n", $3, status[$3], $1, $2, name
    }' <<< "$changes" |
    fzf --ansi --no-sort --layout=reverse --delimiter='\t' --with-nth=2 \
      --prompt="$prompt" --header="$header" \
      --preview="git diff --color=always --stat --patch $* -- :/{1}" \
      --bind="enter:execute:git diff --stat --patch $* -- :/{1}"
}

gbmerge() {
  git rev-parse --git-dir >/dev/null || return
  local source target result tree conflicts header
  source=$(git rev-parse --abbrev-ref HEAD) || return
  while target=${1:-$(_git_pick_branch "PR $source into> " "$source")}; [ -n "$target" ]; do
    result=$(git merge-tree --write-tree --name-only --no-messages "$target" HEAD)
    [ -n "$result" ] || return 1
    tree=${result%%$'\n'*}
    conflicts=${result#"$tree"}
    [ -n "$conflicts" ] && header="CONFLICTS:${conflicts//$'\n'/ }" || header=clean
    _git_diff_files "PR $source into $target> " "$header" "$target" "$tree" || return
    [ -n "$1" ] && return 0
  done
}