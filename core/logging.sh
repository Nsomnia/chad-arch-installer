#!/usr/bin/env bash
#
# GLM5 Chad Arch Installer - Logging Infrastructure
#

set -eo pipefail

if [[ -z "${_LOGGING_LOADED:-}" ]]; then
    readonly _LOGGING_LOADED=1
else
    return 0
fi

LOG_DIR="${LOG_DIR:-/var/log/chad-installer}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/install.log}"
LOG_LEVEL="${LOG_LEVEL:-DEBUG}"
LOG_TO_FILE="${LOG_TO_FILE:-true}"
LOG_TO_SYSLOG="${LOG_TO_SYSLOG:-false}"

declare -A LOG_LEVELS=(
    [DEBUG]=0
    [INFO]=1
    [WARN]=2
    [ERROR]=3
    [FATAL]=4
)

_log_init() {
    mkdir -p "$LOG_DIR"
    
    if [[ ! -f "$LOG_FILE" ]]; then
        touch "$LOG_FILE"
        chmod 600 "$LOG_FILE"
    fi
    
    _log_rotate
}

_log_rotate() {
    local max_logs=5
    local count
    
    count=$(find "$LOG_DIR" -name "*.log.*" 2>/dev/null | wc -l)
    
    if [[ $count -ge $max_logs ]]; then
        ls -t "$LOG_DIR"/*.log.* 2>/dev/null | tail -n +$max_logs | xargs rm -f 2>/dev/null || true
    fi
    
    if [[ -f "$LOG_FILE" ]]; then
        local size
        size=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
        
        if [[ $size -gt 10485760 ]]; then
            mv "$LOG_FILE" "$LOG_FILE.$(date +%Y%m%d_%H%M%S)"
            touch "$LOG_FILE"
        fi
    fi
}

_log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    local level_num=1
    local current_level_num=1
    
    case "$level" in
        DEBUG) level_num=0 ;;
        INFO)  level_num=1 ;;
        WARN)  level_num=2 ;;
        ERROR) level_num=3 ;;
        FATAL) level_num=4 ;;
        *)     level_num=1 ;;
    esac
    
    case "$LOG_LEVEL" in
        DEBUG) current_level_num=0 ;;
        INFO)  current_level_num=1 ;;
        WARN)  current_level_num=2 ;;
        ERROR) current_level_num=3 ;;
        FATAL) current_level_num=4 ;;
        *)     current_level_num=1 ;;
    esac
    
    if [[ $level_num -lt $current_level_num ]]; then
        return 0
    fi
    
    local log_line="[$timestamp] [$level] $msg"
    
    if $LOG_TO_FILE; then
        if [[ -d "$(dirname "$LOG_FILE")" ]] && touch "$LOG_FILE" &>/dev/null; then
            echo "$log_line" >> "$LOG_FILE" 2>/dev/null || true
        fi
    fi
    
    if $LOG_TO_SYSLOG && command -v logger &>/dev/null; then
        logger -t "chad-installer" "[$level] $msg"
    fi
    
    case "$level" in
        DEBUG) echo -e "\033[2m$log_line\033[0m" ;;
        INFO)  echo -e "\033[34m$log_line\033[0m" ;;
        WARN)  echo -e "\033[33m$log_line\033[0m" >&2 ;;
        ERROR) echo -e "\033[31m$log_line\033[0m" >&2 ;;
        FATAL) echo -e "\033[31;1m$log_line\033[0m" >&2 ;;
    esac
}

log_debug() { _log DEBUG "$@"; }
log_info()  { _log INFO "$@"; }
log_warn()  { _log WARN "$@"; }
log_error() { _log ERROR "$@"; }
log_fatal() { _log FATAL "$@"; exit 1; }

_log_cmd() {
    local description="$1"
    shift
    local cmd=("$@")
    
    log_debug "Executing: ${cmd[*]}"
    log_debug "Description: $description"
    
    local start_time
    start_time=$(date +%s)
    
    if "${cmd[@]}" 2>&1 | tee -a "$LOG_FILE"; then
        local end_time
        end_time=$(date +%s)
        log_debug "Command completed in $((end_time - start_time))s"
        return 0
    else
        local rc=$?
        log_error "Command failed with exit code $rc: ${cmd[*]}"
        return $rc
    fi
}

_log_section() {
    local title="$1"
    local line
    line=$(printf '%*s' 60 '' | tr ' ' '=')
    
    log_info ""
    log_info "$line"
    log_info "= $title"
    log_info "$line"
}

_log_step() {
    local step_num="$1"
    local total="$2"
    local desc="$3"
    
    log_info "[$step_num/$total] $desc"
}

_log_var() {
    local name="$1"
    local value="${!name}"
    log_debug "$name = '$value'"
}

_log_array() {
    local name="$1"
    local -n arr=$name
    log_debug "$name = (${arr[*]})"
}

_log_stack() {
    local frame=0
    log_debug "Stack trace:"
    while caller $frame; do
        ((frame++))
    done | while read -r line func file; do
        log_debug "  $file:$line $func()"
    done
}

_log_summary() {
    local total_errors="$1"
    local total_warnings="$2"
    local duration="$3"
    
    _log_section "Installation Summary"
    
    log_info "Duration: $duration"
    log_info "Errors: $total_errors"
    log_info "Warnings: $total_warnings"
    
    if [[ $total_errors -gt 0 ]]; then
        log_error "Installation completed WITH ERRORS"
        return 1
    elif [[ $total_warnings -gt 0 ]]; then
        log_warn "Installation completed with warnings"
        return 0
    else
        log_info "Installation completed successfully"
        return 0
    fi
}

if [[ ! -d "$LOG_DIR" ]]; then
    mkdir -p "$LOG_DIR" 2>/dev/null || LOG_TO_FILE=false
fi

if [[ -z "${_LOG_INITIALIZED:-}" ]]; then
    _log_init
    readonly _LOG_INITIALIZED=1
fi
