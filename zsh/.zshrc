# ─── Homebrew (Linux needs explicit shellenv) ──────────
if [[ -f /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -f /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

# ─── Oh My Zsh ──────────────────────────────────────────
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""
ZSH_DISABLE_COMPFIX="true"

plugins=(
    git
    sudo
    fzf
    zsh-syntax-highlighting
    zsh-autosuggestions
    zsh-completions
    alias-tips
    tmux
    aws
    docker
    docker-compose
    kubectl
    kube-ps1
)

source "$ZSH/oh-my-zsh.sh"

# ─── Completions (single init) ──────────────────────────
autoload -Uz compinit bashcompinit
compinit -C
bashcompinit
zstyle ':completion:*' menu select

# ─── Environment ────────────────────────────────────────
export EDITOR=nvim
export VISUAL=nvim
export PATH="$HOME/.local/bin:$HOME/bin:$PATH"

[[ "$(uname)" == "Darwin" ]] && {
    ulimit -n 4096
    export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES
}

# ─── Dev Tools ──────────────────────────────────────────
if command -v pyenv &>/dev/null; then
    export PYENV_VIRTUALENV_DISABLE_PROMPT=1
    eval "$(pyenv init -)"
    eval "$(pyenv virtualenv-init -)"
fi

export NVM_DIR="$HOME/.nvm"
if [[ -d "$NVM_DIR" ]]; then
    if [[ -n "${HOMEBREW_PREFIX:-}" ]] && [[ -s "$HOMEBREW_PREFIX/opt/nvm/nvm.sh" ]]; then
        \. "$HOMEBREW_PREFIX/opt/nvm/nvm.sh"
        [[ -s "$HOMEBREW_PREFIX/opt/nvm/etc/bash_completion.d/nvm" ]] && \. "$HOMEBREW_PREFIX/opt/nvm/etc/bash_completion.d/nvm"
    elif [[ -s "$NVM_DIR/nvm.sh" ]]; then
        \. "$NVM_DIR/nvm.sh"
        [[ -s "$NVM_DIR/bash_completion" ]] && \. "$NVM_DIR/bash_completion"
    fi
fi

[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"

command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"

# ─── Aliases ────────────────────────────────────────────
alias vim="nvim"
alias vi="nvim"
alias cat="bat"
alias grep="rg --color=always"
alias fzf="fzf --color=16"
alias cd="z"
alias top="btop"
alias help="tldr"
alias ps="procs"
alias du="dust"
alias df="duf"
alias lg="lazygit"

if command -v eza &>/dev/null; then
    alias ls="eza --icons --group-directories-first"
fi

# bat → batcat symlink fallback (Debian/Ubuntu)
if ! command -v bat &>/dev/null && command -v batcat &>/dev/null; then
    alias bat="batcat"
    alias cat="batcat"
fi

# fd → fdfind symlink fallback (Debian/Ubuntu)
if ! command -v fd &>/dev/null && command -v fdfind &>/dev/null; then
    alias fd="fdfind"
fi

alias ranger="y"
alias sy='sudo -E $(which yazi)'
alias zsh-config='$EDITOR ~/.zshrc'

# ─── Yazi cd-on-exit wrapper ────────────────────────────
function y() {
    local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
    yazi "$@" --cwd-file="$tmp"
    if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
        builtin cd -- "$cwd"
    fi
    rm -f -- "$tmp"
}

[[ -d "$HOME/.docker/completions" ]] && fpath=("$HOME/.docker/completions" $fpath)

# ─── Starship Prompt (must be LAST) ────────────────────
command -v starship &>/dev/null && eval "$(starship init zsh)"

# ─── Local overrides (secrets, machine-specific) ───────
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"
