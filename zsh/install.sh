#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/rapidrabbit76/oh-my-config.git"
ZSHRC="$HOME/.zshrc"
BACKUP_FILE="$ZSHRC.bak.$(date +%Y%m%d%H%M%S)"
OMZ_DIR="$HOME/.oh-my-zsh"
OMZ_CUSTOM="${ZSH_CUSTOM:-$OMZ_DIR/custom}"
REMOTE_MODE=false
CLEANUP_DIR=""

if [[ "${BASH_SOURCE[0]}" == "bash" ]] || [[ "${BASH_SOURCE[0]}" == "/dev/stdin" ]] || [[ ! -f "${BASH_SOURCE[0]}" ]]; then
  REMOTE_MODE=true
  CLEANUP_DIR="$(mktemp -d)"
  trap 'rm -rf "$CLEANUP_DIR"' EXIT
  if command -v git &>/dev/null; then
    git clone --depth 1 "$REPO_URL" "$CLEANUP_DIR" 2>/dev/null
  else
    echo "Error: git is required for remote install"
    exit 1
  fi
  SCRIPT_DIR="$CLEANUP_DIR/zsh"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}  ✓${NC} $1"; }
warn()  { echo -e "${YELLOW}  ⚠${NC} $1"; }
error() { echo -e "${RED}  ✗${NC} $1"; }

PROGRESS_CURRENT=0
PROGRESS_TOTAL=0

progress_start() {
  PROGRESS_CURRENT=0
  PROGRESS_TOTAL=$1
}

progress_tick() {
  local label="${1:-}"
  PROGRESS_CURRENT=$((PROGRESS_CURRENT + 1))
  local percent=$((PROGRESS_CURRENT * 100 / PROGRESS_TOTAL))
  local width=30
  local filled=$((PROGRESS_CURRENT * width / PROGRESS_TOTAL))
  local empty=$((width - filled))
  local bar=""
  for ((i = 0; i < filled; i++)); do bar+="█"; done
  for ((i = 0; i < empty; i++)); do bar+="░"; done
  printf "\r  ${CYAN}%s${NC} ${DIM}%3d%%${NC} ${DIM}%s${NC}" "$bar" "$percent" "$label"
  if [[ $PROGRESS_CURRENT -eq $PROGRESS_TOTAL ]]; then
    printf "\n"
  fi
}

show_banner() {
  echo ""
  echo -e "${BOLD}${CYAN}"
  cat << 'BANNER'
    ╔═══════════════════════════════════════════════╗
    ║                                               ║
    ║    ░█▄█░█░█░░░█▀▀░█▀█░█▀█░█▀▀░▀█▀░█▀▀░░    ║
    ║    ░█░█░░█░░░░█░░░█░█░█░█░█▀▀░░█░░█░█░░░    ║
    ║    ░▀░▀░░▀░░░░▀▀▀░▀▀▀░▀░▀░▀░░░▀▀▀░▀▀▀░░░    ║
    ║                                               ║
    ║          ⚡ Zsh Environment Setup              ║
    ║         Modern CLI + Starship prompt           ║
    ║                                               ║
    ╚═══════════════════════════════════════════════╝
BANNER
  echo -e "${NC}"
  echo -e "  ${DIM}oh-my-zsh · starship · modern CLI tools · cross-platform${NC}"
  echo ""
}

if [[ "${1:-}" == "--uninstall" ]]; then
  echo ""
  echo -e "${BOLD}${RED}  Uninstalling oh-my-config zsh...${NC}"
  echo ""

  [[ -f "$ZSHRC" ]] && rm -f "$ZSHRC" && ok "Removed ~/.zshrc"

  echo ""
  ok "Uninstall complete"
  warn "Restore from backup: ${DIM}cp ~/.zshrc.bak.* ~/.zshrc${NC}"
  warn "oh-my-zsh and CLI tools are NOT removed (manual cleanup)"
  exit 0
fi

show_banner

# ═══════════════════════════════════════════════════════════
# [1/7] Platform Detection
# ═══════════════════════════════════════════════════════════
echo -e "${BOLD}  [1/7] Platform detection${NC}"
echo ""

OS="unknown"
DISTRO=""
PKG_MANAGER=""
HAS_BREW=false
ARCH="$(uname -m)"

if [[ "$(uname)" == "Darwin" ]]; then
  OS="macos"
elif [[ "$(uname)" == "Linux" ]]; then
  OS="linux"
  if [[ -f /etc/os-release ]]; then
    DISTRO=$(. /etc/os-release && echo "$ID")
  fi
fi

if command -v brew &>/dev/null; then
  HAS_BREW=true
  PKG_MANAGER="brew"
elif command -v apt &>/dev/null; then
  PKG_MANAGER="apt"
elif command -v dnf &>/dev/null; then
  PKG_MANAGER="dnf"
elif command -v pacman &>/dev/null; then
  PKG_MANAGER="pacman"
fi

ok "Detected ${BOLD}$OS${NC} ($ARCH) ${DIM}[${PKG_MANAGER:-none}]${NC}"

ensure_brew() {
  if $HAS_BREW; then return 0; fi
  echo ""
  warn "Homebrew not found — many modern CLI tools install cleanly via brew"
  read -rp "  Install Homebrew? [Y/n] " answer
  if [[ "${answer:-Y}" =~ ^[Yy]?$ ]]; then
    if [[ "$OS" == "linux" ]]; then
      if [[ "$PKG_MANAGER" == "apt" ]]; then
        sudo apt update -qq && sudo apt install -y build-essential procps curl file git &>/dev/null
      elif [[ "$PKG_MANAGER" == "dnf" ]]; then
        sudo dnf groupinstall -y 'Development Tools' &>/dev/null
        sudo dnf install -y procps-ng curl file git &>/dev/null
      fi
    fi
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [[ "$OS" == "linux" ]]; then
      eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" 2>/dev/null || true
    elif [[ "$OS" == "macos" ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || \
      eval "$(/usr/local/bin/brew shellenv)" 2>/dev/null || true
    fi
    HAS_BREW=true
    PKG_MANAGER="brew"
    ok "Homebrew installed"
  fi
}

pkg_install() {
  local pkg="$1"
  if $HAS_BREW; then
    brew install "$pkg" &>/dev/null
  elif [[ "$PKG_MANAGER" == "apt" ]]; then
    sudo apt install -y "$pkg" &>/dev/null
  elif [[ "$PKG_MANAGER" == "dnf" ]]; then
    sudo dnf install -y "$pkg" &>/dev/null
  elif [[ "$PKG_MANAGER" == "pacman" ]]; then
    sudo pacman -S --noconfirm "$pkg" &>/dev/null
  else
    return 1
  fi
}

# apt에서 bat/fd 바이너리명이 다른 문제 해결용 심링크 생성
setup_apt_aliases() {
  if [[ "$PKG_MANAGER" != "apt" ]] || $HAS_BREW; then return; fi
  local bin_dir="$HOME/.local/bin"
  mkdir -p "$bin_dir"
  if command -v batcat &>/dev/null && ! command -v bat &>/dev/null; then
    ln -sf "$(which batcat)" "$bin_dir/bat"
    ok "Created bat → batcat symlink"
  fi
  if command -v fdfind &>/dev/null && ! command -v fd &>/dev/null; then
    ln -sf "$(which fdfind)" "$bin_dir/fd"
    ok "Created fd → fdfind symlink"
  fi
}

# GitHub release 바이너리 다운로드 헬퍼
install_from_gh_release() {
  local repo="$1" binary_name="$2" asset_pattern="$3"
  local bin_dir="$HOME/.local/bin"
  mkdir -p "$bin_dir"
  local tmp_dir
  tmp_dir="$(mktemp -d)"

  local url
  url=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null \
    | grep "browser_download_url.*$asset_pattern" \
    | head -1 \
    | cut -d '"' -f 4) || return 1

  [[ -z "$url" ]] && return 1

  local filename="${url##*/}"
  curl -fsSL "$url" -o "$tmp_dir/$filename" || { rm -rf "$tmp_dir"; return 1; }

  case "$filename" in
    *.tar.gz|*.tgz) tar xzf "$tmp_dir/$filename" -C "$tmp_dir" ;;
    *.zip) unzip -qo "$tmp_dir/$filename" -d "$tmp_dir" ;;
    *) chmod +x "$tmp_dir/$filename"; cp "$tmp_dir/$filename" "$bin_dir/$binary_name"; rm -rf "$tmp_dir"; return 0 ;;
  esac

  local found
  found=$(find "$tmp_dir" -name "$binary_name" -type f 2>/dev/null | head -1)
  if [[ -n "$found" ]]; then
    chmod +x "$found"
    cp "$found" "$bin_dir/$binary_name"
  else
    rm -rf "$tmp_dir"
    return 1
  fi
  rm -rf "$tmp_dir"
}

# ═══════════════════════════════════════════════════════════
# [2/7] Core dependencies (zsh, git, curl)
# ═══════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}  [2/7] Core dependencies${NC}"
echo ""

if command -v zsh &>/dev/null; then
  ok "Found $(zsh --version 2>/dev/null | head -1)"
else
  warn "zsh not found — installing"
  if $HAS_BREW; then
    brew install zsh
  elif [[ "$PKG_MANAGER" == "apt" ]]; then
    sudo apt update -qq && sudo apt install -y zsh
  elif [[ "$PKG_MANAGER" == "dnf" ]]; then
    sudo dnf install -y zsh
  elif [[ "$PKG_MANAGER" == "pacman" ]]; then
    sudo pacman -S --noconfirm zsh
  fi
  ok "zsh installed"
fi

for dep in git curl; do
  if command -v "$dep" &>/dev/null; then
    ok "Found $dep"
  else
    pkg_install "$dep" && ok "$dep installed" || error "Failed to install $dep"
  fi
done

# ═══════════════════════════════════════════════════════════
# [3/7] CLI tools
# ═══════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}  [3/7] Modern CLI tools${NC}"
echo ""

# brew_name:check_cmd:apt_name:dnf_name:pacman_name:description
TOOLS=(
  "neovim:nvim:neovim:neovim:neovim:Terminal editor"
  "eza:eza:::eza:Modern ls replacement"
  "bat:bat:bat:bat:bat:Cat with syntax highlighting"
  "ripgrep:rg:ripgrep:ripgrep:ripgrep:Fast recursive search"
  "fzf:fzf:fzf:fzf:fzf:Fuzzy finder"
  "zoxide:zoxide:::zoxide:Smarter cd"
  "btop:btop:btop:btop:btop:Resource monitor"
  "tealdeer:tldr:::tealdeer:Cheat sheet for CLI"
  "procs:procs:::procs:Modern ps replacement"
  "dust:dust:::dust:Disk usage analyzer"
  "duf:duf:duf:duf:duf:Disk free replacement"
  "lazygit:lazygit:::lazygit:Git TUI"
  "starship:starship:::starship:Cross-shell prompt"
  "fd:fd:fd-find:fd-find:fd:Modern find replacement"
  "git-delta:delta:::git-delta:Git diff viewer"
  "tmux:tmux:tmux:tmux:tmux:Terminal multiplexer"
  "yazi:yazi:::yazi:Terminal file manager"
  "ncdu:ncdu:ncdu:ncdu:ncdu:Disk usage explorer"
)

MISSING_TOOLS=()
MISSING_DESCS=()
MISSING_BREW=()
MISSING_NATIVE=()

for entry in "${TOOLS[@]}"; do
  IFS=':' read -r brew_name cmd apt_name dnf_name pacman_name desc <<< "$entry"
  if command -v "$cmd" &>/dev/null; then
    ok "$brew_name ${DIM}($desc)${NC}"
  else
    MISSING_TOOLS+=("$brew_name")
    MISSING_DESCS+=("$desc")
    MISSING_BREW+=("$brew_name")

    native_name=""
    case "$PKG_MANAGER" in
      apt) native_name="$apt_name" ;;
      dnf) native_name="$dnf_name" ;;
      pacman) native_name="$pacman_name" ;;
    esac
    MISSING_NATIVE+=("${native_name:-}")

    error "$brew_name ${DIM}($desc)${NC}"
  fi
done

if [[ ${#MISSING_TOOLS[@]} -gt 0 ]]; then
  echo ""
  echo -e "  ${YELLOW}╭─ Missing ${#MISSING_TOOLS[@]} tools ─────────────────────────╮${NC}"
  for i in "${!MISSING_TOOLS[@]}"; do
    printf "  ${YELLOW}│${NC}  %-18s %s\n" "${MISSING_TOOLS[$i]}" "${DIM}${MISSING_DESCS[$i]}${NC}"
  done
  echo -e "  ${YELLOW}╰──────────────────────────────────────────────╯${NC}"
  echo ""

  if $HAS_BREW; then
    echo -e "  ${DIM}Install all at once:${NC}"
    echo -e "  ${CYAN}brew install ${MISSING_BREW[*]}${NC}"
    echo ""
    read -rp "  Install missing tools via brew? [Y/n] " answer
    if [[ "${answer:-Y}" =~ ^[Yy]?$ ]]; then
      echo ""
      progress_start ${#MISSING_BREW[@]}
      INSTALL_FAILED=()
      for tool in "${MISSING_BREW[@]}"; do
        if brew install "$tool" &>/dev/null; then
          progress_tick "$tool"
        else
          progress_tick "$tool (failed)"
          INSTALL_FAILED+=("$tool")
        fi
      done
      [[ ${#INSTALL_FAILED[@]} -gt 0 ]] && warn "Failed: ${INSTALL_FAILED[*]}" || ok "All tools installed"
    else
      warn "Skipping — some aliases won't work"
    fi
  else
    # ─── Native package manager: install what's available ───
    NATIVE_INSTALLABLE=()
    NATIVE_NAMES=()
    NEED_OTHER_METHOD=()

    for i in "${!MISSING_TOOLS[@]}"; do
      if [[ -n "${MISSING_NATIVE[$i]}" ]]; then
        NATIVE_INSTALLABLE+=("${MISSING_TOOLS[$i]}")
        NATIVE_NAMES+=("${MISSING_NATIVE[$i]}")
      else
        NEED_OTHER_METHOD+=("${MISSING_TOOLS[$i]}")
      fi
    done

    if [[ ${#NATIVE_INSTALLABLE[@]} -gt 0 ]]; then
      echo -e "  ${CYAN}Available via $PKG_MANAGER: ${NATIVE_NAMES[*]}${NC}"
      read -rp "  Install these via $PKG_MANAGER? [Y/n] " answer
      if [[ "${answer:-Y}" =~ ^[Yy]?$ ]]; then
        [[ "$PKG_MANAGER" == "apt" ]] && sudo apt update -qq
        echo ""
        progress_start ${#NATIVE_NAMES[@]}
        for pkg in "${NATIVE_NAMES[@]}"; do
          if pkg_install "$pkg"; then
            progress_tick "$pkg"
          else
            progress_tick "$pkg (failed)"
          fi
        done
        setup_apt_aliases
      fi
    fi

    if [[ ${#NEED_OTHER_METHOD[@]} -gt 0 ]]; then
      echo ""
      echo -e "  ${YELLOW}Not in $PKG_MANAGER: ${NEED_OTHER_METHOD[*]}${NC}"
      echo ""
      echo -e "  ${BOLD}Choose install method:${NC}"
      echo -e "    ${CYAN}1)${NC} Install Homebrew (Linuxbrew) — installs all at once ${DIM}(recommended)${NC}"
      echo -e "    ${CYAN}2)${NC} Install individually (GitHub releases + cargo)"
      echo -e "    ${CYAN}3)${NC} Skip"
      echo ""
      read -rp "  Choice [1/2/3]: " method
      case "${method:-1}" in
        1)
          ensure_brew
          if $HAS_BREW; then
            echo ""
            progress_start ${#NEED_OTHER_METHOD[@]}
            for tool in "${NEED_OTHER_METHOD[@]}"; do
              if brew install "$tool" &>/dev/null; then
                progress_tick "$tool"
              else
                progress_tick "$tool (failed)"
              fi
            done
          fi
          ;;
        2)
          echo ""
          # starship: official installer
          if [[ " ${NEED_OTHER_METHOD[*]} " == *" starship "* ]]; then
            info "Installing starship..."
            if curl -sS https://starship.rs/install.sh | sh -s -- -y &>/dev/null; then
              ok "starship installed"
            else
              warn "starship install failed"
            fi
          fi

          # cargo-based tools
          cargo_crate_for() {
            case "$1" in
              eza)       echo "eza" ;;
              zoxide)    echo "zoxide" ;;
              tealdeer)  echo "tealdeer" ;;
              procs)     echo "procs" ;;
              dust)      echo "du-dust" ;;
              git-delta) echo "git-delta" ;;
              yazi)      echo "yazi-fm yazi-cli" ;;
              *)         echo "" ;;
            esac
          }

          CARGO_TOOLS=()
          for tool in "${NEED_OTHER_METHOD[@]}"; do
            [[ "$tool" == "starship" || "$tool" == "lazygit" || "$tool" == "duf" ]] && continue
            crate="$(cargo_crate_for "$tool")"
            [[ -n "$crate" ]] && CARGO_TOOLS+=("$tool")
          done

          if [[ ${#CARGO_TOOLS[@]} -gt 0 ]]; then
            if ! command -v cargo &>/dev/null; then
              info "cargo not found — installing Rust..."
              curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y &>/dev/null
              [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
            fi
            if command -v cargo &>/dev/null; then
              progress_start ${#CARGO_TOOLS[@]}
              for tool in "${CARGO_TOOLS[@]}"; do
                crate="$(cargo_crate_for "$tool")"
                if cargo install $crate &>/dev/null; then
                  progress_tick "$tool"
                else
                  progress_tick "$tool (failed)"
                fi
              done
            else
              warn "cargo not available — skipping cargo tools"
            fi
          fi

          # lazygit: GitHub binary release
          if [[ " ${NEED_OTHER_METHOD[*]} " == *" lazygit "* ]]; then
            info "Installing lazygit from GitHub..."
            lg_arch="x86_64"
            [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]] && lg_arch="arm64"
            if install_from_gh_release "jesseduffield/lazygit" "lazygit" "Linux_${lg_arch}.tar.gz"; then
              ok "lazygit installed to ~/.local/bin"
            else
              warn "lazygit install failed"
            fi
          fi

          # duf: GitHub binary release
          if [[ " ${NEED_OTHER_METHOD[*]} " == *" duf "* ]]; then
            info "Installing duf from GitHub..."
            duf_arch="amd64"
            [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]] && duf_arch="arm64"
            if install_from_gh_release "muesli/duf" "duf" "linux_${duf_arch}.tar.gz"; then
              ok "duf installed to ~/.local/bin"
            else
              warn "duf install failed"
            fi
          fi
          ;;
        3)
          warn "Skipping — some aliases won't work"
          ;;
      esac
    fi
  fi
else
  echo ""
  ok "All tools already installed"
fi

# ═══════════════════════════════════════════════════════════
# [4/7] Oh My Zsh + plugins
# ═══════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}  [4/7] Oh My Zsh + plugins${NC}"
echo ""

if [[ -d "$OMZ_DIR" ]]; then
  ok "Oh My Zsh already installed"
else
  info "Installing Oh My Zsh..."
  RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
  ok "Oh My Zsh installed"
fi

CUSTOM_PLUGINS=(
  "zsh-users/zsh-syntax-highlighting"
  "zsh-users/zsh-autosuggestions"
  "zsh-users/zsh-completions"
  "djui/alias-tips"
)

progress_start ${#CUSTOM_PLUGINS[@]}
for plugin_repo in "${CUSTOM_PLUGINS[@]}"; do
  plugin_name="${plugin_repo##*/}"
  plugin_dir="$OMZ_CUSTOM/plugins/$plugin_name"
  if [[ -d "$plugin_dir" ]]; then
    progress_tick "$plugin_name (exists)"
  else
    if git clone --depth 1 "https://github.com/$plugin_repo.git" "$plugin_dir" &>/dev/null; then
      progress_tick "$plugin_name"
    else
      progress_tick "$plugin_name (failed)"
    fi
  fi
done

# ═══════════════════════════════════════════════════════════
# [5/7] Nerd Font
# ═══════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}  [5/7] Nerd Font${NC}"
echo ""

NERD_FONT_FOUND=false
if [[ "$OS" == "macos" ]]; then
  if fc-list 2>/dev/null | grep -qi "nerd" || ls ~/Library/Fonts/*[Nn]erd* &>/dev/null 2>&1; then
    NERD_FONT_FOUND=true
  fi
elif [[ "$OS" == "linux" ]]; then
  if fc-list 2>/dev/null | grep -qi "nerd"; then
    NERD_FONT_FOUND=true
  fi
fi

if $NERD_FONT_FOUND; then
  ok "Nerd Font detected"
else
  warn "Nerd Font not detected — icons may not render"
  if [[ "$OS" == "macos" ]] && $HAS_BREW; then
    read -rp "  Install Hack Nerd Font? [Y/n] " answer
    if [[ "${answer:-Y}" =~ ^[Yy]?$ ]]; then
      brew install --cask font-hack-nerd-font &>/dev/null && ok "font-hack-nerd-font installed" || warn "Font install failed"
    fi
  elif [[ "$OS" == "linux" ]]; then
    read -rp "  Install Hack Nerd Font? [Y/n] " answer
    if [[ "${answer:-Y}" =~ ^[Yy]?$ ]]; then
      FONT_DIR="$HOME/.local/share/fonts"
      mkdir -p "$FONT_DIR"
      FONT_TMP="$(mktemp -d)"
      FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Hack.tar.xz"
      info "Downloading Hack Nerd Font..."
      if curl -fsSL "$FONT_URL" -o "$FONT_TMP/Hack.tar.xz" 2>/dev/null; then
        tar xf "$FONT_TMP/Hack.tar.xz" -C "$FONT_DIR" 2>/dev/null
        fc-cache -f "$FONT_DIR" 2>/dev/null
        ok "Hack Nerd Font installed to $FONT_DIR"
      else
        warn "Font download failed"
        echo -e "       ${DIM}Manual: https://www.nerdfonts.com/font-downloads${NC}"
      fi
      rm -rf "$FONT_TMP"
    fi
  fi
fi

# ═══════════════════════════════════════════════════════════
# [6/7] Dev tools (pyenv, nvm, rust, uv)
# ═══════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}  [6/7] Dev tools (optional)${NC}"
echo ""

if command -v pyenv &>/dev/null; then
  ok "pyenv $(pyenv --version 2>/dev/null)"
else
  read -rp "  Install pyenv (Python version manager)? [Y/n] " answer
  if [[ "${answer:-Y}" =~ ^[Yy]?$ ]]; then
    if [[ "$OS" == "linux" && "$PKG_MANAGER" == "apt" ]]; then
      sudo apt install -y make build-essential libssl-dev zlib1g-dev \
        libbz2-dev libreadline-dev libsqlite3-dev wget llvm \
        libncurses-dev xz-utils tk-dev libffi-dev liblzma-dev &>/dev/null || true
    elif [[ "$OS" == "linux" && "$PKG_MANAGER" == "dnf" ]]; then
      sudo dnf install -y gcc make zlib-devel bzip2-devel readline-devel \
        sqlite-devel openssl-devel tk-devel libffi-devel xz-devel &>/dev/null || true
    fi
    if $HAS_BREW; then
      brew install pyenv pyenv-virtualenv &>/dev/null && ok "pyenv installed" || warn "pyenv install failed"
    else
      curl -fsSL https://pyenv.run | bash &>/dev/null && ok "pyenv installed" || warn "pyenv install failed"
    fi
  else
    ok "Skipped pyenv"
  fi
fi

if [[ -d "$HOME/.nvm" ]] || command -v nvm &>/dev/null; then
  ok "nvm found"
else
  read -rp "  Install nvm (Node version manager)? [Y/n] " answer
  if [[ "${answer:-Y}" =~ ^[Yy]?$ ]]; then
    if $HAS_BREW; then
      brew install nvm &>/dev/null
      mkdir -p "$HOME/.nvm"
      ok "nvm installed (via brew)"
    else
      curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash &>/dev/null && ok "nvm installed" || warn "nvm install failed"
    fi
  else
    ok "Skipped nvm"
  fi
fi

if command -v cargo &>/dev/null; then
  ok "cargo/rust found"
else
  read -rp "  Install Rust? [Y/n] " answer
  if [[ "${answer:-Y}" =~ ^[Yy]?$ ]]; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y &>/dev/null && ok "rust installed" || warn "rust install failed"
    [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
  else
    ok "Skipped rust"
  fi
fi

if command -v uv &>/dev/null; then
  ok "uv found"
else
  read -rp "  Install uv (fast Python package manager)? [Y/n] " answer
  if [[ "${answer:-Y}" =~ ^[Yy]?$ ]]; then
    curl -LsSf https://astral.sh/uv/install.sh | sh &>/dev/null && ok "uv installed" || warn "uv install failed"
  else
    ok "Skipped uv"
  fi
fi

# ═══════════════════════════════════════════════════════════
# [7/7] Deploy .zshrc
# ═══════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}  [7/7] Deploy config${NC}"
echo ""

if [[ -f "$ZSHRC" ]] || [[ -L "$ZSHRC" ]]; then
  cp -P "$ZSHRC" "$BACKUP_FILE"
  ok "Backed up to ${DIM}$BACKUP_FILE${NC}"
fi

cp "$SCRIPT_DIR/.zshrc" "$ZSHRC"
ok "Deployed .zshrc"

if [[ ! -f "$HOME/.zshrc.local" ]]; then
  cat > "$HOME/.zshrc.local" << 'LOCAL'
# Machine-specific config — not tracked by git
# Add API keys, custom PATHs, and local aliases here
#
# export OPENAI_API_KEY="sk-..."
# export PATH="$PATH:/custom/path"
LOCAL
  ok "Created ~/.zshrc.local ${DIM}(put secrets here)${NC}"
else
  ok "~/.zshrc.local already exists"
fi

CURRENT_SHELL=$(basename "$SHELL")
if [[ "$CURRENT_SHELL" != "zsh" ]]; then
  ZSH_PATH=$(which zsh 2>/dev/null || echo "")
  if [[ -n "$ZSH_PATH" ]]; then
    echo ""
    read -rp "  Set zsh as default shell? [Y/n] " answer
    if [[ "${answer:-Y}" =~ ^[Yy]?$ ]]; then
      if ! grep -qx "$ZSH_PATH" /etc/shells 2>/dev/null; then
        echo "$ZSH_PATH" | sudo tee -a /etc/shells >/dev/null
      fi
      if [[ "$OS" == "linux" ]]; then
        sudo chsh -s "$ZSH_PATH" "$(whoami)" && ok "Default shell set to zsh" || warn "chsh failed — run: chsh -s $ZSH_PATH"
      else
        chsh -s "$ZSH_PATH" && ok "Default shell set to zsh" || warn "chsh failed"
      fi
    fi
  fi
fi

echo ""
echo -e "${GREEN}  ╔═══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}  ║         Installation complete! 🎉             ║${NC}"
echo -e "${GREEN}  ╠═══════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}  ║                                               ║${NC}"
echo -e "${GREEN}  ║${NC}  ${CYAN}source ~/.zshrc${NC}  or restart terminal       ${GREEN}║${NC}"
echo -e "${GREEN}  ║${NC}  ${CYAN}~/.zshrc.local${NC}  for secrets & overrides    ${GREEN}║${NC}"
echo -e "${GREEN}  ║                                               ║${NC}"
echo -e "${GREEN}  ║${NC}  ${DIM}Uninstall: install.sh --uninstall${NC}           ${GREEN}║${NC}"
echo -e "${GREEN}  ║                                               ║${NC}"
echo -e "${GREEN}  ╚═══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${DIM}Also install tmux & yazi configs:${NC}"
echo -e "  ${CYAN}bash <(curl -fsSL https://raw.githubusercontent.com/rapidrabbit76/oh-my-config/main/tmux/install.sh)${NC}"
echo -e "  ${CYAN}bash <(curl -fsSL https://raw.githubusercontent.com/rapidrabbit76/oh-my-config/main/yazi/install.sh)${NC}"
echo ""
