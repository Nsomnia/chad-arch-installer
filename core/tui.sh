#!/usr/bin/env bash
#
# GLM5 Chad Arch Installer - TUI Framework
# Requires gum for interactive TUI
#

set -eo pipefail

if [[ -z "${_TUI_LOADED:-}" ]]; then
    readonly _TUI_LOADED=1
else
    return 0
fi

_TUI_BACKEND=""
_TUI_COLORS_ENABLED=true
_TUI_DEBUG=false

declare -A _TUI_COLORS=(
    [reset]='\033[0m'
    [bold]='\033[1m'
    [dim]='\033[2m'
    [red]='\033[31m'
    [green]='\033[32m'
    [yellow]='\033[33m'
    [blue]='\033[34m'
    [magenta]='\033[35m'
    [cyan]='\033[36m'
    [white]='\033[37m'
    [bg_red]='\033[41m'
    [bg_green]='\033[42m'
)

_tui_install_gum() {
    if command -v pacman &>/dev/null; then
        echo "Installing gum for TUI interface..."
        if sudo pacman -S --noconfirm gum &>/dev/null; then
            return 0
        fi
    fi
    return 1
}

_tui_init() {
    if command -v gum &>/dev/null && gum --version &>/dev/null; then
        _TUI_BACKEND="gum"
    elif [[ "$NON_INTERACTIVE" != "true" ]]; then
        echo "gum is required for interactive TUI but not found."
        if _tui_install_gum; then
            _TUI_BACKEND="gum"
        else
            echo "Error: Failed to install gum. Install manually: pacman -S gum" >&2
            _TUI_BACKEND="none"
        fi
    else
        _TUI_BACKEND="none"
    fi
    
    [[ -t 1 ]] || _TUI_COLORS_ENABLED=false
}

_tui_detect_backend() {
    echo "$_TUI_BACKEND"
}

_tui_require_interactive() {
    if [[ "$_TUI_BACKEND" != "gum" ]]; then
        echo "Error: Interactive TUI requires gum. Install with: pacman -S gum" >&2
        return 1
    fi
    return 0
}

_tui_color() {
    local color="${1}"
    shift
    
    if $_TUI_COLORS_ENABLED && [[ -v "_TUI_COLORS[$color]" ]]; then
        echo -en "${_TUI_COLORS[$color]}$*${_TUI_COLORS[reset]}"
    else
        echo -en "$*"
    fi
}

_tui_print() {
    local msg="$*"
    echo -e "$msg"
}

_tui_info() {
    gum style --foreground 45 "[INFO] $*"
}

_tui_success() {
    gum style --foreground 82 "[OK] $*"
}

_tui_warn() {
    gum style --foreground 214 "[WARN] $*"
}

_tui_error() {
    gum style --foreground 196 "[ERROR] $*"
}

_tui_header() {
    local title="$1"
    local width="${2:-60}"
    
    gum style --align center --width "$width" --padding "1 0" --border double --border-foreground 212 "$title"
}

_tui_section() {
    local title="$1"
    
    gum style --foreground 141 --bold "▶ $title"
}

_tui_menu_select() {
    local prompt="$1"
    shift
    local options=("$@")
    
    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        echo "${options[0]}"
        return 0
    fi
    
    _tui_require_interactive || return 1
    
    local result
    result=$(printf '%s\n' "${options[@]}" | gum choose --header="$prompt" --height=20 --cursor="→ " --cursor.foreground=82 --selected.foreground=82 2>/dev/null)
    local rc=$?
    if [[ $rc -eq 0 ]] && [[ -n "$result" ]]; then
        echo "$result"
        return 0
    fi
    return 1
}

_tui_filter() {
    local prompt="$1"
    shift
    local options=("$@")
    
    _tui_require_interactive || return 1
    
    printf '%s\n' "${options[@]}" | gum filter --header="$prompt" --placeholder="Type to filter..." --height=20
}

_tui_menu_multi() {
    local prompt="$1"
    shift
    local options=("$@")
    
    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        return 0
    fi
    
    _tui_require_interactive || return 1
    
    local result
    result=$(printf '%s\n' "${options[@]}" | gum choose --header="$prompt" --no-limit --height=25 --cursor="→ " --cursor.foreground=82 --selected.foreground=82 --selected="✓ " --unselected="○ " 2>/dev/null)
    local rc=$?
    if [[ $rc -eq 0 ]] && [[ -n "$result" ]]; then
        echo "$result"
    fi
    return $rc
}

_tui_input() {
    local prompt="$1"
    local default="${2:-}"
    local placeholder="${3:-Type here...}"
    
    _tui_require_interactive || return 1
    
    local result
    result=$(gum input --header="$prompt" --placeholder="$placeholder" --value="$default" --header.foreground=141 --prompt="❯ " --prompt.foreground=82 2>/dev/null)
    local rc=$?
    [[ $rc -eq 0 ]] && echo "$result" && return 0
    return 1
}

_tui_password() {
    local prompt="$1"
    
    _tui_require_interactive || return 1
    
    gum input --header="$prompt" --password --header.foreground=141 --prompt="🔒 " --prompt.foreground=196
}

_tui_confirm() {
    local prompt="$1"
    local default="${2:-n}"
    
    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        [[ "$default" == "y" ]]
        return $?
    fi
    
    _tui_require_interactive || return 1
    
    local gum_default="no"
    [[ "$default" == "y" ]] && gum_default="yes"
    gum confirm "$prompt" --default="$gum_default" --selected.background=82 --selected.foreground=0 --unselected.background=240 --unselected.foreground=15 --prompt.border="rounded" --prompt.padding="1 3" 2>/dev/null
}

_tui_box() {
    local title="${1:-}"
    local content="${2:-}"
    local border_style="${3:-rounded}"
    local border_color="${4:-141}"
    
    local full_content=""
    if [[ -n "$title" && -n "$content" ]]; then
        full_content="$title"$'\n'"──────────────────────"$'\n'"$content"
    elif [[ -n "$content" ]]; then
        full_content="$content"
    else
        full_content="$title"
    fi
    echo -e "$full_content" | gum style --border="$border_style" --border-foreground="$border_color" --padding="1 2"
}

_tui_style() {
    local text="$*"
    
    gum style "$text"
}

_tui_spinner() {
    local pid=$1
    local msg="${2:-Processing...}"
    
    local spin_pid
    (while kill -0 "$pid" 2>/dev/null; do sleep 0.1; done) &
    spin_pid=$!
    gum spin --spinner dot --title "$msg" -- sleep 3600 &
    local gum_pid=$!
    wait "$pid" 2>/dev/null
    kill "$gum_pid" "$spin_pid" 2>/dev/null
}

_tui_spin() {
    local msg="${1:-Processing...}"
    shift
    
    gum spin --spinner dot --title "$msg" -- "$@"
}

_tui_progress() {
    local current="$1"
    local total="$2"
    local msg="${3:-}"
    local width="${4:-40}"
    
    gum progress --width "$width" --title "$msg" -- "$current" "$total"
}

_tui_table() {
    local -n data=$1
    local headers=("${@:2}")
    
    if [[ ${#data[@]} -gt 0 ]]; then
        local gum_data=""
        local separator="│"
        
        for row in "${data[@]}"; do
            gum_data+="$row"$'\n'
        done
        
        echo "$gum_data" | gum table --widths="${#headers[*]}" --separator="$separator"
        return
    fi
    
    local max_widths=()
    for h in "${headers[@]}"; do
        max_widths+=(${#h})
    done
    
    for row in "${data[@]}"; do
        IFS='|' read -ra cols <<< "$row"
        for i in "${!cols[@]}"; do
            (( ${#cols[$i]} > ${max_widths[$i]} )) && max_widths[i]=${#cols[$i]}
        done
    done
    
    local separator="+"
    for w in "${max_widths[@]}"; do
        separator+="$(printf '%*s' "$((w + 2))" '' | tr ' ' '-')+"
    done
    
    echo "$separator"
    
    local header_row="|"
    for i in "${!headers[@]}"; do
        header_row+=" ${headers[$i]}$(printf '%*s' $((max_widths[i] - ${#headers[$i]})) '') |"
    done
    echo "$header_row"
    echo "$separator"
    
    for row in "${data[@]}"; do
        IFS='|' read -ra cols <<< "$row"
        local line="|"
        for i in "${!cols[@]}"; do
            line+=" ${cols[$i]}$(printf '%*s' $((max_widths[i] - ${#cols[$i]})) '') |"
        done
        echo "$line"
    done
    
    echo "$separator"
}

_tui_wait() {
    local msg="${1:-Press any key to continue...}"
    gum confirm "$msg" --default=true && return 0
}

_tui_clear() {
    clear
}

_tui_pager() {
    local content="$1"
    echo "$content" | gum pager
}

_tui_file() {
    local path="${1:-.}"
    
    gum file "$path"
}

_tui_write() {
    local prompt="$1"
    local default="${2:-}"
    
    if [[ -n "$default" ]]; then
        echo -e "$default" | gum write --header="$prompt" --placeholder="Type your text..."
    else
        gum write --header="$prompt" --placeholder="Type your text..."
    fi
}

_tui_init
