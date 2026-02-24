#!/usr/bin/env bash
#
# GLM5 Chad Arch Installer - Kernel Management Library
#
# Handles kernel selection and installation:
# - Official kernels (linux, linux-lts, linux-hardened, linux-zen)
# - CachyOS kernels (linux-cachyos, linux-cachyos-bore, linux-cachyos-rt)
# - Liquorix kernel (optimized for desktop/gaming)
# - XanMod kernels
#

set -eo pipefail

if [[ -z "${_KERNEL_LOADED:-}" ]]; then
    readonly _KERNEL_LOADED=1
else
    return 0
fi

declare -A KERNEL_DESC=(
    [linux]="Official Arch Linux kernel (stable)"
    [linux-lts]="Long-term support kernel (stable, older)"
    [linux-hardened]="Security-focused kernel"
    [linux-zen]="Optimized for gaming/desktop"
    [linux-cachyos]="CachyOS kernel with BORE scheduler"
    [linux-cachyos-bore]="CachyOS with BORE scheduler (responsive)"
    [linux-cachyos-rt]="CachyOS realtime kernel"
    [linux-lqx]="Liquorix kernel (desktop/gaming)"
    [linux-xanmod]="XanMod kernel (gaming)"
    [linux-xanmod-lts]="XanMod LTS kernel"
    [linux-xanmod-rt]="XanMod realtime kernel"
)

declare -A KERNEL_REPO=(
    [linux]="official"
    [linux-lts]="official"
    [linux-hardened]="official"
    [linux-zen]="official"
    [linux-cachyos]="cachyos"
    [linux-cachyos-bore]="cachyos"
    [linux-cachyos-rt]="cachyos"
    [linux-lqx]="chaotic-aur"
    [linux-xanmod]="chaotic-aur"
    [linux-xanmod-lts]="chaotic-aur"
    [linux-xanmod-rt]="chaotic-aur"
)

declare -A KERNEL_OPTIMIZED=(
    [linux-cachyos]="v3 v4 bore"
    [linux-cachyos-bore]="v3 v4 bore"
    [linux-lqx]="low-latency"
    [linux-xanmod]="low-latency"
)

declare -a KERNEL_OFFICIAL=("linux" "linux-lts" "linux-hardened" "linux-zen")
declare -a KERNEL_CACHYOS=("linux-cachyos" "linux-cachyos-bore" "linux-cachyos-rt")
declare -a KERNEL_THIRD_PARTY=("linux-lqx" "linux-xanmod" "linux-xanmod-lts" "linux-xanmod-rt")

kernel_is_official() {
    local kernel="$1"
    [[ " ${KERNEL_OFFICIAL[*]} " == *" $kernel "* ]]
}

kernel_is_cachyos() {
    local kernel="$1"
    [[ " ${KERNEL_CACHYOS[*]} " == *" $kernel "* ]]
}

kernel_requires_repo() {
    local kernel="$1"
    local repo="${KERNEL_REPO[$kernel]:-official}"
    [[ "$repo" != "official" ]] && echo "$repo"
}

kernel_get_packages() {
    local kernel="$1"
    local packages=("$kernel" "${kernel}-headers")
    
    if kernel_is_cachyos "$kernel"; then
        packages+=("${kernel}-headers")
    fi
    
    echo "${packages[*]}"
}

kernel_get_microcode() {
    local vendor="$1"
    
    case "$vendor" in
        GenuineIntel) echo "intel-ucode" ;;
        AuthenticAMD) echo "amd-ucode" ;;
        *) echo "" ;;
    esac
}

kernel_get_recommended() {
    local cpu_info vendor model
    cpu_info=$(detect_cpu_info 2>/dev/null || echo "vendor=unknown")
    
    for part in $cpu_info; do
        case "$part" in
            vendor=*) vendor="${part#vendor=}" ;;
            model=*) model="${part#model=}" ;;
        esac
    done
    
    if echo "$model" | grep -qiE "server|xeon|epyc"; then
        echo "linux-lts"
        return 0
    fi
    
    local flags
    flags=$(grep -m1 "^flags" /proc/cpuinfo 2>/dev/null | cut -d: -f2)
    
    if echo "$flags" | grep -qE "avx2|avx512"; then
        echo "linux-cachyos-bore"
    else
        echo "linux-zen"
    fi
}

kernel_detect_optimized_version() {
    local kernel="$1"
    local flags
    flags=$(grep -m1 "^flags" /proc/cpuinfo 2>/dev/null | cut -d: -f2)
    
    if kernel_is_cachyos "$kernel"; then
        if echo "$flags" | grep -qE "avx512f.*avx512dq.*avx512cd.*avx512bw.*avx512vl"; then
            echo "v4"
        elif echo "$flags" | grep -q "avx2"; then
            echo "v3"
        else
            echo "v2"
        fi
    fi
}

kernel_validate_available() {
    local kernel="$1"
    local repo="${KERNEL_REPO[$kernel]:-}"
    
    case "$repo" in
        official)
            return 0
            ;;
        cachyos|chaotic-aur)
            if repo_is_enabled "$repo" 2>/dev/null || [[ "$repo" == "cachyos" && $(repo_is_enabled cachyos 2>/dev/null) ]]; then
                return 0
            fi
            log_warn "Kernel $kernel requires $repo repository"
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

kernel_install() {
    local kernel="$1"
    local mount_point="${2:-}"
    local vendor="${3:-}"
    
    _log_section "Installing Kernel: $kernel"
    
    local packages
    mapfile -t packages < <(kernel_get_packages "$kernel" | tr ' ' '\n')
    
    local microcode
    microcode=$(kernel_get_microcode "$vendor")
    [[ -n "$microcode" ]] && packages+=("$microcode")
    
    log_info "Packages to install: ${packages[*]}"
    
    if [[ -n "$mount_point" ]]; then
        mock_cmd "Install kernel packages" pacstrap "$mount_point" "${packages[@]}"
    else
        mock_cmd "Install kernel packages" pacman -S --noconfirm "${packages[@]}"
    fi
    
    log_info "Kernel $kernel installed"
}

kernel_list_available() {
    _tui_header "Available Kernels"
    
    echo ""
    echo "=== Official Kernels ==="
    for k in "${KERNEL_OFFICIAL[@]}"; do
        printf "  %-25s %s\n" "$k" "${KERNEL_DESC[$k]}"
    done
    
    echo ""
    echo "=== CachyOS Kernels (requires cachyos repo) ==="
    for k in "${KERNEL_CACHYOS[@]}"; do
        local opt="${KERNEL_OPTIMIZED[$k]:-}"
        printf "  %-25s %s %s\n" "$k" "${KERNEL_DESC[$k]}" "${opt:+[$opt]}"
    done
    
    echo ""
    echo "=== Third-Party Kernels (requires chaotic-aur repo) ==="
    for k in "${KERNEL_THIRD_PARTY[@]}"; do
        local opt="${KERNEL_OPTIMIZED[$k]:-}"
        printf "  %-25s %s %s\n" "$k" "${KERNEL_DESC[$k]}" "${opt:+[$opt]}"
    done
}

kernel_select() {
    local recommended
    recommended=$(kernel_get_recommended)
    
    _tui_header "Kernel Selection"
    
    echo "Recommended for your system: $recommended"
    echo ""
    
    local all_kernels=()
    all_kernels+=("${KERNEL_OFFICIAL[@]}")
    all_kernels+=("${KERNEL_CACHYOS[@]}")
    all_kernels+=("${KERNEL_THIRD_PARTY[@]}")
    
    local options=()
    for k in "${all_kernels[@]}"; do
        local desc="${KERNEL_DESC[$k]:-$k}"
        local marker=""
        [[ "$k" == "$recommended" ]] && marker=" (Recommended)"
        options+=("$k$marker - $desc")
    done
    
    local choice
    choice=$(_tui_menu_select "Select kernel:" "${options[@]}")
    
    echo "${choice%% *}"
}

kernel_select_multi() {
    local recommended
    recommended=$(kernel_get_recommended)
    
    _tui_header "Kernel Selection (Multiple)"
    
    echo "Select multiple kernels (e.g., main + LTS fallback)"
    echo "Recommended: $recommended"
    echo ""
    
    local all_kernels=()
    all_kernels+=("${KERNEL_OFFICIAL[@]}")
    all_kernels+=("${KERNEL_CACHYOS[@]}")
    all_kernels+=("${KERNEL_THIRD_PARTY[@]}")
    
    local options=()
    for k in "${all_kernels[@]}"; do
        local desc="${KERNEL_DESC[$k]:-$k}"
        local marker=""
        [[ "$k" == "$recommended" ]] && marker=" (Recommended)"
        options+=("$k$marker")
    done
    
    local selected
    mapfile -t selected < <(_tui_menu_multi "Select kernels (Space to toggle):" "${options[@]}")
    
    for s in "${selected[@]}"; do
        echo "${s%% *}"
    done
}

kernel_generate_mkinitcpio() {
    local mount_point="${1:-}"
    local luks_enabled="${2:-false}"
    
    _log_section "Configuring mkinitcpio"
    
    local config_file="/etc/mkinitcpio.conf"
    [[ -n "$mount_point" ]] && config_file="$mount_point$config_file"
    
    local modules=""
    local hooks="base udev autodetect keyboard keymap consolefont modconf block"
    
    if [[ "$luks_enabled" == "true" ]]; then
        hooks+=" encrypt"
    fi
    
    hooks+=" filesystems keyboard fsck"
    
    if grep -q "btrfs" /proc/filesystems 2>/dev/null; then
        modules+=" btrfs"
    fi
    
    local mkinitcpio_conf="# Generated by GLM5 Chad Arch Installer
MODULES=\"$modules\"
BINARIES=\"\"
FILES=\"\"
HOOKS=\"$hooks\"
COMPRESSION=\"zstd\"
COMPRESSION_OPTIONS=\"-19\"
"
    
    mock_write_file "$config_file" "$mkinitcpio_conf"
    
    log_info "mkinitcpio configured"
}

kernel_configure_modules() {
    local mount_point="${1:-}"
    local kernel="${2:-linux}"
    
    _log_section "Configuring Kernel Modules"
    
    local modprobe_dir="/etc/modprobe.d"
    [[ -n "$mount_point" ]] && modprobe_dir="$mount_point$modprobe_dir"
    
    mkdir -p "$modprobe_dir"
    
    local blacklist_conf="# Blacklist problematic modules
blacklist pcspkr
blacklist snd_pcsp
"
    mock_write_file "$modprobe_dir/99-blacklist.conf" "$blacklist_conf"
}
