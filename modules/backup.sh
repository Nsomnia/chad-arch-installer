#!/usr/bin/env bash
#
# GLM5 Chad Arch Installer - Backup and Restore Module
#

set -eo pipefail

if [[ -z "${_BACKUP_LOADED:-}" ]]; then
    readonly _BACKUP_LOADED=1
else
    return 0
fi

BACKUP_DIR="${BACKUP_DIR:-/backup}"
BACKUP_DATE="$(date +%Y%m%d_%H%M%S)"
BACKUP_PREFIX="chad-backup-${BACKUP_DATE}"

declare -a BACKUP_PATHS=(
    "/etc"
    "/root"
    "/home"
    "/var/lib/pacman"
    "/usr/local/bin"
)

declare -a BACKUP_PACKAGE_FILES=(
    "/var/lib/pacman/local"
)

backup_create_dir() {
    local backup_dir="${1:-$BACKUP_DIR}"
    
    if [[ ! -d "$backup_dir" ]]; then
        log_info "Creating backup directory: $backup_dir"
        mkdir -p "$backup_dir"
    fi
}

backup_packages() {
    local output_dir="${1:-$BACKUP_DIR}"
    local output_file="$output_dir/${BACKUP_PREFIX}-packages.txt"
    
    _log_section "Backing Up Package List"
    
    backup_create_dir "$output_dir"
    
    log_info "Exporting explicit packages..."
    pacman -Qqe > "$output_file.explicit" 2>/dev/null || true
    
    log_info "Exporting all packages..."
    pacman -Qq > "$output_file.all" 2>/dev/null || true
    
    log_info "Exporting foreign packages (AUR)..."
    pacman -Qqm > "$output_file.aur" 2>/dev/null || true
    
    log_info "Exporting package information..."
    pacman -Qi > "$output_file.info" 2>/dev/null || true
    
    log_info "Package lists saved to $output_file.*"
}

backup_pacman_database() {
    local output_dir="${1:-$BACKUP_DIR}"
    local output_file="$output_dir/${BACKUP_PREFIX}-pacman-db.tar.zst"
    
    _log_section "Backing Up Pacman Database"
    
    backup_create_dir "$output_dir"
    
    local compress_flag="--zstd"
    if ! command -v zstd &>/dev/null; then
        compress_flag="-z"
        output_file="$output_dir/${BACKUP_PREFIX}-pacman-db.tar.gz"
        log_warn "zstd not available, using gzip compression"
    fi
    
    log_info "Creating pacman database backup..."
    tar $compress_flag -cf "$output_file" -C /var/lib/pacman local 2>/dev/null || {
        log_error "Failed to backup pacman database"
        return 1
    }
    
    log_info "Pacman database saved to $output_file"
}

backup_gpg_keys() {
    local output_dir="${1:-$BACKUP_DIR}"
    local output_file="$output_dir/${BACKUP_PREFIX}-gpg-keys"
    
    _log_section "Backing Up GPG Keys"
    
    backup_create_dir "$output_dir"
    
    log_info "Exporting GPG public keys..."
    gpg --armor --export > "$output_file.public.asc" 2>/dev/null || true
    
    log_info "Exporting GPG private keys..."
    gpg --armor --export-secret-keys > "$output_file.private.asc" 2>/dev/null || true
    
    log_info "Exporting GPG ownertrust..."
    gpg --export-ownertrust > "$output_file.trust.txt" 2>/dev/null || true
    
    log_info "GPG keys saved to $output_file.*"
}

backup_ssh_keys() {
    local output_dir="${1:-$BACKUP_DIR}"
    local ssh_dir="${HOME}/.ssh"
    local compress_ext=".tar.zst"
    local compress_flag="--zstd"
    
    _log_section "Backing Up SSH Keys"
    
    if [[ ! -d "$ssh_dir" ]]; then
        log_warn "SSH directory not found: $ssh_dir"
        return 0
    fi
    
    backup_create_dir "$output_dir"
    
    if ! command -v zstd &>/dev/null; then
        compress_ext=".tar.gz"
        compress_flag="-z"
        log_warn "zstd not available, using gzip compression"
    fi
    
    local output_file="$output_dir/${BACKUP_PREFIX}-ssh-keys${compress_ext}"
    
    log_info "Archiving SSH directory..."
    tar $compress_flag -cf "$output_file" -C "$ssh_dir" . 2>/dev/null || {
        log_error "Failed to backup SSH keys"
        return 1
    }
    
    log_info "SSH keys saved to $output_file"
}

backup_git_config() {
    local output_dir="${1:-$BACKUP_DIR}"
    local output_file="$output_dir/${BACKUP_PREFIX}-git-config"
    
    _log_section "Backing Up Git Configuration"
    
    backup_create_dir "$output_dir"
    
    log_info "Exporting git config..."
    git config --global --list > "$output_file.txt" 2>/dev/null || true
    
    log_info "Copying .gitconfig..."
    cp "${HOME}/.gitconfig" "$output_file" 2>/dev/null || true
    
    log_info "Git configuration saved"
}

backup_custom_paths() {
    local output_dir="${1:-$BACKUP_DIR}"
    local paths=("${@:2}")
    
    _log_section "Backing Up Custom Paths"
    
    backup_create_dir "$output_dir"
    
    local compress_ext=".tar.zst"
    local compress_flag="--zstd"
    
    if ! command -v zstd &>/dev/null; then
        compress_ext=".tar.gz"
        compress_flag="-z"
    fi
    
    for path in "${paths[@]}"; do
        if [[ -e "$path" ]]; then
            local name
            name=$(basename "$path")
            local safe_name="${name//\//-}"
            local output_file="$output_dir/${BACKUP_PREFIX}-custom-${safe_name}${compress_ext}"
            
            log_info "Backing up: $path"
            
            if [[ -d "$path" ]]; then
                tar $compress_flag -cf "$output_file" -C "$(dirname "$path")" "$name"
            else
                tar $compress_flag -cf "$output_file" -C "$(dirname "$path")" "$name"
            fi
        else
            log_warn "Path not found: $path"
        fi
    done
}

backup_usr_local_bin() {
    local output_dir="${1:-$BACKUP_DIR}"
    local bin_dir="/usr/local/bin"
    
    _log_section "Backing Up /usr/local/bin"
    
    if [[ ! -d "$bin_dir" ]] || [[ -z "$(ls -A "$bin_dir" 2>/dev/null)" ]]; then
        log_info "/usr/local/bin is empty or doesn't exist, skipping"
        return 0
    fi
    
    backup_create_dir "$output_dir"
    
    local compress_ext=".tar.zst"
    local compress_flag="--zstd"
    
    if ! command -v zstd &>/dev/null; then
        compress_ext=".tar.gz"
        compress_flag="-z"
    fi
    
    local output_file="$output_dir/${BACKUP_PREFIX}-usr-local-bin${compress_ext}"
    
    log_info "Archiving /usr/local/bin..."
    tar $compress_flag -cf "$output_file" -C "$bin_dir" . 2>/dev/null || {
        log_error "Failed to backup /usr/local/bin"
        return 1
    }
    
    log_info "/usr/local/bin saved to $output_file"
}

backup_full() {
    local output_dir="${1:-$BACKUP_DIR}"
    
    _log_section "Full Backup"
    
    backup_create_dir "$output_dir"
    
    backup_packages "$output_dir"
    backup_pacman_database "$output_dir"
    backup_gpg_keys "$output_dir"
    backup_ssh_keys "$output_dir"
    backup_git_config "$output_dir"
    backup_usr_local_bin "$output_dir"
    
    local manifest="$output_dir/${BACKUP_PREFIX}-manifest.txt"
    {
        echo "GLM5 Chad Arch Installer - Backup Manifest"
        echo "Date: $(date)"
        echo "Hostname: $(hostname)"
        echo ""
        echo "Files in this backup:"
        ls -la "$output_dir"/${BACKUP_PREFIX}* 2>/dev/null
    } > "$manifest"
    
    log_info "Backup complete. Files in $output_dir"
    log_info "Manifest: $manifest"
}

restore_packages() {
    local backup_dir="${1:-$BACKUP_DIR}"
    local package_file="$backup_dir"
    
    _log_section "Restoring Packages"
    
    if [[ -f "${package_file}-packages.txt.all" ]]; then
        log_info "Restoring from package list..."
        mock_cmd "Install packages" pacman -S --needed - < "${package_file}-packages.txt.all"
    else
        log_error "Package list not found"
        return 1
    fi
}

restore_pacman_database() {
    local backup_dir="${1:-$BACKUP_DIR}"
    local db_file
    db_file=$(ls "$backup_dir"/*-pacman-db.tar.* 2>/dev/null | head -1)
    
    _log_section "Restoring Pacman Database"
    
    if [[ -z "$db_file" ]]; then
        log_error "Pacman database backup not found"
        return 1
    fi
    
    log_info "Restoring from $db_file"
    
    local decompress_flag=""
    if [[ "$db_file" == *.zst ]]; then
        decompress_flag="--zstd"
    elif [[ "$db_file" == *.gz ]]; then
        decompress_flag="-z"
    fi
    
    tar $decompress_flag -xf "$db_file" -C /var/lib/pacman/ 2>/dev/null || {
        log_error "Failed to restore pacman database"
        return 1
    }
    
    log_info "Pacman database restored"
}

restore_ssh_keys() {
    local backup_dir="${1:-$BACKUP_DIR}"
    local ssh_file
    ssh_file=$(ls "$backup_dir"/*-ssh-keys.tar.* 2>/dev/null | head -1)
    
    _log_section "Restoring SSH Keys"
    
    if [[ -z "$ssh_file" ]]; then
        log_error "SSH key backup not found"
        return 1
    fi
    
    mkdir -p "${HOME}/.ssh"
    chmod 700 "${HOME}/.ssh"
    
    log_info "Extracting SSH keys..."
    
    local decompress_flag=""
    if [[ "$ssh_file" == *.zst ]]; then
        decompress_flag="--zstd"
    elif [[ "$ssh_file" == *.gz ]]; then
        decompress_flag="-z"
    fi
    
    tar $decompress_flag -xf "$ssh_file" -C "${HOME}/.ssh" 2>/dev/null || {
        log_error "Failed to restore SSH keys"
        return 1
    }
    
    chmod 600 "${HOME}/.ssh/"* 2>/dev/null || true
    chmod 644 "${HOME}/.ssh/"*.pub 2>/dev/null || true
    
    log_info "SSH keys restored"
}

restore_gpg_keys() {
    local backup_dir="${1:-$BACKUP_DIR}"
    local key_prefix
    key_prefix=$(ls "$backup_dir"/*-gpg-keys.public.asc 2>/dev/null | head -1)
    key_prefix="${key_prefix%.public.asc}"
    
    _log_section "Restoring GPG Keys"
    
    if [[ -z "$key_prefix" ]]; then
        log_error "GPG key backup not found"
        return 1
    fi
    
    log_info "Importing GPG public keys..."
    gpg --import "${key_prefix}.public.asc" 2>/dev/null || true
    
    if [[ -f "${key_prefix}.private.asc" ]]; then
        log_info "Importing GPG private keys..."
        gpg --import "${key_prefix}.private.asc" 2>/dev/null || true
    fi
    
    if [[ -f "${key_prefix}.trust.txt" ]]; then
        log_info "Restoring GPG ownertrust..."
        gpg --import-ownertrust "${key_prefix}.trust.txt" 2>/dev/null || true
    fi
    
    log_info "GPG keys restored"
}

restore_ssh_keys() {
    local backup_dir="${1:-$BACKUP_DIR}"
    local ssh_file
    ssh_file=$(ls "$backup_dir"/*-ssh-keys.tar.zst 2>/dev/null | head -1)
    
    _log_section "Restoring SSH Keys"
    
    if [[ -z "$ssh_file" ]]; then
        log_error "SSH key backup not found"
        return 1
    fi
    
    mkdir -p "${HOME}/.ssh"
    chmod 700 "${HOME}/.ssh"
    
    log_info "Extracting SSH keys..."
    tar --zstd -xf "$ssh_file" -C "${HOME}/.ssh" 2>/dev/null || {
        log_error "Failed to restore SSH keys"
        return 1
    }
    
    chmod 600 "${HOME}/.ssh/"* 2>/dev/null || true
    chmod 644 "${HOME}/.ssh/"*.pub 2>/dev/null || true
    
    log_info "SSH keys restored"
}

backup_select_paths() {
    _log_section "Select Paths to Backup"
    
    local common_paths=(
        "/etc"
        "/root"
        "/home"
        "/var/lib/pacman"
        "/usr/local/bin"
        "/opt"
        "/srv"
    )
    
    local selected
    mapfile -t selected < <(_tui_menu_multi "Select paths to backup:" "${common_paths[@]}")
    
    if [[ ${#selected[@]} -gt 0 ]]; then
        backup_custom_paths "$BACKUP_DIR" "${selected[@]}"
    else
        log_info "No paths selected for backup"
    fi
}

backup_interactive() {
    _tui_header "Backup Menu"
    
    local options=(
        "Full Backup"
        "Package Lists Only"
        "Pacman Database"
        "GPG Keys"
        "SSH Keys"
        "Git Configuration"
        "/usr/local/bin"
        "Custom Paths"
        "Select Paths Interactively"
        "Back"
    )
    
    while true; do
        local choice
        choice=$(_tui_menu_select "Backup Options:" "${options[@]}")
        
        case "$choice" in
            "Full Backup") backup_full ;;
            "Package Lists Only") backup_packages ;;
            "Pacman Database") backup_pacman_database ;;
            "GPG Keys") backup_gpg_keys ;;
            "SSH Keys") backup_ssh_keys ;;
            "Git Configuration") backup_git_config ;;
            "/usr/local/bin") backup_usr_local_bin ;;
            "Custom Paths")
                local paths=$(_tui_input "Enter paths (space-separated)")
                backup_custom_paths "$BACKUP_DIR" $paths
                ;;
            "Select Paths Interactively") backup_select_paths ;;
            "Back") return 0 ;;
        esac
        
        _tui_wait
    done
}

restore_interactive() {
    _tui_header "Restore Menu"
    
    local options=(
        "Packages"
        "Pacman Database"
        "GPG Keys"
        "SSH Keys"
        "Back"
    )
    
    while true; do
        local choice
        choice=$(_tui_menu_select "Restore Options:" "${options[@]}")
        
        case "$choice" in
            "Packages") restore_packages ;;
            "Pacman Database") restore_pacman_database ;;
            "GPG Keys") restore_gpg_keys ;;
            "SSH Keys") restore_ssh_keys ;;
            "Back") return 0 ;;
        esac
        
        _tui_wait
    done
}
