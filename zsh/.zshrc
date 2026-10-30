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
bindkey '^@' autosuggest-accept

# ─── tmux: 인자 없이 `tmux` 치면 세션 관리 TUI ─────────
# 세션 0개면 새로 만들고, 1개면 바로 붙고, 여러 개면 fzf 창 (fzf 없으면 attach).
#   Enter: 접속 · Ctrl-T: 새 세션 · Ctrl-R: 이름 변경 · Ctrl-X: 삭제 · Esc: 닫기
#   목록에 없는 이름을 치고 Enter 해도 그 이름으로 새 세션을 만듦.
unalias tmux 2>/dev/null
_omc_tmux_new() {
    local name=${1//[^a-zA-Z0-9_-]/_}
    [[ -n $name ]] || return 1
    if [[ -n $TMUX ]]; then
        command tmux new-session -d -s "$name" && command tmux switch-client -t "=$name"
    else
        command tmux new-session -s "$name"
    fi
}
tmux() {
    (( $# )) && { command tmux "$@"; return }
    local go=attach-session
    [[ -n $TMUX ]] && go=switch-client
    local -a sessions lines padded
    local out rc query key choice name line n w first=1
    while true; do
        sessions=("${(@f)$(command tmux list-sessions \
            -F '#{session_name}	#{session_windows} win	#{?session_attached,● attached,}' 2>/dev/null)}")
        sessions=("${(@)sessions:#}")
        # 1열: 실제 세션 이름 (숨김, fzf {1}) · 2열부터 표시용 (이름 열 너비 맞춤)
        w=8; padded=()
        for line in "${sessions[@]}"; do n=${line%%	*}; (( ${#n} > w )) && w=${#n}; done
        for line in "${sessions[@]}"; do n=${line%%	*}; padded+=("$n	${(r:$w:)n}	${line#*	}"); done
        sessions=("${padded[@]}")
        if (( ${#sessions} == 0 )); then
            command tmux new-session; return
        elif (( first && ${#sessions} == 1 )) && [[ -z $TMUX ]]; then
            command tmux attach-session; return
        elif ! command -v fzf &>/dev/null; then
            [[ -n $TMUX ]] || command tmux attach-session; return
        fi
        first=0
        out=$(printf '%s\n' "${sessions[@]}" | fzf \
            --layout=reverse --height=~60% --min-height=14 --info=inline-right \
            --border=rounded --border-label=' 󰆍 tmux sessions ' --border-label-pos=3 \
            --padding=0,1 --tabstop=2 --delimiter='\t' --with-nth=2.. --prompt='   ' --pointer='▶' --marker=' ' --gutter=' ' --ghost='세션 검색 · 새 이름 입력' \
            --header-first --header=$' Enter 접속 · ^T 새 세션 · ^R 이름 변경 · ^X 삭제\n Esc 닫기 · 새 이름 + Enter: 생성' \
            --preview 'tmux list-windows -t "="{1} -F "#{?window_active,▶, } #{window_index}  #{window_name}  (#{pane_current_command})  #{b:pane_current_path}"' \
            --preview-window='right,42%,border-left' --preview-label=' windows ' --preview-label-pos=3 \
            --color='gutter:-1,border:#6c7086,label:#cba6f7,preview-border:#6c7086,header:#a6adc8,prompt:#89b4fa,pointer:#fab387,hl:#f9e2af,hl+:#f9e2af,fg+:#cdd6f4,bg+:#313244,info:#6c7086' \
            --print-query --expect=ctrl-t,ctrl-r,ctrl-x)
        rc=$?
        (( rc > 1 )) && return 0
        lines=("${(@f)out}")
        query=$lines[1] key=$lines[2] choice=${lines[3]%%$'\t'*}
        case $key in
            ctrl-t)
                name=${query:-${PWD:t}}
                [[ -n $query ]] || vared -p '  새 세션 이름: ' name
                _omc_tmux_new "$name"; return ;;
            ctrl-r)
                [[ -n $choice ]] || continue
                name=$choice
                vared -p "  '$choice' 새 이름: " name
                name=${name//[^a-zA-Z0-9_-]/_}
                [[ -n $name && $name != $choice ]] && command tmux rename-session -t "=$choice" "$name"
                continue ;;
            ctrl-x)
                [[ -n $choice ]] || continue
                if read -q "?  세션 '$choice' 를 삭제할까요? [y/N] "; then
                    command tmux kill-session -t "=$choice"
                fi
                echo
                continue ;;
            *)
                if [[ -n $choice ]]; then command tmux $go -t "=$choice"; return
                elif [[ -n $query ]]; then _omc_tmux_new "$query"; return
                else continue; fi ;;
        esac
    done
}

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

# oh-my-config auto-update (asks before updating config files)
[[ -f "$HOME/.local/share/oh-my-config/update.sh" ]] && bash "$HOME/.local/share/oh-my-config/update.sh" --auto
