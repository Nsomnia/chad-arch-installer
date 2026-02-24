#!/usr/bin/env bash
#
# GLM5 Chad Arch Installer - Hardware Detection Module
#

set -eo pipefail

if [[ -z "${_HARDWARE_LOADED:-}" ]]; then
    readonly _HARDWARE_LOADED=1
else
    return 0
fi

hardware_detect_gpu() {
    _log_section "Detecting GPU"
    
    local gpus=()
    local gpu_info=""
    
    if command -v lspci &>/dev/null; then
        while IFS= read -r line; do
            if [[ "$line" =~ VGA|3D|Display ]]; then
                gpus+=("$line")
            fi
        done < <(lspci 2>/dev/null)
    fi
    
    if [[ ${#gpus[@]} -eq 0 ]]; then
        log_warn "No GPU detected via lspci"
        return 1
    fi
    
    for gpu in "${gpus[@]}"; do
        local vendor driver
        
        if [[ "$gpu" =~ [Nn][Vv][Ii][Dd][Ii][Aa] ]]; then
            vendor="nvidia"
            driver="nvidia"
        elif [[ "$gpu" =~ [Aa][Mm][Dd] ]] || [[ "$gpu" =~ [Aa][Tt][Ii] ]]; then
            vendor="amd"
            driver="amdgpu"
        elif [[ "$gpu" =~ [Ii][Nn][Tt][Ee][Ll] ]]; then
            vendor="intel"
            driver="i915"
        else
            vendor="unknown"
            driver="unknown"
        fi
        
        gpu_info+="vendor=$vendor|driver=$driver|device=$gpu"$'\n'
    done
    
    echo "$gpu_info"
}

hardware_detect_touchscreen() {
    _log_section "Detecting Touchscreen"
    
    local touchscreens=()
    
    if command -v xinput &>/dev/null; then
        while IFS= read -r line; do
            if [[ "$line" =~ [Tt][Oo][Uu][Cc][Hh] ]]; then
                touchscreens+=("$line")
            fi
        done < <(xinput list 2>/dev/null || true)
    fi
    
    if [[ -d /sys/class/input ]]; then
        for device in /sys/class/input/input*/device; do
            if [[ -f "$device/name" ]]; then
                local name
                name=$(cat "$device/name" 2>/dev/null)
                if [[ "$name" =~ [Tt][Oo][Uu][Cc][Hh] ]]; then
                    touchscreens+=("$name")
                fi
            fi
        done
    fi
    
    if [[ ${#touchscreens[@]} -gt 0 ]]; then
        log_info "Touchscreen detected: ${touchscreens[*]}"
        return 0
    else
        log_info "No touchscreen detected"
        return 1
    fi
}

hardware_detect_wifi() {
    _log_section "Detecting WiFi Adapter"
    
    local wifi_adapters=()
    
    if command -v ip &>/dev/null; then
        while IFS= read -r line; do
            if [[ "$line" =~ wl ]]; then
                local iface
                iface=$(echo "$line" | awk '{print $2}')
                wifi_adapters+=("$iface")
            fi
        done < <(ip link show 2>/dev/null)
    fi
    
    if [[ -d /sys/class/net ]]; then
        for iface in /sys/class/net/wl*; do
            [[ -e "$iface" ]] && wifi_adapters+=("$(basename "$iface")")
        done
    fi
    
    if [[ ${#wifi_adapters[@]} -gt 0 ]]; then
        log_info "WiFi adapters: ${wifi_adapters[*]}"
        return 0
    else
        log_info "No WiFi adapter detected"
        return 1
    fi
}

hardware_detect_bluetooth() {
    _log_section "Detecting Bluetooth"
    
    if command -v bluetoothctl &>/dev/null; then
        if bluetoothctl list 2>/dev/null | grep -q "Controller"; then
            log_info "Bluetooth adapter detected"
            return 0
        fi
    fi
    
    if [[ -d /sys/class/bluetooth ]]; then
        log_info "Bluetooth adapter detected via sysfs"
        return 0
    fi
    
    log_info "No Bluetooth adapter detected"
    return 1
}

hardware_detect_audio() {
    _log_section "Detecting Audio Hardware"
    
    local audio_devices=()
    
    if [[ -d /proc/asound ]]; then
        for card in /proc/asound/card*; do
            if [[ -f "$card/codec#0" ]]; then
                local codec
                codec=$(head -1 "$card/codec#0" 2>/dev/null)
                audio_devices+=("$codec")
            fi
        done
    fi
    
    if command -v aplay &>/dev/null; then
        while IFS= read -r line; do
            audio_devices+=("$line")
        done < <(aplay -l 2>/dev/null | grep "^card")
    fi
    
    if [[ ${#audio_devices[@]} -gt 0 ]]; then
        log_info "Audio devices detected"
        return 0
    else
        log_info "No audio devices detected"
        return 1
    fi
}

hardware_detect_legacy() {
    _log_section "Detecting Legacy Hardware"
    
    local legacy_info=()
    
    if grep -q "i686" /proc/cpuinfo 2>/dev/null; then
        legacy_info+=("32-bit CPU detected")
    fi
    
    local cpu_model
    cpu_model=$(grep -m1 "^model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2)
    
    if echo "$cpu_model" | grep -qiE "Pentium|Core 2|Core Duo|Athlon 64|Phenom"; then
        legacy_info+=("Legacy CPU: $cpu_model")
    fi
    
    if command -v lspci &>/dev/null; then
        if lspci 2>/dev/null | grep -qiE "Radeon.*R300|Radeon.*R400|Radeon.*R500|Radeon.*HD [23]"; then
            legacy_info+=("Legacy GPU detected - may require MESA_LOADER_DRIVER_OVERRIDE")
        fi
    fi
    
    if [[ -d /sys/class/dmi/id ]]; then
        local product_name
        product_name=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "Unknown")
        local board_vendor
        board_vendor=$(cat /sys/class/dmi/id/board_vendor 2>/dev/null || echo "Unknown")
        
        if echo "$product_name" | grep -qiE "Latitude|[Ll]atitude|Precision|OptiPlex"; then
            legacy_info+=("Dell system detected: $product_name")
        fi
    fi
    
    if [[ ${#legacy_info[@]} -gt 0 ]]; then
        log_info "Legacy hardware detected:"
        for info in "${legacy_info[@]}"; do
            log_info "  - $info"
        done
        return 0
    else
        log_info "No legacy hardware detected"
        return 1
    fi
}

hardware_get_gpu_packages() {
    local vendor="$1"
    local packages=()
    
    case "$vendor" in
        nvidia)
            packages=(
                "nvidia-dkms"
                "nvidia-utils"
                "lib32-nvidia-utils"
                "nvidia-settings"
                "libva-nvidia-driver"
            )
            ;;
        amd)
            packages=(
                "mesa"
                "vulkan-radeon"
                "libva-mesa-driver"
                "lib32-mesa"
                "lib32-vulkan-radeon"
                "xf86-video-amdgpu"
            )
            ;;
        intel)
            packages=(
                "mesa"
                "vulkan-intel"
                "intel-media-driver"
                "libva-intel-driver"
            )
            ;;
    esac
    
    printf '%s\n' "${packages[@]}"
}

hardware_configure_nvidia() {
    local mount_point="${1:-}"
    
    _log_section "Configuring NVIDIA Drivers"
    
    local modprobe_file="/etc/modprobe.d/nvidia.conf"
    [[ -n "$mount_point" ]] && modprobe_file="$mount_point$modprobe_file"
    
    local nvidia_conf="# NVIDIA kernel module options
options nvidia NVreg_PreserveVideoMemoryAllocations=1
options nvidia NVreg_TemporaryFilePath=/var/tmp
options nvidia-drm modeset=1
"
    
    mock_write_file "$modprobe_file" "$nvidia_conf"
    
    log_info "NVIDIA driver configuration written"
    
    log_info "Enabling nvidia-suspend, nvidia-hibernate, nvidia-resume services"
    mock_cmd "Enable nvidia-suspend" systemctl enable nvidia-suspend.service
    mock_cmd "Enable nvidia-hibernate" systemctl enable nvidia-hibernate.service
    mock_cmd "Enable nvidia-resume" systemctl enable nvidia-resume.service
}

hardware_configure_amd_legacy() {
    local mount_point="${1:-}"
    
    _log_section "Configuring AMD Legacy GPU"
    
    local modprobe_file="/etc/modprobe.d/amdgpu.conf"
    [[ -n "$mount_point" ]] && modprobe_file="$mount_point$modprobe_file"
    
    local amd_conf="# AMD GPU options for legacy hardware
options amdgpu si_support=1
options amdgpu cik_support=1
options radeon si_support=0
options radeon cik_support=0
"
    
    mock_write_file "$modprobe_file" "$amd_conf"
    
    local env_file="/etc/environment"
    [[ -n "$mount_point" ]] && env_file="$mount_point$env_file"
    
    log_info "Adding MESA_LOADER_DRIVER_OVERRIDE for legacy GPU"
    mock_append_file "$env_file" "MESA_LOADER_DRIVER_OVERRIDE=radeonsi"
}

hardware_configure_touchscreen() {
    local mount_point="${1:-}"
    
    _log_section "Configuring Touchscreen"
    
    log_info "Installing touchscreen support packages..."
    local packages=(
        "libinput"
        "xf86-input-libinput"
        "touchegg"
    )
    
    mock_cmd "Install touchscreen packages" pacman -S --noconfirm "${packages[@]}"
    
    log_info "Touchscreen configuration applied"
}

hardware_configure_dell_7000() {
    local mount_point="${1:-}"
    
    _log_section "Configuring Dell 7000 Series"
    
    log_info "Applying Dell 7000 series specific configurations..."
    
    local modprobe_file="/etc/modprobe.d/dell.conf"
    [[ -n "$mount_point" ]] && modprobe_file="$mount_point$modprobe_file"
    
    local dell_conf="# Dell 7000 series specific options
options i915 enable_fbc=1
options i915 enable_psr=2
options snd_hda_intel power_save=1
"
    
    mock_write_file "$modprobe_file" "$dell_conf"
    
    log_info "Installing Dell-specific packages..."
    local packages=(
        "dell-command-configure"
        "smbios-utils"
    )
    
    mock_cmd "Install Dell packages" pacman -S --noconfirm "${packages[@]}" || true
    
    log_info "Dell 7000 configuration applied"
}

hardware_detect_all() {
    _log_section "Full Hardware Detection"
    
    _tui_header "Hardware Detection Results"
    
    echo ""
    echo "=== CPU ==="
    detect_cpu_info | tr '|' '\n' | while read -r line; do
        echo "  $line"
    done
    
    echo ""
    echo "=== GPU ==="
    hardware_detect_gpu | while read -r line; do
        if [[ -n "$line" ]]; then
            echo "  $line"
        fi
    done || echo "  None detected"
    
    echo ""
    echo "=== Touchscreen ==="
    if hardware_detect_touchscreen; then
        echo "  Detected"
    else
        echo "  Not detected"
    fi
    
    echo ""
    echo "=== WiFi ==="
    if hardware_detect_wifi; then
        echo "  Detected"
    else
        echo "  Not detected"
    fi
    
    echo ""
    echo "=== Bluetooth ==="
    if hardware_detect_bluetooth; then
        echo "  Detected"
    else
        echo "  Not detected"
    fi
    
    echo ""
    echo "=== Audio ==="
    if hardware_detect_audio; then
        echo "  Detected"
    else
        echo "  Not detected"
    fi
    
    echo ""
    echo "=== Legacy Hardware ==="
    if hardware_detect_legacy; then
        : 
    else
        echo "  None detected"
    fi
}

hardware_install_drivers() {
    local mount_point="${1:-}"
    
    _log_section "Installing Hardware Drivers"
    
    local gpu_info
    gpu_info=$(hardware_detect_gpu) || true
    
    local vendors=()
    local drivers=()
    
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            local vendor driver
            for part in $line; do
                case "$part" in
                    vendor=*) vendor="${part#vendor=}" ;;
                    driver=*) driver="${part#driver=}" ;;
                esac
            done
            [[ -n "$vendor" ]] && vendors+=("$vendor")
            [[ -n "$driver" ]] && drivers+=("$driver")
        fi
    done <<< "$gpu_info"
    
    for vendor in $(printf '%s\n' "${vendors[@]}" | sort -u); do
        log_info "Installing GPU drivers for: $vendor"
        local packages
        mapfile -t packages < <(hardware_get_gpu_packages "$vendor")
        mock_cmd "Install $vendor drivers" pacman -S --noconfirm "${packages[@]}"
        
        case "$vendor" in
            nvidia) hardware_configure_nvidia "$mount_point" ;;
            amd)
                if hardware_detect_legacy; then
                    hardware_configure_amd_legacy "$mount_point"
                fi
                ;;
        esac
    done
    
    if hardware_detect_touchscreen; then
        hardware_configure_touchscreen "$mount_point"
    fi
    
    if hardware_detect_wifi; then
        log_info "WiFi support included in kernel"
    fi
    
    if hardware_detect_bluetooth; then
        log_info "Installing Bluetooth packages..."
        mock_cmd "Install bluetooth packages" pacman -S --noconfirm bluez bluez-utils
        mock_cmd "Enable bluetooth" systemctl enable bluetooth
    fi
    
    log_info "Hardware driver installation complete"
}

hardware_interactive() {
    _tui_header "Hardware Detection Menu"
    
    local options=(
        "Detect All Hardware"
        "Detect GPU"
        "Detect Touchscreen"
        "Detect WiFi"
        "Detect Bluetooth"
        "Detect Audio"
        "Detect Legacy Hardware"
        "Install Drivers"
        "Back"
    )
    
    while true; do
        local choice
        choice=$(_tui_menu_select "Hardware Options:" "${options[@]}")
        
        case "$choice" in
            "Detect All Hardware") hardware_detect_all ;;
            "Detect GPU") hardware_detect_gpu ;;
            "Detect Touchscreen") hardware_detect_touchscreen ;;
            "Detect WiFi") hardware_detect_wifi ;;
            "Detect Bluetooth") hardware_detect_bluetooth ;;
            "Detect Audio") hardware_detect_audio ;;
            "Detect Legacy Hardware") hardware_detect_legacy ;;
            "Install Drivers") hardware_install_drivers ;;
            "Back") return 0 ;;
        esac
        
        _tui_wait
    done
}

detect_cpu_vendor() {
    local vendor
    vendor=$(cat /proc/cpuinfo 2>/dev/null | grep -m1 "^vendor_id" | cut -d: -f2 | tr -d ' ')
    echo "${vendor:-unknown}"
}

detect_cpu_info() {
    local cpu_info="/proc/cpuinfo"
    
    local vendor model cores threads
    vendor=$(grep -m1 "^vendor_id" "$cpu_info" 2>/dev/null | cut -d: -f2 | tr -d ' ')
    model=$(grep -m1 "^model name" "$cpu_info" 2>/dev/null | cut -d: -f2 | sed 's/^[[:space:]]//')
    cores=$(grep "^cpu cores" "$cpu_info" 2>/dev/null | head -1 | cut -d: -f2 | tr -d ' ')
    threads=$(grep "^siblings" "$cpu_info" 2>/dev/null | head -1 | cut -d: -f2 | tr -d ' ')
    
    echo "vendor=$vendor|model=$model|cores=$cores|threads=$threads"
}
