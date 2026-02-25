#!/usr/bin/env bash
#
# GLM5 Chad Arch Installer - Dependency Resolution
#
# Handles checking and installing dependencies for the installer
#

set -eo pipefail

if [[ -z "${_DEPS_LOADED:-}" ]]; then
    readonly _DEPS_LOADED=1
else
    return 0
fi

declare -A DEPS_REQUIRED=(
    [bash]="bash"
    [python3]="python"
    [sed]="sed"
    [awk]="gawk"
    [grep]="grep"
    [tr]="coreutils"
    [cut]="coreutils"
)

declare -A DEPS_TUI=(
    [gum]="gum"
)

declare -A DEPS_NETWORK=(
    [curl]="curl"
    [wget]="wget"
)

declare -A DEPS_INSTALL=(
    [parted]="parted"
    [mkfs.btrfs]="btrfs-progs"
    [pacstrap]="arch-install-scripts"
    [arch-chroot]="arch-install-scripts"
)

declare -A DEPS_COMPRESS=(
    [zstd]="zstd"
    [xz]="xz"
    [gzip]="gzip"
)

declare -A DEPS_OPTIONAL=(
    [yq]="yq"
    [bc]="bc"
    [jq]="jq"
)

declare -A DEPS_MISSING=()
declare -A DEPS_AVAILABLE=()

deps_check_binary() {
    local binary="$1"
    command -v "$binary" &>/dev/null
}

deps_get_package() {
    local binary="$1"
    
    if [[ -v "DEPS_REQUIRED[$binary]" ]]; then
        echo "${DEPS_REQUIRED[$binary]}"
    elif [[ -v "DEPS_TUI[$binary]" ]]; then
        echo "${DEPS_TUI[$binary]}"
    elif [[ -v "DEPS_NETWORK[$binary]" ]]; then
        echo "${DEPS_NETWORK[$binary]}"
    elif [[ -v "DEPS_INSTALL[$binary]" ]]; then
        echo "${DEPS_INSTALL[$binary]}"
    elif [[ -v "DEPS_COMPRESS[$binary]" ]]; then
        echo "${DEPS_COMPRESS[$binary]}"
    elif [[ -v "DEPS_OPTIONAL[$binary]" ]]; then
        echo "${DEPS_OPTIONAL[$binary]}"
    else
        echo "$binary"
    fi
}

deps_check_group() {
    local group="$1"
    shift
    local binaries=("$@")
    
    local missing=()
    local available=()
    
    for binary in "${binaries[@]}"; do
        if deps_check_binary "$binary"; then
            available+=("$binary")
        else
            missing+=("$binary")
        fi
    done
    
    DEPS_AVAILABLE[$group]="${available[*]}"
    DEPS_MISSING[$group]="${missing[*]}"
    
    [[ ${#missing[@]} -eq 0 ]]
}

deps_check_all() {
    _log_section "Checking Dependencies"
    
    local errors=0
    local warnings=0
    
    log_info "Checking required tools..."
    for binary in "${!DEPS_REQUIRED[@]}"; do
        if deps_check_binary "$binary"; then
            log_debug "✓ $binary: $(command -v "$binary")"
        else
            log_error "✗ $binary: NOT FOUND"
            ((errors++))
        fi
    done
    
    log_info "Checking TUI backends..."
    local tui_found=false
    for binary in "${!DEPS_TUI[@]}"; do
        if deps_check_binary "$binary"; then
            log_debug "✓ $binary: $(command -v "$binary")"
            tui_found=true
        else
            log_debug "- $binary: not installed (optional)"
        fi
    done
    
    if ! $tui_found; then
        log_warn "⚠ gum not found - TUI will not work. Install with: pacman -S gum"
        ((warnings++))
    fi
    
    log_info "Checking network tools..."
    local net_found=false
    for binary in "${!DEPS_NETWORK[@]}"; do
        if deps_check_binary "$binary"; then
            log_debug "✓ $binary: $(command -v "$binary")"
            net_found=true
            break
        fi
    done
    
    if ! $net_found; then
        log_warn "⚠ No network tool found - repos update will not work"
        ((warnings++))
    fi
    
    log_info "Checking installation tools..."
    for binary in "${!DEPS_INSTALL[@]}"; do
        if deps_check_binary "$binary"; then
            log_debug "✓ $binary: $(command -v "$binary")"
        else
            log_debug "- $binary: not available (needed for installation)"
            ((warnings++))
        fi
    done
    
    log_info "Checking compression tools..."
    for binary in "${!DEPS_COMPRESS[@]}"; do
        if deps_check_binary "$binary"; then
            log_debug "✓ $binary: $(command -v "$binary")"
        else
            log_debug "- $binary: not available"
        fi
    done
    
    log_info "Checking optional tools..."
    for binary in "${!DEPS_OPTIONAL[@]}"; do
        if deps_check_binary "$binary"; then
            log_debug "✓ $binary: $(command -v "$binary")"
        else
            log_debug "- $binary: not installed (optional)"
        fi
    done
    
    log_info ""
    
    if [[ $errors -gt 0 ]]; then
        log_error "❌ $errors errors found - some functionality will not work"
        return 1
    elif [[ $warnings -gt 0 ]]; then
        log_warn "⚠ $warnings warnings - some features may be limited"
        return 0
    else
        log_success "✓ All dependencies satisfied"
        return 0
    fi
}

deps_install_missing() {
    local packages=()
    
    for binary in "${!DEPS_MISSING[@]}"; do
        local pkg
        pkg=$(deps_get_package "$binary")
        packages+=("$pkg")
    done
    
    if [[ ${#packages[@]} -eq 0 ]]; then
        log_info "No missing dependencies to install"
        return 0
    fi
    
    log_info "Installing missing packages: ${packages[*]}"
    
    if [[ "$MOCK_MODE" == "true" ]]; then
        mock_cmd "Install dependencies" pacman -S --noconfirm "${packages[@]}"
    else
        pacman -S --noconfirm "${packages[@]}"
    fi
}

deps_ensure() {
    local binary="$1"
    local package="${2:-$(deps_get_package "$binary")}"
    
    if deps_check_binary "$binary"; then
        return 0
    fi
    
    log_warn "Missing dependency: $binary"
    
    if _tui_confirm "Install $package?"; then
        if [[ "$MOCK_MODE" == "true" ]]; then
            mock_cmd "Install $package" pacman -S --noconfirm "$package"
        else
            pacman -S --noconfirm "$package"
        fi
        return 0
    fi
    
    return 1
}

deps_ensure_bc() {
    deps_ensure "bc" "bc"
}

deps_ensure_zstd() {
    deps_ensure "zstd" "zstd"
}

deps_ensure_curl_or_wget() {
    if deps_check_binary "curl" || deps_check_binary "wget"; then
        return 0
    fi
    
    log_warn "No network tool available"
    
    if _tui_confirm "Install curl?"; then
        if [[ "$MOCK_MODE" == "true" ]]; then
            mock_cmd "Install curl" pacman -S --noconfirm curl
        else
            pacman -S --noconfirm curl
        fi
        return 0
    fi
    
    return 1
}

deps_ensure_yq_or_internal() {
    if deps_check_binary "yq"; then
        return 0
    fi
    
    log_debug "yq not found, using internal YAML parser"
    return 0
}

deps_get_status() {
    local status=""
    
    if deps_check_binary "gum"; then
        status+="TUI: gum ✓ | "
    else
        status+="TUI: ✗ | "
    fi
    
    if deps_check_binary "curl" || deps_check_binary "wget"; then
        status+="Network: ✓ | "
    else
        status+="Network: ✗ | "
    fi
    
    if deps_check_binary "parted" && deps_check_binary "pacstrap"; then
        status+="Install: ✓"
    else
        status+="Install: ✗"
    fi
    
    echo "$status"
}
