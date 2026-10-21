setopt HIST_IGNORE_SPACE
HISTORY_IGNORE="(ls|cd)"

# General
alias l="ls -alhtr"
alias sbp="source ~/.zshrc"
alias vbp="vim ~/.zshrc"
alias lbp="less ~/.zshrc"

# Conda
alias ci="conda info --envs"
alias ca="conda activate"

# General
alias autolint="isort . && black --line-length 120 . && flake8 ."

vram() {
    nvidia-smi --id=0 \
        --query-gpu=memory.used,memory.total,utilization.gpu,temperature.gpu \
        --format=csv,noheader,nounits |
        awk -F', *' '{printf "VRAM: %s/%s MiB | GPU: %s%% | Temp: %s°C\n", $1, $2, $3, $4}'
}

# Git
alias ga="git add"
alias gmp="git commit -m fix && git push"
function gm() {
    git commit -m "$*"
}
alias gs="git status"
alias gst="git status -sb"
alias gl="git log"
alias glog="git log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"
alias gw="git whatchanged"
alias gd="git diff"
alias gdc="git diff --cached"
alias gdcc="git diff HEAD^ HEAD"
alias gp="git pull"
alias gpp="git push"
alias gb="git branch"

gbage() {
  git for-each-ref --sort=-committerdate --format='%(committerdate:relative)%09%(refname:short)' refs/heads
}

# Git functions
#source git_functions.zsh
#source gblame.zsh