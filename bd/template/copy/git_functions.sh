gbdel() {
  git rev-parse --git-dir >/dev/null || return
  local base=main selected reply
  selected=$(
    git for-each-ref --sort=committerdate \
      --format='%(committerdate:relative)%09%(refname:short)' refs/heads |
    awk -F'\t' -v base="$base" -v current="$(git branch --show-current)" '$2 != base && $2 != current' |
    fzf --layout=reverse --multi --delimiter='\t' --prompt='Delete branches> ' --header="TAB mark · preview: not in $base" \
      --preview="git log --color=always --oneline $base..{2}" |
    cut -f2
  )
  [ -z "$selected" ] && return 0

  printf '  %s\n' $selected
  read -r "reply?Force-delete these branches? [y/N] "
  [[ $reply == [yY]* ]] && xargs git branch -D <<< "$selected"
}


_git_pick_file() {
  local format='%C(auto)%h %C(blue)%cr%Creset %s'
  awk 'NR == FNR { text[$0]; next } $0 in text && !seen[$0]++' \
    <(git grep -Il '') <(git log --relative --name-only --format=) |
    fzf --scheme=path --tiebreak=index --prompt="$1" \
      --preview="git log --color=always -10 --format='$format' -- {}"
}

glog() {
  git rev-parse --git-dir >/dev/null || return
  local format='%C(auto)%h %C(blue)%cr%Creset %s'
  local file
  while file=${1:-$(_git_pick_file 'Log file> ')}; [ -n "$file" ]; do
    git log --color=always --format="$format" -- "${@:-$file}" |
      fzf --ansi --no-sort --layout=reverse --prompt='Log> ' \
        --header='ENTER open diff · ESC/CTRL-C back to files' \
        --preview="git show --color=always --stat --patch --format='$format' {1} -- ${*:-$file}" \
        --bind="enter:execute:git show --stat --patch --format='$format' {1} -- ${*:-$file}"
    [ -n "$1" ] && return 0
  done
}

gblame() {
  git rev-parse --git-dir >/dev/null || return
  local format='%C(auto)%h %C(blue)%cr%Creset %s'
  local file lines
  while file=${1:-$(_git_pick_file 'Blame file> ')}; [ -n "$file" ]; do
    lines=$(git blame -f -w -C --root --date=relative "$file") || return
    fzf --no-sort --layout=reverse --prompt='Blame> ' \
      --header='ENTER open diff · ESC/CTRL-C back to files' \
      --preview="git show --color=always --stat --patch --format='$format' {1} -- :/{2}" \
      --bind="enter:execute:git show --stat --patch --format='$format' {1} -- :/{2}" <<< "$lines"
    [ -n "$1" ] && return 0
  done
}

_git_pick_branch() {
  git for-each-ref --sort=-committerdate \
    --format='%(HEAD) %(committerdate:relative)%09%(refname:short)' refs/heads |
    fzf --delimiter='\t' --prompt="$1" \
      --preview='git log --graph --color=always -20 --format="%C(auto)%h %C(blue)%cr%C(auto)%d %s" {2}' |
    cut -f2
}

gbs() {
  git rev-parse --git-dir >/dev/null || return
  local branch
  branch=$(_git_pick_branch 'Switch branch> ')
  [ -z "$branch" ] && return 0
  git switch "$branch"
}

gbdiff() {
  git rev-parse --git-dir >/dev/null || return
  local ref changes
  while ref=${1:-$(_git_pick_branch 'Diff against> ')}; [ -n "$ref" ]; do
    changes=$(git diff --merge-base --name-status --no-renames "$ref") || return
    awk '
      BEGIN { FS = OFS = "\t"; color["A"] = 32; color["M"] = 33; color["D"] = 31 }
      NR == FNR { added[$3] = $1; deleted[$3] = $2; next }
      NF {
        a = added[$2]; d = deleted[$2]
        counts = a == "-" ? sprintf("%11s", "bin") : \
          sprintf("\033[32m%5s\033[0m \033[31m%-5s\033[0m", a + 0 ? "+" a : "", d + 0 ? "-" d : "")
        print $2, "\033[" color[$1] "m" $1 "\033[0m "counts" "$2
      }' <(git diff --merge-base --numstat --no-renames "$ref") - <<< "$changes" |
      fzf --ansi --no-sort --layout=reverse --delimiter='\t' --with-nth=2 --prompt="Diff vs $ref> " \
        --header='ENTER open diff · ESC/CTRL-C back · A added · M modified · D deleted' \
        --preview="git diff --color=always --merge-base '$ref' -- :/{1}" \
        --bind="enter:execute:git diff --merge-base '$ref' -- :/{1}"
    [ -n "$1" ] && return 0
  done
}