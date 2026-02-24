#!/usr/bin/env bash
#
# GLM5 Chad Arch Installer - Bootloader Management Library
#
# Handles bootloader installation and configuration:
# - systemd-boot (default for UEFI)
# - GRUB (fallback, required for some hardware)
# - Limine (modern, fast bootloader)
# - rEFInd (alternative UEFI bootloader)
#

set -eo pipefail

if [[ -z "${_BOOTLOADER_LOADED:-}" ]]; then
    readonly _BOOTLOADER_LOADED=1
else
    return 0
fi

declare -A BOOTLOADER_PACKAGES=(
    [systemd-boot]="efibootmgr"
    [grub]="grub efibootmgr"
    [limine]="limine"
    [refind]="refind"
)

declare -A BOOTLOADER_DESC=(
    [systemd-boot]="Native UEFI bootloader, fast and simple"
    [grub]="Traditional bootloader, widest compatibility (required for Chromebooks)"
    [limine]="Modern bootloader with advanced features, very fast"
    [refind]="Graphical UEFI bootloader with theme support"
)

bootloader_detect_uefi() {
    [[ -d /sys/firmware/efi ]]
}

bootloader_detect_secure_boot() {
    if [[ -f /sys/firmware/efi/efivars/SecureBoot-* ]]; then
        local sb
        sb=$(cat /sys/firmware/efi/efivars/SecureBoot-* 2>/dev/null | od -An -tu1 | tr -d ' ')
        [[ "$sb" == "1" ]]
    else
        return 1
    fi
}

bootloader_requires_grub() {
    local reasons=()
    
    if [[ -d /sys/firmware/efi ]] && grep -qi "chromebook\|chromebox" /sys/class/dmi/id/product_name 2>/dev/null; then
        reasons+=("Chromebook hardware detected")
    fi
    
    if ! bootloader_detect_uefi; then
        reasons+=("BIOS mode (not UEFI)")
    fi
    
    if [[ ${#reasons[@]} -gt 0 ]]; then
        echo "${reasons[*]}"
        return 0
    fi
    return 1
}

bootloader_get_recommended() {
    local required
    required=$(bootloader_requires_grub) && {
        echo "grub"
        return 0
    }
    
    if bootloader_detect_uefi; then
        echo "limine"
    else
        echo "grub"
    fi
}

bootloader_get_packages() {
    local bootloader="$1"
    echo "${BOOTLOADER_PACKAGES[$bootloader]:-}"
}

bootloader_install_packages() {
    local bootloader="$1"
    local mount_point="${2:-}"
    
    local packages
    packages=$(bootloader_get_packages "$bootloader")
    
    if [[ -z "$packages" ]]; then
        log_error "Unknown bootloader: $bootloader"
        return 1
    fi
    
    log_info "Installing bootloader packages: $packages"
    
    if [[ -n "$mount_point" ]]; then
        mock_cmd "Install bootloader packages" pacstrap "$mount_point" $packages
    else
        mock_cmd "Install bootloader packages" pacman -S --noconfirm $packages
    fi
}

bootloader_install_systemd_boot() {
    local mount_point="$1"
    local kernel="$2"
    local root_uuid="$3"
    
    _log_section "Installing systemd-boot"
    
    mock_cmd "Install systemd-boot" arch-chroot "$mount_point" bootctl install --path=/boot
    
    local loader_conf="default arch.conf
timeout 5
console-mode max
editor no
"
    mock_write_file "$mount_point/boot/loader/loader.conf" "$loader_conf"
    
    local entry_conf="title   Arch Linux
linux   /vmlinuz-$kernel
initrd  /initramfs-$kernel.img
options root=UUID=$root_uuid rootflags=subvol=/@ rw
"
    mock_write_file "$mount_point/boot/loader/entries/arch.conf" "$entry_conf"
    
    if [[ -f "$mount_point/boot/vmlinuz-$kernel-lts" ]]; then
        local fallback_conf="title   Arch Linux (fallback)
linux   /vmlinuz-$kernel
initrd  /initramfs-$kernel-fallback.img
options root=UUID=$root_uuid rootflags=subvol=/@ rw
"
        mock_write_file "$mount_point/boot/loader/entries/arch-fallback.conf" "$fallback_conf"
    fi
    
    log_info "systemd-boot installed successfully"
}

bootloader_install_grub() {
    local mount_point="$1"
    local kernel="$2"
    local root_uuid="$3"
    local luks_uuid="${4:-}"
    
    _log_section "Installing GRUB"
    
    local grub_cmdline="root=UUID=$root_uuid rootflags=subvol=/@ rw"
    [[ -n "$luks_uuid" ]] && grub_cmdline="cryptdevice=UUID=$luks_uuid:cryptroot $grub_cmdline"
    
    local grub_default="GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR=\"Arch\"
GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet\"
GRUB_CMDLINE_LINUX=\"$grub_cmdline\"
GRUB_PRELOAD_MODULES=\"part_gpt part_msdos\"
GRUB_ENABLE_CRYPTODISK=y
"
    mock_write_file "$mount_point/etc/default/grub" "$grub_default"
    
    if bootloader_detect_uefi; then
        mock_cmd "Install GRUB UEFI" arch-chroot "$mount_point" grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --removable
    else
        local device="${INSTALL_DEVICE:-/dev/sda}"
        mock_cmd "Install GRUB BIOS" arch-chroot "$mount_point" grub-install --target=i386-pc "$device"
    fi
    
    mock_cmd "Generate GRUB config" arch-chroot "$mount_point" grub-mkconfig -o /boot/grub/grub.cfg
    
    log_info "GRUB installed successfully"
}

bootloader_install_limine() {
    local mount_point="$1"
    local kernel="$2"
    local root_uuid="$3"
    local luks_uuid="${4:-}"
    
    _log_section "Installing Limine"
    
    local cmdline="root=UUID=$root_uuid rootflags=subvol=/@ rw"
    [[ -n "$luks_uuid" ]] && cmdline="cryptdevice=UUID=$luks_uuid:cryptroot $cmdline"
    
    mock_cmd "Install Limine" arch-chroot "$mount_point" limine-install /boot
    
    local limine_conf="timeout: 5

/Arch Linux
    protocol: linux
    kernel_path: boot():/vmlinuz-$kernel
    kernel_cmdline: $cmdline
    module_path: boot():/initramfs-$kernel.img

/Arch Linux (fallback)
    protocol: linux
    kernel_path: boot():/vmlinuz-$kernel
    kernel_cmdline: $cmdline
    module_path: boot():/initramfs-$kernel-fallback.img
"
    mock_write_file "$mount_point/boot/limine.conf" "$limine_conf"
    
    log_info "Limine installed successfully"
}

bootloader_install_refind() {
    local mount_point="$1"
    local kernel="$2"
    local root_uuid="$3"
    
    _log_section "Installing rEFInd"
    
    mock_cmd "Install rEFInd" arch-chroot "$mount_point" refind-install
    
    local refind_conf="timeout 5
showtools all
scan_driver_dirs drivers
scanfor manual,external
menus_dir /boot/EFI/refind/themes/rEFInd-minimal
    
menuentry \"Arch Linux\" {
    volume   \"Arch Linux\"
    loader   /vmlinuz-$kernel
    initrd   /initramfs-$kernel.img
    options  \"root=UUID=$root_uuid rootflags=subvol=/@ rw\"
}
"
    mock_write_file "$mount_point/boot/EFI/refind/refind.conf" "$refind_conf"
    
    log_info "rEFInd installed successfully"
}

bootloader_install() {
    local bootloader="$1"
    local mount_point="$2"
    local kernel="$3"
    local root_uuid="$4"
    local luks_uuid="${5:-}"
    
    bootloader_install_packages "$bootloader" "$mount_point"
    
    case "$bootloader" in
        systemd-boot)
            bootloader_install_systemd_boot "$mount_point" "$kernel" "$root_uuid"
            ;;
        grub)
            bootloader_install_grub "$mount_point" "$kernel" "$root_uuid" "$luks_uuid"
            ;;
        limine)
            bootloader_install_limine "$mount_point" "$kernel" "$root_uuid" "$luks_uuid"
            ;;
        refind)
            bootloader_install_refind "$mount_point" "$kernel" "$root_uuid"
            ;;
        *)
            log_error "Unknown bootloader: $bootloader"
            return 1
            ;;
    esac
}

bootloader_configure_secure_boot() {
    local mount_point="$1"
    
    _log_section "Configuring Secure Boot"
    
    log_info "Installing secure boot packages..."
    local packages=("sbctl" "shim-signed" "mokutil")
    mock_cmd "Install secure boot packages" pacman -S --noconfirm "${packages[@]}"
    
    log_info "Secure boot requires manual key enrollment"
    log_info "After installation, run: sbctl create-keys && sbctl enroll-keys"
}

bootloader_menu() {
    _tui_header "Bootloader Selection"
    
    local recommended
    recommended=$(bootloader_get_recommended)
    
    local required_reason
    required_reason=$(bootloader_requires_grub)
    if [[ -n "$required_reason" ]]; then
        _tui_warn "GRUB is required: $required_reason"
        echo ""
    fi
    
    local options=()
    for bl in systemd-boot grub limine refind; do
        local desc="${BOOTLOADER_DESC[$bl]}"
        if [[ "$bl" == "$recommended" ]]; then
            options+=("$bl (Recommended) - $desc")
        else
            options+=("$bl - $desc")
        fi
    done
    
    local choice
    choice=$(_tui_menu_select "Select bootloader:" "${options[@]}")
    
    echo "${choice%% *}"
}
