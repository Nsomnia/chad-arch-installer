#!/usr/bin/env bash
#
# GLM5 Chad Arch Installer - Configuration System
#

set -eo pipefail

if [[ -z "${_CONFIG_LOADED:-}" ]]; then
    readonly _CONFIG_LOADED=1
else
    return 0
fi

CONFIG_FILE="${CONFIG_FILE:-}"
CONFIG_DIR="${CONFIG_DIR:-${SCRIPT_DIR}/../config}"
DEFAULT_CONFIG="$CONFIG_DIR/defaults.yaml"
USER_CONFIG="${USER_CONFIG:-/etc/chad-installer/config.yaml}"

declare -A CONFIG=()
declare -a CONFIG_ERRORS=()

_parse_yaml() {
    local yaml_file="$1"
    local prefix="${2:-}"
    local current_key=""
    local indent_level=0
    
    if [[ ! -f "$yaml_file" ]]; then
        log_error "Config file not found: $yaml_file"
        return 1
    fi
    
    if command -v yq &>/dev/null; then
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                local key="${line%%=*}"
                local value="${line#*=}"
                key="${prefix}${key}"
                key="${key//./_}"
                CONFIG["$key"]="$value"
            fi
        done < <(yq -r 'paths(scalars) as $p | $p | join("_") + "=" + getpath($p)' "$yaml_file" 2>/dev/null)
    else
        while IFS= read -r line; do
            [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
            
            local indent=${line%%[^[:space:]]*}
            indent=${#indent}
            
            if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*:[[:space:]]*(.*) ]]; then
                local key="${BASH_REMATCH[1]}"
                local value="${BASH_REMATCH[2]}"
                
                if [[ $indent -eq 0 ]]; then
                    current_key="${key}"
                    indent_level=0
                elif [[ $indent -eq 2 ]] && [[ $indent_level -le 0 ]]; then
                    current_key="${key}"
                    indent_level=1
                elif [[ $indent -eq 4 ]] && [[ $indent_level -le 1 ]]; then
                    key="${current_key}_${key}"
                    indent_level=2
                else
                    continue
                fi
                
                value="${value#\"}"
                value="${value%\"}"
                value="${value#\'}"
                value="${value%\'}"
                value="${value%%#*}"
                value="${value%"${value##*[![:space]]}"}"
                
                if [[ -n "$value" ]]; then
                    CONFIG["$key"]="$value"
                fi
            fi
        done < "$yaml_file"
    fi
}

config_load() {
    local files=()
    
    [[ -f "$DEFAULT_CONFIG" ]] && files+=("$DEFAULT_CONFIG")
    [[ -f "$USER_CONFIG" ]] && files+=("$USER_CONFIG")
    [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]] && files+=("$CONFIG_FILE")
    
    if [[ ${#files[@]} -eq 0 ]]; then
        log_warn "No configuration files found, using built-in defaults"
        _config_set_defaults
        return 0
    fi
    
    for f in "${files[@]}"; do
        log_debug "Loading config from: $f"
        _parse_yaml "$f"
    done
    
    _config_validate
}

_config_set_defaults() {
    CONFIG[system_hostname]="arch-chad"
    CONFIG[system_timezone]="UTC"
    CONFIG[system_locale]="en_US.UTF-8"
    CONFIG[system_keymap]="us"
    CONFIG[system_cpu_vendor]="auto"
    
    CONFIG[storage_efi_size_mb]="1024"
    CONFIG[storage_luks_enabled]="false"
    CONFIG[storage_luks_cipher]="aes-xts-plain64"
    CONFIG[storage_luks_key_size]="512"
    CONFIG[storage_btrfs_compress]="zstd:3"
    CONFIG[storage_btrfs_label]="ARCH"
    
    CONFIG[boot_kernel]="linux"
    CONFIG[boot_kernel_fallback]="linux-lts"
    CONFIG[boot_loader]="systemd-boot"
    CONFIG[boot_secure_boot]="false"
    
    CONFIG[snapper_enabled]="true"
    CONFIG[snapper_hourly]="10"
    CONFIG[snapper_daily]="7"
    CONFIG[snapper_weekly]="4"
    CONFIG[snapper_monthly]="6"
    CONFIG[snapper_yearly]="2"
    
    CONFIG[repos_cachyos]="false"
    CONFIG[repos_cachyos_v3]="false"
    CONFIG[repos_cachyos_v4]="false"
    CONFIG[repos_chaotic]="false"
    
    CONFIG[optimize_makepkg_parallel]="auto"
    CONFIG[optimize_makepkg_compiler_flags]="auto"
    CONFIG[optimize_makepkg_lto]="true"
    
    CONFIG[desktop_enabled]="false"
    CONFIG[desktop_environment]="hyprland"
}

config_get() {
    local key="$1"
    local default="${2:-}"
    
    key="${key//./_}"
    
    if [[ -v "CONFIG[$key]" ]]; then
        echo "${CONFIG[$key]}"
    else
        echo "$default"
    fi
}

config_set() {
    local key="$1"
    local value="$2"
    
    key="${key//./_}"
    CONFIG["$key"]="$value"
    log_debug "Config set: $key = $value"
}

config_get_array() {
    local key="$1"
    local value
    
    value=$(config_get "$key" "")
    
    if [[ -z "$value" ]]; then
        return 0
    fi
    
    echo "$value" | tr ',' ' ' | tr -s ' '
}

config_get_bool() {
    local key="$1"
    local default="${2:-false}"
    
    local value
    value=$(config_get "$key" "$default")
    
    case "${value,,}" in
        true|yes|1|on|enabled) return 0 ;;
        false|no|0|off|disabled) return 1 ;;
        *) return 1 ;;
    esac
}

config_get_int() {
    local key="$1"
    local default="${2:-0}"
    
    local value
    value=$(config_get "$key" "$default")
    
    echo "$((value))"
}

_config_validate() {
    CONFIG_ERRORS=()
    
    local hostname
    hostname=$(config_get "system_hostname" "")
    if [[ ! "$hostname" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; then
        CONFIG_ERRORS+=("Invalid hostname: $hostname")
    fi
    
    local timezone
    timezone=$(config_get "system_timezone" "UTC")
    if [[ ! -f "/usr/share/zoneinfo/$timezone" ]]; then
        if [[ "$MOCK_MODE" != "true" ]]; then
            CONFIG_ERRORS+=("Invalid timezone: $timezone")
        fi
    fi
    
    local kernel
    kernel=$(config_get "boot_kernel" "linux")
    case "$kernel" in
        linux|linux-lts|linux-hardened|linux-zen|linux-cachyos|linux-cachyos-bore)
            : ;;
        *)
            CONFIG_ERRORS+=("Invalid kernel: $kernel")
            ;;
    esac
    
    local loader
    loader=$(config_get "boot_loader" "systemd-boot")
    case "$loader" in
        systemd-boot|grub|refind|limine)
            : ;;
        *)
            CONFIG_ERRORS+=("Invalid bootloader: $loader")
            ;;
    esac
    
    local compression
    compression=$(config_get "storage_btrfs_compress" "zstd:3")
    case "$compression" in
        zstd|zstd:*|lzo|lz4|no|none)
            : ;;
        *)
            CONFIG_ERRORS+=("Invalid BTRFS compression: $compression")
            ;;
    esac
    
    if [[ ${#CONFIG_ERRORS[@]} -gt 0 ]]; then
        log_error "Configuration validation failed:"
        for err in "${CONFIG_ERRORS[@]}"; do
            log_error "  - $err"
        done
        return 1
    fi
    
    log_info "Configuration validated successfully"
    return 0
}

config_show() {
    _tui_header "Current Configuration"
    
    _tui_section "System"
    echo "  Hostname:    $(config_get "system_hostname")"
    echo "  Timezone:    $(config_get "system_timezone")"
    echo "  Locale:      $(config_get "system_locale")"
    echo "  Keymap:      $(config_get "system_keymap")"
    echo "  CPU Vendor:  $(config_get "system_cpu_vendor")"
    
    _tui_section "Storage"
    echo "  EFI Size:    $(config_get "storage_efi_size_mb") MB"
    echo "  LUKS:        $(config_get "storage.luks.enabled")"
    echo "  BTRFS Label: $(config_get "storage.btrfs.label")"
    echo "  Compression: $(config_get "storage.btrfs.compress")"
    
    _tui_section "Boot"
    echo "  Kernel:      $(config_get "boot_kernel")"
    echo "  Bootloader:  $(config_get "boot_loader")"
    echo "  Secure Boot: $(config_get "boot_secure_boot")"
    
    _tui_section "Snapper"
    echo "  Enabled:     $(config_get "snapper_enabled")"
    echo "  Hourly:      $(config_get "snapper_hourly")"
    echo "  Daily:       $(config_get "snapper_daily")"
    
    _tui_section "Repositories"
    echo "  CachyOS:     $(config_get "repos_cachyos")"
    echo "  CachyOS v3:  $(config_get "repos_cachyos_v3")"
    echo "  CachyOS v4:  $(config_get "repos_cachyos_v4")"
    echo "  Chaotic-AUR: $(config_get "repos_chaotic")"
}

config_wizard() {
    _tui_header "Configuration Wizard"
    
    local hostname
    hostname=$(_tui_input "Hostname" "$(config_get "system_hostname")")
    config_set "system.hostname" "$hostname"
    
    local timezone
    timezone=$(_tui_input "Timezone" "$(config_get "system_timezone")")
    config_set "system.timezone" "$timezone"
    
    local kernels=("linux" "linux-lts" "linux-hardened" "linux-zen" "linux-cachyos")
    local kernel
    kernel=$(_tui_menu_select "Select Kernel" "${kernels[@]}")
    config_set "boot.kernel" "$kernel"
    
    local bootloaders=("systemd-boot" "grub" "refind")
    local bootloader
    bootloader=$(_tui_menu_select "Select Bootloader" "${bootloaders[@]}")
    config_set "boot.loader" "$bootloader"
    
    local compressions=("zstd:3" "zstd:6" "zstd:10" "lzo" "lz4" "none")
    local compression
    compression=$(_tui_menu_select "BTRFS Compression" "${compressions[@]}")
    config_set "storage.btrfs.compress" "$compression"
    
    if _tui_confirm "Enable LUKS encryption?"; then
        config_set "storage.luks.enabled" "true"
    else
        config_set "storage.luks.enabled" "false"
    fi
    
    if _tui_confirm "Enable Snapper snapshots?"; then
        config_set "snapper.enabled" "true"
    else
        config_set "snapper.enabled" "false"
    fi
    
    local repos=("cachyos" "cachyos_v3" "cachyos_v4" "chaotic-aur" "archlinuxcn")
    _tui_header "Select Additional Repositories"
    local selected_repos
    mapfile -t selected_repos < <(_tui_menu_multi "Select repositories to enable (Space to toggle):" "${repos[@]}")
    
    for r in "${repos[@]}"; do
        config_set "repos.$r" "false"
    done
    
    for r in "${selected_repos[@]}"; do
        config_set "repos.${r//-/_}" "true"
    done
    
    if _tui_confirm "Install desktop environment?"; then
        config_set "desktop.enabled" "true"
        local desktops=("hyprland" "kde" "gnome" "sway" "xfce" "i3")
        local de
        de=$(_tui_menu_select "Select Desktop Environment" "${desktops[@]}")
        config_set "desktop.environment" "$de"
    else
        config_set "desktop.enabled" "false"
    fi
    
    _tui_header "Configuration Complete"
    config_show
}

config_save() {
    local output_file="${1:-$USER_CONFIG}"
    
    mkdir -p "$(dirname "$output_file")"
    
    {
        echo "# GLM5 Chad Arch Installer Configuration"
        echo "# Generated: $(date)"
        echo ""
        
        echo "system:"
        echo "  hostname: $(config_get "system_hostname")"
        echo "  timezone: $(config_get "system_timezone")"
        echo "  locale: $(config_get "system_locale")"
        echo "  keymap: $(config_get "system_keymap")"
        echo "  cpu_vendor: $(config_get "system_cpu_vendor")"
        echo ""
        
        echo "storage:"
        echo "  efi_size_mb: $(config_get "storage_efi_size_mb")"
        echo "  luks:"
        echo "    enabled: $(config_get "storage.luks.enabled")"
        echo "    cipher: $(config_get "storage.luks.cipher")"
        echo "    key_size: $(config_get "storage.luks.key_size")"
        echo "  btrfs:"
        echo "    compress: $(config_get "storage.btrfs.compress")"
        echo "    label: $(config_get "storage.btrfs.label")"
        echo ""
        
        echo "boot:"
        echo "  kernel: $(config_get "boot_kernel")"
        echo "  loader: $(config_get "boot_loader")"
        echo "  secure_boot: $(config_get "boot_secure_boot")"
        echo ""
        
        echo "snapper:"
        echo "  enabled: $(config_get "snapper_enabled")"
        echo "  hourly: $(config_get "snapper_hourly")"
        echo "  daily: $(config_get "snapper_daily")"
        echo "  weekly: $(config_get "snapper_weekly")"
        echo "  monthly: $(config_get "snapper_monthly")"
        echo "  yearly: $(config_get "snapper_yearly")"
        echo ""
        
        echo "repos:"
        echo "  cachyos: $(config_get "repos_cachyos")"
        echo "  cachyos_v3: $(config_get "repos_cachyos_v3")"
        echo "  cachyos_v4: $(config_get "repos_cachyos_v4")"
        echo "  chaotic: $(config_get "repos_chaotic")"
        echo ""
        
        echo "desktop:"
        echo "  enabled: $(config_get "desktop_enabled")"
        echo "  environment: $(config_get "desktop_environment")"
    } > "$output_file"
    
    log_info "Configuration saved to: $output_file"
}
