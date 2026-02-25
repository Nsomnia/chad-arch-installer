#!/usr/bin/env bash
#
# GLM5 Chad Arch Installer - Mock/Test Mode Infrastructure
#

set -eo pipefail

if [[ -z "${_MOCK_LOADED:-}" ]]; then
    readonly _MOCK_LOADED=1
else
    return 0
fi

MOCK_MODE="${MOCK_MODE:-false}"
MOCK_LOG="${MOCK_LOG:-/tmp/chad-installer-mock.log}"
MOCK_ROOT="${MOCK_ROOT:-/tmp/chad-installer-mock-root}"
MOCK_TIME_MULTIPLIER="${MOCK_TIME_MULTIPLIER:-0.1}"

declare -a MOCK_COMMANDS=()
declare -a MOCK_FILES=()

mock_init() {
    if [[ "$MOCK_MODE" != "true" ]]; then
        return 0
    fi
    
    mkdir -p "$MOCK_ROOT"
    echo "=== Mock Session Started: $(date) ===" > "$MOCK_LOG"
    
    MOCK_FILES=(
        "/etc/fstab"
        "/etc/crypttab"
        "/etc/default/grub"
        "/etc/mkinitcpio.conf"
        "/etc/snapper/configs/root"
        "/etc/pacman.conf"
        "/etc/pacman.d/mirrorlist"
    )
    
    for f in "${MOCK_FILES[@]}"; do
        local mock_path="$MOCK_ROOT$f"
        mkdir -p "$(dirname "$mock_path")"
        touch "$mock_path"
    done
    MOCK_FILE_CONTENTS=()
}

mock_log_cmd() {
    if [[ "$MOCK_MODE" != "true" ]]; then
        return 1
    fi
    
    local description="$1"
    shift
    local cmd=("$@")
    
    echo "[MOCK] $description" >> "$MOCK_LOG"
    echo "  Command: ${cmd[*]}" >> "$MOCK_LOG"
    echo "  Time: $(date)" >> "$MOCK_LOG"
    echo "" >> "$MOCK_LOG"
}

mock_cmd() {
    local description="$1"
    shift
    local cmd=("$@")
    
    if [[ "$MOCK_MODE" == "true" ]]; then
        mock_log_cmd "$description" "${cmd[@]}"
        
        case "${cmd[0]}" in
            pacstrap)
                echo "[MOCK] Would run pacstrap with: ${cmd[*]:1}"
                echo "PACKAGES_INSTALLED: ${cmd[*]:2}" >> "$MOCK_LOG"
                return 0
                ;;
            mount|umount)
                echo "[MOCK] Would ${cmd[0]}: ${cmd[*]:1}"
                return 0
                ;;
            mkfs.*|btrfs)
                echo "[MOCK] Would create filesystem: ${cmd[*]}"
                return 0
                ;;
            sgdisk|parted|fdisk)
                echo "[MOCK] Would partition: ${cmd[*]}"
                return 0
                ;;
            cryptsetup)
                echo "[MOCK] Would setup LUKS: ${cmd[*]}"
                return 0
                ;;
            grub-install|bootctl)
                echo "[MOCK] Would install bootloader: ${cmd[*]}"
                return 0
                ;;
            systemctl)
                echo "[MOCK] Would systemctl: ${cmd[*]}"
                return 0
                ;;
            pacman)
                echo "[MOCK] Would pacman: ${cmd[*]}"
                return 0
                ;;
            useradd|usermod|passwd)
                echo "[MOCK] Would modify user: ${cmd[*]}"
                return 0
                ;;
            chroot)
                echo "[MOCK] Would chroot: ${cmd[*]}"
                return 0
                ;;
            *)
                echo "[MOCK] Command: ${cmd[*]}"
                return 0
                ;;
        esac
    else
        "${cmd[@]}"
    fi
}

mock_write_file() {
    local path="$1"
    local content="$2"
    
    if [[ "$MOCK_MODE" == "true" ]]; then
        echo "[MOCK] Writing to $path:" >> "$MOCK_LOG"
        echo "$content" >> "$MOCK_LOG"
        echo "---" >> "$MOCK_LOG"
        
        local mock_path="$MOCK_ROOT$path"
        mkdir -p "$(dirname "$mock_path")"
        echo "$content" > "$mock_path"
    else
        echo "$content" > "$path"
    fi
}

mock_append_file() {
    local path="$1"
    local content="$2"
    
    if [[ "$MOCK_MODE" == "true" ]]; then
        echo "[MOCK] Appending to $path:" >> "$MOCK_LOG"
        echo "$content" >> "$MOCK_LOG"
        echo "---" >> "$MOCK_LOG"
        
        local mock_path="$MOCK_ROOT$path"
        mkdir -p "$(dirname "$mock_path")"
        echo "$content" >> "$mock_path"
    else
        echo "$content" >> "$path"
    fi
}

mock_read_file() {
    local path="$1"
    
    if [[ "$MOCK_MODE" == "true" ]]; then
        cat "$MOCK_ROOT$path" 2>/dev/null || cat "$path" 2>/dev/null || echo ""
    else
        cat "$path"
    fi
}

mock_exists() {
    local path="$1"
    
    if [[ "$MOCK_MODE" == "true" ]]; then
        [[ -f "$MOCK_ROOT$path" ]] || [[ -f "$path" ]]
    else
        [[ -f "$path" ]]
    fi
}

mock_sleep() {
    local seconds="$1"
    
    if [[ "$MOCK_MODE" == "true" ]]; then
        local mock_seconds
        if command -v bc &>/dev/null; then
            mock_seconds=$(echo "$seconds * $MOCK_TIME_MULTIPLIER" | bc -l 2>/dev/null || echo "0.1")
        else
            mock_seconds="0.1"
        fi
        echo "[MOCK] Simulating ${seconds}s sleep (${mock_seconds}s real)"
        sleep "$mock_seconds"
    else
        sleep "$seconds"
    fi
}

mock_progress() {
    local msg="$1"
    local duration="${2:-2}"
    
    if [[ "$MOCK_MODE" == "true" ]]; then
        echo "[MOCK PROGRESS] $msg"
        mock_sleep "$duration"
    else
        local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
        local i=0
        local iterations=$((duration * 10))
        
        for ((j=0; j<iterations; j++)); do
            i=$(( (i+1) % ${#spin} ))
            printf "\r${spin:$i:1} $msg"
            sleep 0.1
        done
        printf "\r✓ $msg\n"
    fi
}

mock_summary() {
    if [[ "$MOCK_MODE" != "true" ]]; then
        return 0
    fi
    
    echo ""
    echo "=== Mock Session Summary ==="
    echo "Log file: $MOCK_LOG"
    echo "Mock root: $MOCK_ROOT"
    echo ""
    echo "Commands executed (simulated):"
    grep -c "\[MOCK\]" "$MOCK_LOG" 2>/dev/null || echo "0"
    echo ""
    echo "Files created/modified:"
    find "$MOCK_ROOT" -type f 2>/dev/null | wc -l
    echo ""
    echo "Review $MOCK_LOG for full simulation details"
}

mock_validate() {
    local errors=0
    
    if [[ "$MOCK_MODE" != "true" ]]; then
        return 0
    fi
    
    echo "Validating mock operations..."
    
    if grep -q "Would partition" "$MOCK_LOG"; then
        echo "✓ Partition operations simulated"
    else
        echo "⚠ No partition operations found"
        ((errors++))
    fi
    
    if grep -q "Would create filesystem" "$MOCK_LOG"; then
        echo "✓ Filesystem operations simulated"
    else
        echo "⚠ No filesystem operations found"
        ((errors++))
    fi
    
    if grep -q "Would run pacstrap" "$MOCK_LOG"; then
        echo "✓ Package installation simulated"
    else
        echo "⚠ No pacstrap operations found"
        ((errors++))
    fi
    
    return $errors
}

mock_cleanup() {
    if [[ "$MOCK_MODE" != "true" ]]; then
        return 0
    fi
    
    if _tui_confirm "Clean up mock directory ($MOCK_ROOT)?"; then
        rm -rf "$MOCK_ROOT"
        echo "Mock directory cleaned"
    fi
}
