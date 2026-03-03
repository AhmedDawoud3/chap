#!/usr/bin/env bash
# setup.sh - Install chap and its dependencies.
#
# Installs:
#   /usr/local/bin/chap                 <- the main executable
#   /usr/local/lib/chap/helper.py       <- Python helper (called by chap internally)
#   /usr/local/lib/chap/chap.usage.kdl  <- usage spec (for shell completions)

set -euo pipefail

_tty_colors() { [[ -z "${NO_COLOR:-}" && -t 1 ]]; }

log_info() { _tty_colors && echo -e "\033[0;36m[INFO]\033[0m $*" || echo "[INFO] $*"; }
log_ok()   { _tty_colors && echo -e "\033[0;32m[ OK ]\033[0m $*" || echo "[ OK ] $*"; }
log_warn() { _tty_colors && echo -e "\033[0;33m[WARN]\033[0m $*" || echo "[WARN] $*"; }
log_fail() { _tty_colors && echo -e "\033[1;31m[FAIL]\033[0m $*" >&2 || echo "[FAIL] $*" >&2; exit 1; }

section() {
    if _tty_colors; then
        echo -e "\n\033[1;37m$*\033[0m"
        echo -e "\033[0;90m$(printf '%.0s─' {1..50})\033[0m"
    else
        echo ""
        echo "$*"
        printf '%.0s-' {1..50}; echo
    fi
}

BIN_DIR="/usr/local/bin"
LIB_DIR="/usr/local/lib/chap"
BIN_TARGET="$BIN_DIR/chap"
LIB_TARGET="$LIB_DIR/helper.py"
SPEC_TARGET="$LIB_DIR/chap.usage.kdl"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if _tty_colors; then
    echo -e "\033[1;35m"
    echo "  ┌─────────────────────────────┐"
    echo "  │        chap  installer      │"
    echo "  └─────────────────────────────┘"
    echo -e "\033[0m"
else
    echo ""
    echo "  chap installer"
    echo ""
fi

section "Checking dependencies"

if command -v ffmpeg &>/dev/null; then
    log_ok "ffmpeg found  ($(ffmpeg -version 2>&1 | head -1 | cut -d' ' -f1-3))"
else
    log_fail "ffmpeg is not installed or not in PATH.
        Please install it from: https://ffmpeg.org/download.html"
fi

if command -v python3 &>/dev/null; then
    log_ok "python3 found ($(python3 --version))"
else
    log_fail "python3 is not installed or not in PATH.
        Please install it from: https://www.python.org/downloads/"
fi

section "Checking source files"

if [[ -f "$SCRIPT_DIR/chap.sh" ]]; then
    log_ok "chap.sh         found in '$SCRIPT_DIR'"
else
    log_fail "chap.sh not found in '$SCRIPT_DIR'. Make sure you run setup.sh from the project directory."
fi

if [[ -f "$SCRIPT_DIR/helper.py" ]]; then
    log_ok "helper.py       found in '$SCRIPT_DIR'"
else
    log_fail "helper.py not found in '$SCRIPT_DIR'. Make sure you run setup.sh from the project directory."
fi

if [[ -f "$SCRIPT_DIR/chap.usage.kdl" ]]; then
    log_ok "chap.usage.kdl  found in '$SCRIPT_DIR'"
else
    log_warn "chap.usage.kdl not found — shell completions will not be installed."
fi

section "Installing"

if mkdir -p "$LIB_DIR" 2>/dev/null; then
    log_ok "Directory ready: '$LIB_DIR'"
else
    log_fail "Cannot create '$LIB_DIR'. You may need write access to /usr/local/."
fi

if cp "$SCRIPT_DIR/helper.py" "$LIB_TARGET" 2>/dev/null; then
    chmod 644 "$LIB_TARGET"
    log_ok "Installed helper.py      ->  $LIB_TARGET"
else
    log_fail "Cannot write to '$LIB_TARGET'. You may need write access to /usr/local/."
fi

if cp "$SCRIPT_DIR/chap.sh" "$BIN_TARGET" 2>/dev/null; then
    chmod 755 "$BIN_TARGET"
    log_ok "Installed chap           ->  $BIN_TARGET"
else
    log_fail "Cannot write to '$BIN_TARGET'. You may need write access to /usr/local/."
fi

if [[ -f "$SCRIPT_DIR/chap.usage.kdl" ]]; then
    if cp "$SCRIPT_DIR/chap.usage.kdl" "$SPEC_TARGET" 2>/dev/null; then
        chmod 644 "$SPEC_TARGET"
        log_ok "Installed chap.usage.kdl ->  $SPEC_TARGET"
    else
        log_warn "Could not install chap.usage.kdl — shell completions unavailable."
    fi
fi

# ---------------------------------------------------------------------------
# Shell completions (optional — requires usage-cli)
# ---------------------------------------------------------------------------

section "Shell completions"

if ! command -v usage &>/dev/null; then
    log_warn "usage-cli not found — skipping completion generation."
    log_warn "Install it from: https://usage.jdx.dev to enable tab completions."
else
    log_ok "usage-cli found ($(usage --version 2>&1))"

    # Detect which shells are available and generate completions for each
    _install_completion() {
        local shell="$1" comp_dir="$2" comp_file="$3"
        if command -v "$shell" &>/dev/null && [[ -d "$comp_dir" ]]; then
            if usage generate completion "$shell" chap \
                   --file "$SPEC_TARGET" \
                   --usage-cmd "chap --usage-spec" \
                   > "$comp_file" 2>/dev/null; then
                log_ok "Installed $shell completions  ->  $comp_file"
            else
                log_warn "Failed to generate $shell completions."
            fi
        fi
    }

    _install_completion bash "/etc/bash_completion.d"        "/etc/bash_completion.d/chap"
    _install_completion zsh  "/usr/local/share/zsh/site-functions" "/usr/local/share/zsh/site-functions/_chap"
    _install_completion fish "$HOME/.config/fish/completions" "$HOME/.config/fish/completions/chap.fish"

    log_info "Reload your shell or open a new terminal to activate completions."
fi

if _tty_colors; then
    echo -e "\n\033[1;32m  Installation complete.\033[0m"
    echo -e "\033[0;90m$(printf '%.0s─' {1..50})\033[0m"
    echo -e "  \033[0;37mTry it:\033[0m"
    echo -e "  \033[0;36mchap\033[0m video.mp4 \033[0;33m\"00:00 Intro\"\033[0m \033[0;33m\"01:30 Main Content\"\033[0m \033[0;33m\"05:00 Outro\"\033[0m"
    echo ""
else
    echo ""
    echo "  Installation complete."
    echo "  Try it:"
    echo "  chap video.mp4 \"00:00 Intro\" \"01:30 Main Content\" \"05:00 Outro\""
    echo ""
fi
