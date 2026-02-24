#!/usr/bin/env bash
#
# GLM5 Chad Arch Installer - TUI Framework
# Supports: gum, dialog, or pure bash fallback
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

_tui_init() {
    if command -v gum &>/dev/null && gum --version &>/dev/null; then
        _TUI_BACKEND="gum"
    elif command -v dialog &>/dev/null; then
        _TUI_BACKEND="dialog"
    else
        _TUI_BACKEND="bash"
    fi
    
    [[ -t 1 ]] || _TUI_COLORS_ENABLED=false
}

_tui_detect_backend() {
    echo "$_TUI_BACKEND"
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
    _tui_color cyan "[INFO] $*"
    echo
}

_tui_success() {
    _tui_color green "[OK] $*"
    echo
}

_tui_warn() {
    _tui_color yellow "[WARN] $*"
    echo
}

_tui_error() {
    _tui_color red "[ERROR] $*"
    echo
}

_tui_header() {
    local title="$1"
    local width="${2:-60}"
    local line
    line=$(printf '%*s' "$width" '' | tr ' ' '=')
    
    echo
    _tui_color cyan "$line"
    _tui_color bold "$title"
    echo
    _tui_color cyan "$line"
    echo
}

_tui_section() {
    local title="$1"
    echo
    _tui_color bold "▶ $title"
    echo
}

_tui_menu_select() {
    local prompt="$1"
    shift
    local options=("$@")
    
    local backend="$_TUI_BACKEND"
    
    if [[ ! -t 0 ]] || [[ ! -t 1 ]] || [[ "$NON_INTERACTIVE" == "true" ]]; then
        backend="bash"
    fi
    
    case "$backend" in
        gum)
            if command -v gum &>/dev/null && [[ -t 0 ]] && [[ -t 1 ]]; then
                local result
                result=$(printf '%s\n' "${options[@]}" | gum choose --header="$prompt" --height=20 2>/dev/null)
                local rc=$?
                if [[ $rc -eq 0 ]] && [[ -n "$result" ]]; then
                    echo "$result"
                    return 0
                elif [[ $rc -ne 0 ]]; then
                    return 1
                fi
            fi
            _tui_menu_bash "$prompt" options
            return $?
            ;;
        dialog)
            local cmd=()
            for i in "${!options[@]}"; do
                cmd+=("$i" "${options[$i]}")
            done
            local result
            result=$(dialog --stdout --menu "$prompt" 0 60 0 "${cmd[@]}" 2>/dev/null) || {
                clear
                _tui_menu_bash "$prompt" options
                return $?
            }
            clear
            [[ -n "$result" ]] && echo "${options[$result]}"
            ;;
        bash|*)
            _tui_menu_bash "$prompt" options
            return $?
            ;;
    esac
}

_tui_menu_bash() {
    local prompt="$1"
    local -n opts=$2
    
    echo "$prompt" >&2
    echo >&2
    
    for i in "${!opts[@]}"; do
        echo "  $((i+1)). ${opts[$i]}" >&2
    done
    
    echo >&2
    echo -n "Enter choice number: " >&2
    
    if ! IFS= read -r choice; then
        return 1
    fi
    
    choice=$(echo "$choice" | tr -d '[:space:]')
    
    if [[ -z "$choice" ]]; then
        return 1
    fi
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#opts[@]} ]]; then
        local result="${opts[$((choice-1))]}"
        echo "$result"
        return 0
    else
        return 1
    fi
}

_tui_menu_multi() {
    local prompt="$1"
    shift
    local options=("$@")
    
    local backend="$_TUI_BACKEND"
    
    if [[ ! -t 0 ]] || [[ ! -t 1 ]] || [[ "$NON_INTERACTIVE" == "true" ]]; then
        backend="bash"
    fi
    
    case "$backend" in
        gum)
            if command -v gum &>/dev/null && [[ -t 0 ]] && [[ -t 1 ]]; then
                local result
                result=$(printf '%s\n' "${options[@]}" | gum choose --header="$prompt" --no-limit --height=25 2>/dev/null)
                local rc=$?
                if [[ $rc -eq 0 ]]; then
                    if [[ -n "$result" ]]; then
                        echo "$result"
                    fi
                    return 0
                elif [[ $rc -ne 0 ]]; then
                    return 1
                fi
            fi
            _tui_multiselect_bash "$prompt" options
            return $?
            ;;
        dialog)
            local checklist_args=()
            local i=0
            for opt in "${options[@]}"; do
                checklist_args+=("$i" "$opt" "off")
                ((i++))
            done
            
            local result
            result=$(dialog --stdout --checklist "$prompt" 0 70 0 "${checklist_args[@]}" 2>/dev/null)
            local rc=$?
            clear
            
            if [[ $rc -eq 0 ]] && [[ -n "$result" ]]; then
                for idx in $result; do
                    echo "${options[$idx]}"
                done
                return 0
            fi
            _tui_multiselect_bash "$prompt" options
            return $?
            ;;
        bash|*)
            _tui_multiselect_bash "$prompt" options
            return $?
            ;;
    esac
}

_tui_multiselect_bash() {
    local prompt="$1"
    local -n opts=$2
    local cursor=0
    local key
    local -a toggled_indices=()
    local num_options=${#opts[@]}
    
    if [[ $num_options -eq 0 ]]; then
        return 0
    fi
    
    _tui_multiselect_cleanup() {
        tput rmcup 2>/dev/null || true
        tput cnorm 2>/dev/null || true
    }
    trap _tui_multiselect_cleanup EXIT
    
    tput civis 2>/dev/null || true
    tput smcup 2>/dev/null || true
    
    local term_height
    term_height=$(tput lines 2>/dev/null || echo 24)
    local visible_lines=$((term_height - 8))
    [[ $visible_lines -lt 5 ]] && visible_lines=5
    local scroll_offset=0
    
    while true; do
        tput cup 0 0 2>/dev/null || true
        tput ed 2>/dev/null || true
        
        _tui_color bold "$prompt"
        echo
        _tui_color dim "(Space: toggle | Enter: confirm | a: all | n: none | /: search | q: cancel)"
        echo
        
        local max_display=$((num_options < visible_lines ? num_options : visible_lines))
        
        if [[ $num_options -gt $visible_lines ]]; then
            if [[ $cursor -ge $((scroll_offset + visible_lines)) ]]; then
                scroll_offset=$((cursor - visible_lines + 1))
            elif [[ $cursor -lt $scroll_offset ]]; then
                scroll_offset=$cursor
            fi
            _tui_color dim "Showing $((scroll_offset + 1))-$((scroll_offset + max_display)) of $num_options"
            echo
        fi
        
        for ((i=0; i<max_display; i++)); do
            local actual_idx=$((scroll_offset + i))
            [[ $actual_idx -ge $num_options ]] && break
            
            local is_toggled=false
            for t in "${toggled_indices[@]}"; do
                if [[ "$t" == "$actual_idx" ]]; then
                    is_toggled=true
                    break
                fi
            done
            
            local check="☐"
            $is_toggled && check="☑"
            
            if [[ $actual_idx -eq $cursor ]]; then
                _tui_color green "  → [$check] ${opts[$actual_idx]}"
            else
                echo "    [$check] ${opts[$actual_idx]}"
            fi
        done
        
        echo
        _tui_color dim "[↑/k: up] [↓/j: down] [Space: toggle] [a: all] [n: none] [Enter: confirm] [q: cancel]"
        
        IFS= read -rsn1 key
        
        case "$key" in
            $'\x1b')
                read -rsn2 -t 0.05 k1
                key+="$k1"
                ;;
        esac
        
        case "$key" in
            $'\x1b[A'|k)
                ((cursor > 0)) && ((cursor--))
                ;;
            $'\x1b[B'|j)
                ((cursor < num_options - 1)) && ((cursor++))
                ;;
            ' ')
                local found_idx=-1
                for i in "${!toggled_indices[@]}"; do
                    if [[ "${toggled_indices[$i]}" == "$cursor" ]]; then
                        found_idx=$i
                        break
                    fi
                done
                
                if [[ $found_idx -ge 0 ]]; then
                    unset 'toggled_indices[found_idx]'
                    toggled_indices=("${toggled_indices[@]}")
                else
                    toggled_indices+=("$cursor")
                fi
                ;;
            a|A)
                toggled_indices=()
                for ((i=0; i<num_options; i++)); do
                    toggled_indices+=("$i")
                done
                ;;
            n|N)
                toggled_indices=()
                ;;
            ''|$'\n')
                _tui_multiselect_cleanup
                trap - EXIT
                
                for t in "${toggled_indices[@]}"; do
                    echo "${opts[$t]}"
                done
                return 0
                ;;
            q|Q|$'\x1b')
                _tui_multiselect_cleanup
                trap - EXIT
                return 1
                ;;
            '/')
                tput rmcup 2>/dev/null || true
                tput cnorm 2>/dev/null || true
                echo
                echo -n "Search: "
                local search_term
                read -r search_term
                tput civis 2>/dev/null || true
                tput smcup 2>/dev/null || true
                
                if [[ -n "$search_term" ]]; then
                    for ((i=0; i<num_options; i++)); do
                        if [[ "${opts[$i],,}" == *"${search_term,,}"* ]]; then
                            cursor=$i
                            break
                        fi
                    done
                fi
                ;;
        esac
    done
}

_tui_input() {
    local prompt="$1"
    local default="${2:-}"
    local placeholder="${3:-}"
    
    case "$_TUI_BACKEND" in
        gum)
            if command -v gum &>/dev/null && [[ -t 0 ]] && [[ -t 1 ]]; then
                local result
                result=$(gum input --header="$prompt" --placeholder="$placeholder" --value="$default" 2>/dev/null)
                local rc=$?
                [[ $rc -eq 0 ]] && echo "$result" && return 0
                return 1
            fi
            ;;
    esac
    
    echo -n "$prompt"
    [[ -n "$default" ]] && echo -n " [$default]"
    echo -n ": "
    read -r result
    [[ -z "$result" ]] && result="$default"
    echo "$result"
}

_tui_password() {
    local prompt="$1"
    
    case "$_TUI_BACKEND" in
        gum)
            if command -v gum &>/dev/null && [[ -t 0 ]] && [[ -t 1 ]]; then
                gum input --header="$prompt" --password
                return $?
            fi
            ;;
    esac
    
    read -rs -p "$prompt: " result
    echo
    echo "$result"
}

_tui_confirm() {
    local prompt="$1"
    local default="${2:-n}"
    
    local backend="$_TUI_BACKEND"
    
    if [[ ! -t 0 ]] || [[ ! -t 1 ]]; then
        backend="bash"
    fi
    
    case "$backend" in
        gum)
            local gum_default="no"
            [[ "$default" == "y" ]] && gum_default="yes"
            gum confirm "$prompt" --default="$gum_default" 2>/dev/null && return 0 || return 1
            ;;
        dialog)
            dialog --stdout --yesno "$prompt" 0 0 2>/dev/null
            local rc=$?
            clear
            return $rc
            ;;
        *)
            local yn
            echo -n "$prompt [y/N]: "
            read -r yn
            [[ "$yn" =~ ^[Yy]$ ]]
            ;;
    esac
}

_tui_spinner() {
    local pid=$1
    local msg="${2:-Processing...}"
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    
    tput civis
    
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) % ${#spin} ))
        printf "\r${spin:$i:1} $msg"
        sleep 0.1
    done
    
    tput cnorm
    printf "\r"
}

_tui_progress() {
    local current="$1"
    local total="$2"
    local msg="${3:-}"
    local width="${4:-40}"
    
    local percent=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    printf "\r["
    _tui_color green "$(printf '%*s' "$filled" '' | tr ' ' '█')"
    printf '%*s' "$empty" '' | tr ' ' '░'
    printf "] %3d%% %s" "$percent" "$msg"
}

_tui_table() {
    local -n data=$1
    local headers=("${@:2}")
    
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
        header_row+=" $(_tui_color bold "${headers[$i]}")$(printf '%*s' $((max_widths[$i] - ${#headers[$i]})) '') |"
    done
    echo "$header_row"
    echo "$separator"
    
    for row in "${data[@]}"; do
        IFS='|' read -ra cols <<< "$row"
        local line="|"
        for i in "${!cols[@]}"; do
            line+=" ${cols[$i]}$(printf '%*s' $((max_widths[$i] - ${#cols[$i]})) '') |"
        done
        echo "$line"
    done
    
    echo "$separator"
}

_tui_wait() {
    local msg="${1:-Press any key to continue...}"
    echo
    _tui_color dim "$msg"
    read -rsn1
}

_tui_clear() {
    clear
}

_tui_pager() {
    local content="$1"
    if command -v less &>/dev/null; then
        echo "$content" | less -R
    else
        echo "$content"
    fi
}

_tui_init
