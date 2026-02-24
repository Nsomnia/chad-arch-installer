#!/usr/bin/env bash
#
# GLM5 Chad Arch Installer - Installation Module
#

set -eo pipefail

if [[ -z "${_INSTALL_LOADED:-}" ]]; then
    readonly _INSTALL_LOADED=1
else
    return 0
fi

INSTALL_MOUNT="${INSTALL_MOUNT:-/mnt}"
INSTALL_DEVICE=""
INSTALL_EFI_PARTITION=""
INSTALL_ROOT_PARTITION=""

install_preflight() {
    _log_section "Pre-flight Checks"
    
    log_info "Checking UEFI mode..."
    if [[ ! -d /sys/firmware/efi ]]; then
        log_error "System is not in UEFI mode. This installer requires UEFI."
        return 1
    fi
    log_info "UEFI mode confirmed"
    
    log_info "Checking internet connection..."
    if ! ping -c 1 archlinux.org &>/dev/null; then
        log_error "No internet connection. Please connect to the internet."
        return 1
    fi
    log_info "Internet connection confirmed"
    
    log_info "Checking for required tools..."
    local required_tools=("parted" "mkfs.btrfs" "pacstrap" "arch-chroot")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            log_error "Required tool not found: $tool"
            return 1
        fi
    done
    log_info "All required tools available"
    
    log_info "Checking disk space..."
    local mem_kb
    mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local mem_gb=$((mem_kb / 1024 / 1024))
    log_info "System has ${mem_gb}GB RAM"
    
    log_info "Pre-flight checks passed"
}

install_select_disk() {
    _log_section "Disk Selection"
    
    local disks=()
    local disk_info=()
    
    while IFS= read -r line; do
        local name size type
        name=$(echo "$line" | awk '{print $1}')
        size=$(echo "$line" | awk '{print $2" "$3}')
        type=$(echo "$line" | awk '{print $4}')
        
        if [[ "$name" =~ ^/dev/(nvme|sd|vd|mmcblk) ]]; then
            disks+=("$name")
            disk_info+=("$name|$size|$type")
        fi
    done < <(lsblk -ndo NAME,SIZE,TYPE | grep disk)
    
    if [[ ${#disks[@]} -eq 0 ]]; then
        log_error "No disks found"
        return 1
    fi
    
    _tui_header "Available Disks"
    _tui_table disk_info "Device" "Size" "Type"
    
    local selected
    selected=$(_tui_menu_select "Select target disk (WARNING: Will be erased!)" "${disks[@]}")
    
    if [[ -z "$selected" ]]; then
        log_error "No disk selected"
        return 1
    fi
    
    INSTALL_DEVICE="$selected"
    log_info "Selected disk: $INSTALL_DEVICE"
    
    if ! _tui_confirm "This will ERASE ALL DATA on $INSTALL_DEVICE. Continue?"; then
        log_info "Installation cancelled by user"
        return 1
    fi
}

install_partition_disk() {
    local device="$1"
    local efi_size="${2:-1024}"
    local wipe_method="${3:-quick}"
    
    _log_section "Partitioning Disk: $device"
    
    case "$wipe_method" in
        quick)
            log_info "Quick wipe (zap partition table)"
            mock_cmd "Zap disk" sgdisk --zap-all "$device"
            ;;
        secure)
            log_info "Secure wipe (this will take a while)"
            mock_cmd "Secure wipe" dd if=/dev/urandom of="$device" bs=1M status=progress
            ;;
        discard)
            log_info "Discard (SSD TRIM)"
            mock_cmd "Discard" blkdiscard "$device"
            ;;
        skip)
            log_info "Skipping disk wipe"
            ;;
    esac
    
    log_info "Creating partition table..."
    mock_cmd "Create GPT table" parted -s "$device" mklabel gpt
    
    log_info "Creating EFI partition (${efi_size}MB)..."
    mock_cmd "Create EFI partition" parted -s "$device" mkpart ESP fat32 1MiB "${efi_size}MiB"
    mock_cmd "Set EFI flag" parted -s "$device" set 1 esp on
    
    log_info "Creating root partition..."
    mock_cmd "Create root partition" parted -s "$device" mkpart root btrfs "${efi_size}MiB" 100%
    
    if [[ "$device" =~ nvme || "$device" =~ mmcblk ]]; then
        INSTALL_EFI_PARTITION="${device}p1"
        INSTALL_ROOT_PARTITION="${device}p2"
    else
        INSTALL_EFI_PARTITION="${device}1"
        INSTALL_ROOT_PARTITION="${device}2"
    fi
    
    log_info "Partitions created:"
    log_info "  EFI:  $INSTALL_EFI_PARTITION"
    log_info "  Root: $INSTALL_ROOT_PARTITION"
}

install_format_partitions() {
    local efi_part="$1"
    local root_part="$2"
    local luks_enabled="${3:-false}"
    local luks_password="${4:-}"
    
    _log_section "Formatting Partitions"
    
    log_info "Formatting EFI partition..."
    mock_cmd "Format EFI" mkfs.vfat -F32 "$efi_part"
    
    if $luks_enabled; then
        log_info "Setting up LUKS encryption..."
        
        local luks_opts=(
            "--type" "luks2"
            "--cipher" "aes-xts-plain64"
            "--key-size" "512"
            "--hash" "sha512"
            "--pbkdf" "argon2id"
            "--iter-time" "4000"
        )
        
        if [[ -n "$luks_password" ]]; then
            echo -n "$luks_password" | mock_cmd "Create LUKS container" cryptsetup luksFormat "${luks_opts[@]}" "$root_part" -
            echo -n "$luks_password" | mock_cmd "Open LUKS container" cryptsetup open "$root_part" cryptroot -
            INSTALL_ROOT_PARTITION="/dev/mapper/cryptroot"
        else
            mock_cmd "Create LUKS container" cryptsetup luksFormat "${luks_opts[@]}" "$root_part"
            mock_cmd "Open LUKS container" cryptsetup open "$root_part" cryptroot
            INSTALL_ROOT_PARTITION="/dev/mapper/cryptroot"
        fi
    fi
    
    log_info "Formatting root partition as BTRFS..."
    local btrfs_label
    btrfs_label=$(config_get "storage.btrfs.label" "ARCH")
    mock_cmd "Format BTRFS" mkfs.btrfs -L "$btrfs_label" -f "$INSTALL_ROOT_PARTITION"
}

install_mount_filesystems() {
    local root_part="$1"
    local efi_part="$2"
    local mount_point="${3:-$INSTALL_MOUNT}"
    
    _log_section "Mounting Filesystems"
    
    local compress
    compress=$(config_get "storage.btrfs.compress" "zstd:3")
    
    btrfs_create_layout "$root_part" "$mount_point" "$compress"
    btrfs_mount_subvolumes "$root_part" "$mount_point" "$compress"
    
    log_info "Mounting EFI partition..."
    mkdir -p "$mount_point/boot"
    mock_cmd "Mount EFI" mount "$efi_part" "$mount_point/boot"
    
    log_info "Filesystems mounted successfully"
}

install_base_system() {
    local mount_point="${1:-$INSTALL_MOUNT}"
    
    _log_section "Installing Base System"
    
    local kernel
    kernel=$(config_get "boot.kernel" "linux")
    
    local cpu_vendor
    cpu_vendor=$(detect_cpu_vendor)
    
    local microcode=""
    case "$cpu_vendor" in
        GenuineIntel) microcode="intel-ucode" ;;
        AuthenticAMD) microcode="amd-ucode" ;;
    esac
    
    local base_packages=(
        "base" "base-devel"
        "$kernel" "${kernel}-headers"
        "linux-firmware"
        "btrfs-progs"
        "snapper"
        "sudo"
        "vim"
        "networkmanager"
        "openssh"
        "git"
        "curl" "wget"
        "man-db" "man-pages"
        "texinfo"
    )
    
    [[ -n "$microcode" ]] && base_packages+=("$microcode")
    
    local bootloader
    bootloader=$(config_get "boot.loader" "systemd-boot")
    case "$bootloader" in
        systemd-boot) base_packages+=("efibootmgr") ;;
        grub) base_packages+=("grub" "efibootmgr") ;;
        refind) base_packages+=("refind") ;;
    esac
    
    log_info "Installing packages: ${base_packages[*]}"
    
    mock_progress "Installing base system" 30
    
    mock_cmd "Install base system" pacstrap "$mount_point" "${base_packages[@]}"
    
    log_info "Base system installed"
}

install_generate_fstab() {
    local mount_point="${1:-$INSTALL_MOUNT}"
    
    _log_section "Generating fstab"
    
    log_info "Generating fstab..."
    
    if [[ "$MOCK_MODE" == "true" ]]; then
        local fstab_content="# Generated by GLM5 Chad Arch Installer
# <device>                                    <mount>    <type>  <options>                                               <dump> <fsck>

# EFI partition
UUID=mock-efi-uuid                            /boot      vfat    defaults,noatime                                        0      2

# BTRFS subvolumes
UUID=mock-root-uuid                           /          btrfs   subvol=/@,noatime,compress=zstd:3,commit=120            0      0
UUID=mock-root-uuid                           /home      btrfs   subvol=/@home,noatime,compress=zstd:3,commit=120        0      0
UUID=mock-root-uuid                           /var       btrfs   subvol=/@var,noatime,compress=zstd:3,commit=120,nodatacow 0    0
UUID=mock-root-uuid                           /var/log   btrfs   subvol=/@var_log,noatime,compress=zstd:3,commit=120     0      0
UUID=mock-root-uuid                           /var/cache btrfs   subvol=/@var_cache,noatime,compress=zstd:3,commit=120   0      0
UUID=mock-root-uuid                           /.snapshots btrfs  subvol=/@snapshots,noatime,compress=zstd:3,commit=120   0      0

# Swap
/.swap/swapfile                               none       swap    defaults                                                0      0
"
        mock_write_file "$mount_point/etc/fstab" "$fstab_content"
    else
        genfstab -U "$mount_point" >> "$mount_point/etc/fstab"
    fi
    
    log_info "fstab generated"
}

install_configure_system() {
    local mount_point="${1:-$INSTALL_MOUNT}"
    
    _log_section "Configuring System"
    
    local hostname
    hostname=$(config_get "system.hostname" "arch-chad")
    log_info "Setting hostname: $hostname"
    mock_write_file "$mount_point/etc/hostname" "$hostname"
    
    local timezone
    timezone=$(config_get "system.timezone" "UTC")
    log_info "Setting timezone: $timezone"
    mock_cmd "Set timezone" ln -sf "/usr/share/zoneinfo/$timezone" "$mount_point/etc/localtime"
    
    local locale
    locale=$(config_get "system.locale" "en_US.UTF-8")
    log_info "Configuring locale: $locale"
    echo "$locale UTF-8" >> "$mount_point/etc/locale.gen" 2>/dev/null || true
    mock_write_file "$mount_point/etc/locale.conf" "LANG=$locale"
    
    local keymap
    keymap=$(config_get "system.keymap" "us")
    log_info "Setting keymap: $keymap"
    mock_write_file "$mount_point/etc/vconsole.conf" "KEYMAP=$keymap"
    
    log_info "System configuration complete"
}

install_setup_bootloader() {
    local mount_point="${1:-$INSTALL_MOUNT}"
    local root_part="$2"
    
    _log_section "Installing Bootloader"
    
    local bootloader
    bootloader=$(config_get "boot.loader" "systemd-boot")
    
    case "$bootloader" in
        systemd-boot)
            log_info "Installing systemd-boot..."
            mock_cmd "Install systemd-boot" arch-chroot "$mount_point" bootctl install
            
            local loader_conf="default arch.conf
timeout 5
console-mode max
editor no
"
            mock_write_file "$mount_point/boot/loader/loader.conf" "$loader_conf"
            
            local root_uuid
            root_uuid=$(btrfs_get_uuid "$root_part")
            
            local kernel
            kernel=$(config_get "boot.kernel" "linux")
            
            local entry_conf="title   Arch Linux
linux   /vmlinuz-$kernel
initrd  /initramfs-$kernel.img
options root=UUID=$root_uuid rootflags=subvol=/@ rw
"
            mock_write_file "$mount_point/boot/loader/entries/arch.conf" "$entry_conf"
            ;;
            
        grub)
            log_info "Installing GRUB..."
            mock_cmd "Install GRUB" arch-chroot "$mount_point" grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
            mock_cmd "Generate GRUB config" arch-chroot "$mount_point" grub-mkconfig -o /boot/grub/grub.cfg
            ;;
            
        refind)
            log_info "Installing rEFInd..."
            mock_cmd "Install rEFInd" arch-chroot "$mount_point" refind-install
            ;;
    esac
    
    log_info "Bootloader installed: $bootloader"
}

install_create_user() {
    local mount_point="${1:-$INSTALL_MOUNT}"
    local username="${2:-}"
    local password="${3:-}"
    
    _log_section "Creating User"
    
    if [[ -z "$username" ]]; then
        username=$(_tui_input "Enter username")
    fi
    
    if [[ -z "$password" ]]; then
        password=$(_tui_password "Enter password for $username")
    fi
    
    log_info "Creating user: $username"
    
    mock_cmd "Create user" arch-chroot "$mount_point" useradd -m -G wheel -s /bin/bash "$username"
    
    log_info "Setting password..."
    echo "$username:$password" | mock_cmd "Set password" chroot "$mount_point" chpasswd
    
    log_info "Enabling sudo for wheel group..."
    mock_write_file "$mount_point/etc/sudoers.d/wheel" "%wheel ALL=(ALL) ALL"
    
    log_info "User $username created"
}

install_post_config() {
    local mount_point="${1:-$INSTALL_MOUNT}"
    
    _log_section "Post-Installation Configuration"
    
    log_info "Enabling NetworkManager..."
    mock_cmd "Enable NetworkManager" arch-chroot "$mount_point" systemctl enable NetworkManager
    
    log_info "Enabling SSH..."
    mock_cmd "Enable SSH" arch-chroot "$mount_point" systemctl enable sshd
    
    if config_get_bool "snapper.enabled" true; then
        log_info "Setting up Snapper..."
        snapper_full_setup "$mount_point" "$mount_point/home"
    fi
    
    local swap_size
    swap_size=$(config_get "storage.swap_size_mb" "4096")
    if [[ "$swap_size" -gt 0 ]]; then
        btrfs_create_swapfile "$mount_point" "$swap_size"
    fi
    
    log_info "Post-configuration complete"
}

install_run() {
    _log_section "Starting Installation"
    
    local start_time
    start_time=$(date +%s)
    
    install_preflight || return 1
    
    install_select_disk || return 1
    
    local efi_size
    efi_size=$(config_get "storage.efi_size_mb" "1024")
    install_partition_disk "$INSTALL_DEVICE" "$efi_size" "quick"
    
    local luks_enabled
    luks_enabled=$(config_get_bool "storage.luks.enabled" false && echo "false" || echo "true")
    install_format_partitions "$INSTALL_EFI_PARTITION" "$INSTALL_ROOT_PARTITION" "$luks_enabled"
    
    install_mount_filesystems "$INSTALL_ROOT_PARTITION" "$INSTALL_EFI_PARTITION"
    
    install_base_system
    install_generate_fstab
    install_configure_system
    install_setup_bootloader "$INSTALL_MOUNT" "$INSTALL_ROOT_PARTITION"
    
    install_create_user
    
    install_post_config
    
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    _log_section "Installation Complete"
    log_info "Duration: ${duration}s"
    log_info "System installed to $INSTALL_MOUNT"
    
    _tui_wait "Press any key to finish..."
}
