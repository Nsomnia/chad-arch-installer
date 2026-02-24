#!/usr/bin/env bash
#
# GLM5 Chad Arch Installer - Profile Management
#
# Installation profiles for quick setup
#

set -eo pipefail

if [[ -z "${_PROFILE_LOADED:-}" ]]; then
    readonly _PROFILE_LOADED=1
else
    return 0
fi

PROFILE_DIR="${PROFILE_DIR:-${SCRIPT_DIR}/../profiles}"

declare -A PROFILE_DESC=(
    [desktop]="Modern desktop/workstation with Hyprland, CachyOS kernel"
    [server]="Headless server with LTS kernel, minimal packages"
    [legacy]="Optimized for older hardware (2010-2015), AMD legacy support"
    [gaming]="Gaming optimized with low-latency kernel, no mitigations"
    [chromebook]="Chromebook specific with GRUB bootloader"
    [minimal]="Bare minimum installation for custom setup"
)

declare -A PROFILE_KERNELS=(
    [desktop]="linux-cachyos-bore"
    [server]="linux-lts"
    [legacy]="linux-lts"
    [gaming]="linux-cachyos-bore"
    [chromebook]="linux-lts"
    [minimal]="linux"
)

declare -A PROFILE_BOOTLOADERS=(
    [desktop]="limine"
    [server]="systemd-boot"
    [legacy]="grub"
    [gaming]="limine"
    [chromebook]="grub"
    [minimal]="systemd-boot"
)

declare -A PROFILE_DESKTOPS=(
    [desktop]="hyprland"
    [server]="none"
    [legacy]="xfce"
    [gaming]="kde"
    [chromebook]="gnome"
    [minimal]="none"
)

profile_list() {
    _tui_header "Available Installation Profiles"
    
    echo ""
    for name in "${!PROFILE_DESC[@]}"; do
        local kernel="${PROFILE_KERNELS[$name]}"
        local bootloader="${PROFILE_BOOTLOADERS[$name]}"
        local desktop="${PROFILE_DESKTOPS[$name]}"
        [[ "$desktop" == "none" ]] && desktop="none"
        
        printf "  %-15s %s\n" "$name" "${PROFILE_DESC[$name]}"
        printf "                   Kernel: %-20s Bootloader: %s\n" "$kernel" "$bootloader"
        printf "                   Desktop: %s\n\n" "$desktop"
    done
}

profile_exists() {
    local name="$1"
    [[ -f "$PROFILE_DIR/${name}.yaml" ]]
}

profile_get_path() {
    local name="$1"
    echo "$PROFILE_DIR/${name}.yaml"
}

profile_load() {
    local name="$1"
    local profile_file
    
    profile_file=$(profile_get_path "$name")
    
    if [[ ! -f "$profile_file" ]]; then
        log_error "Profile not found: $name"
        return 1
    fi
    
    log_info "Loading profile: $name"
    
    _parse_yaml "$profile_file" "PROFILE_"
}

profile_show() {
    local name="$1"
    local profile_file
    
    profile_file=$(profile_get_path "$name")
    
    if [[ ! -f "$profile_file" ]]; then
        log_error "Profile not found: $name"
        return 1
    fi
    
    _tui_header "Profile: $name"
    cat "$profile_file"
}

profile_apply() {
    local name="$1"
    
    if ! profile_exists "$name"; then
        log_error "Profile not found: $name"
        return 1
    fi
    
    log_info "Applying profile: $name"
    
    profile_load "$name"
    
    config_set "profile.name" "$name"
    config_set "boot.kernel" "${PROFILE_KERNELS[$name]:-linux}"
    config_set "boot.loader" "${PROFILE_BOOTLOADERS[$name]:-systemd-boot}"
    
    local desktop="${PROFILE_DESKTOPS[$name]}"
    if [[ "$desktop" != "none" ]]; then
        config_set "desktop.enabled" "true"
        config_set "desktop.environment" "$desktop"
    else
        config_set "desktop.enabled" "false"
    fi
    
    case "$name" in
        desktop)
            config_set "repos.cachyos" "true"
            config_set "repos.chaotic" "true"
            config_set "storage.luks.enabled" "true"
            config_set "aur.enabled" "true"
            ;;
        server)
            config_set "storage.luks.enabled" "true"
            config_set "storage.use_zram" "true"
            config_set "network.firewall" "true"
            ;;
        legacy)
            config_set "hardware.amd_legacy" "true"
            config_set "kernels.compression" "gzip"
            config_set "optimize.makepkg.lto" "false"
            ;;
        gaming)
            config_set "repos.cachyos" "true"
            config_set "repos.chaotic" "true"
            config_set "boot.kernel_parameters" "mitigations=off nowatchdog"
            config_set "aur.enabled" "true"
            ;;
        chromebook)
            config_set "hardware.chromebook" "true"
            config_set "storage.use_zram" "true"
            config_set "aur.enabled" "true"
            ;;
        minimal)
            : 
            ;;
    esac
    
    log_info "Profile $name applied to configuration"
}

profile_create() {
    local name="$1"
    local output_file="${2:-$PROFILE_DIR/${name}.yaml}"
    
    log_info "Creating profile: $name"
    
    config_save "$output_file"
    
    log_info "Profile saved to: $output_file"
}

profile_wizard() {
    _tui_header "Profile Configuration Wizard"
    
    local profile_name
    profile_name=$(_tui_input "Profile name" "custom")
    
    local hostname
    hostname=$(_tui_input "Hostname" "arch-custom")
    config_set "system.hostname" "$hostname"
    
    local use_cases=(
        "Desktop/Workstation"
        "Server/Headless"
        "Gaming"
        "Development"
        "Minimal/Base"
    )
    local use_case
    use_case=$(_tui_menu_select "Primary use case:" "${use_cases[@]}")
    
    case "$use_case" in
        *"Desktop"*|*"Workstation"*)
            config_set "desktop.enabled" "true"
            local desktops=("hyprland" "kde" "gnome" "sway" "xfce" "i3")
            local desktop
            desktop=$(_tui_menu_select "Desktop environment:" "${desktops[@]}")
            config_set "desktop.environment" "$desktop"
            config_set "repos.cachyos" "true"
            ;;
        *"Server"*|*"Headless"*)
            config_set "desktop.enabled" "false"
            config_set "boot.kernel" "linux-lts"
            config_set "network.firewall" "true"
            ;;
        *"Gaming"*)
            config_set "desktop.enabled" "true"
            config_set "desktop.environment" "kde"
            config_set "repos.cachyos" "true"
            config_set "repos.chaotic" "true"
            config_set "boot.kernel" "linux-cachyos-bore"
            config_set "boot.kernel_parameters" "mitigations=off nowatchdog"
            ;;
        *"Development"*)
            config_set "desktop.enabled" "true"
            config_set "desktop.environment" "hyprland"
            config_set "aur.enabled" "true"
            ;;
        *"Minimal"*)
            config_set "desktop.enabled" "false"
            ;;
    esac
    
    if _tui_confirm "Enable disk encryption?"; then
        config_set "storage.luks.enabled" "true"
    fi
    
    if _tui_confirm "Install optimized kernel (CachyOS)?"; then
        config_set "repos.cachyos" "true"
        local kernels=("linux-cachyos-bore" "linux-cachyos" "linux-zen")
        local kernel
        kernel=$(_tui_menu_select "Select kernel:" "${kernels[@]}")
        config_set "boot.kernel" "$kernel"
    else
        local kernels=("linux" "linux-lts" "linux-hardened" "linux-zen")
        local kernel
        kernel=$(_tui_menu_select "Select kernel:" "${kernels[@]}")
        config_set "boot.kernel" "$kernel"
    fi
    
    local bootloaders=("auto" "limine" "grub" "systemd-boot" "refind")
    local bootloader
    bootloader=$(_tui_menu_select "Select bootloader:" "${bootloaders[@]}")
    config_set "boot.loader" "$bootloader"
    
    profile_create "$profile_name"
    
    _tui_header "Profile Created: $profile_name"
    config_show
}

profile_select() {
    _tui_header "Select Installation Profile"
    
    local options=("custom" "desktop" "server" "legacy" "gaming" "chromebook" "minimal")
    local display_options=()
    
    for opt in "${options[@]}"; do
        if [[ "$opt" == "custom" ]]; then
            display_options+=("Custom (interactive wizard)")
        else
            display_options+=("$opt - ${PROFILE_DESC[$opt]}")
        fi
    done
    
    local choice
    choice=$(_tui_menu_select "Select profile:" "${display_options[@]}")
    
    local profile_name="${choice%% *}"
    [[ "$profile_name" == "Custom" ]] && profile_name="custom"
    
    if [[ "$profile_name" == "custom" ]]; then
        profile_wizard
    else
        profile_show "$profile_name"
        if _tui_confirm "Apply this profile?"; then
            profile_apply "$profile_name"
        fi
    fi
    
    echo "$profile_name"
}

profile_menu() {
    _tui_header "Profile Management"
    
    local options=(
        "List Available Profiles"
        "Show Profile Details"
        "Apply Profile"
        "Create Custom Profile"
        "Show Current Configuration"
        "Back"
    )
    
    while true; do
        local choice
        choice=$(_tui_menu_select "Profile Options:" "${options[@]}")
        
        case "$choice" in
            *"List"*)
                profile_list
                ;;
            *"Show Profile"*)
                local profiles=("desktop" "server" "legacy" "gaming" "chromebook" "minimal")
                local profile
                profile=$(_tui_menu_select "Select profile:" "${profiles[@]}")
                profile_show "$profile"
                ;;
            *"Apply"*)
                profile_select
                ;;
            *"Create"*)
                profile_wizard
                ;;
            *"Current"*)
                config_show
                ;;
            *"Back"*)
                return 0
                ;;
        esac
        
        _tui_wait
    done
}
