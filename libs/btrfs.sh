#!/usr/bin/env bash
#
# GLM5 Chad Arch Installer - BTRFS Utilities
#

set -eo pipefail

if [[ -z "${_BTRFS_LOADED:-}" ]]; then
    readonly _BTRFS_LOADED=1
else
    return 0
fi

BTRFS_DEFAULT_COMPRESS="${BTRFS_DEFAULT_COMPRESS:-zstd:3}"
BTRFS_DEFAULT_MOUNT_OPTS="${BTRFS_DEFAULT_MOUNT_OPTS:-noatime,compress=__COMPRESS__,commit=120}"

declare -a BTRFS_SUBVOLUMES=(
    "@:/"
    "@home:/home"
    "@root:/root"
    "@srv:/srv"
    "@var:/var"
    "@var_log:/var/log"
    "@var_cache:/var/cache"
    "@var_tmp:/var/tmp"
    "@var_lib:/var/lib"
    "@snapshots:/.snapshots"
    "@home_snapshots:/home/.snapshots"
)

declare -a BTRFS_NOCOW_SUBVOLUMES=(
    "@var"
    "@var_cache"
    "@var_tmp"
)

btrfs_create_subvolume() {
    local mount_point="$1"
    local subvol_name="$2"
    
    log_info "Creating BTRFS subvolume: $subvol_name at $mount_point"
    
    mock_cmd "Create subvolume $subvol_name" btrfs subvolume create "$mount_point/$subvol_name"
}

btrfs_delete_subvolume() {
    local mount_point="$1"
    local subvol_name="$2"
    
    log_info "Deleting BTRFS subvolume: $subvol_name"
    
    mock_cmd "Delete subvolume $subvol_name" btrfs subvolume delete "$mount_point/$subvol_name"
}

btrfs_snapshot() {
    local source="$1"
    local dest="$2"
    local readonly="${3:-false}"
    
    local cmd="btrfs subvolume snapshot"
    $readonly && cmd+=" -r"
    cmd+=" $source $dest"
    
    log_info "Creating snapshot: $dest from $source"
    
    if [[ "$MOCK_MODE" == "true" ]]; then
        mock_cmd "Create snapshot" $cmd
    else
        eval "$cmd"
    fi
}

btrfs_send_receive() {
    local snapshot="$1"
    local dest_dir="$2"
    
    log_info "Sending snapshot $snapshot to $dest_dir"
    
    if [[ "$MOCK_MODE" == "true" ]]; then
        mock_cmd "Send snapshot" btrfs send "$snapshot"
        mock_cmd "Receive snapshot" btrfs receive "$dest_dir"
    else
        btrfs send "$snapshot" | btrfs receive "$dest_dir"
    fi
}

btrfs_get_subvolid() {
    local mount_point="$1"
    local subvol_name="$2"
    
    local subvol_path="$mount_point/$subvol_name"
    
    if [[ -d "$subvol_path" ]]; then
        btrfs subvolume show "$subvol_path" 2>/dev/null | grep "Subvolume ID:" | awk '{print $3}'
    fi
}

btrfs_set_default_subvolume() {
    local mount_point="$1"
    local subvol_name="$2"
    
    local subvol_id
    subvol_id=$(btrfs_get_subvolid "$mount_point" "$subvol_name")
    
    if [[ -n "$subvol_id" ]]; then
        log_info "Setting default subvolume to $subvol_name (ID: $subvol_id)"
        mock_cmd "Set default subvolume" btrfs subvolume set-default "$subvol_id" "$mount_point"
    fi
}

btrfs_is_nocow() {
    local subvol_name="$1"
    
    for nocow in "${BTRFS_NOCOW_SUBVOLUMES[@]}"; do
        [[ "$nocow" == "$subvol_name" ]] && return 0
    done
    return 1
}

btrfs_get_mount_opts() {
    local compress="${1:-$BTRFS_DEFAULT_COMPRESS}"
    local subvol_name="${2:-}"
    
    local opts="${BTRFS_DEFAULT_MOUNT_OPTS/__COMPRESS__/$compress}"
    
    if btrfs_is_nocow "$subvol_name"; then
        opts+=",nodatacow"
    fi
    
    echo "$opts"
}

btrfs_create_layout() {
    local device="$1"
    local mount_point="${2:-/mnt}"
    local compress="${3:-$BTRFS_DEFAULT_COMPRESS}"
    
    _log_section "Creating BTRFS Layout"
    
    log_info "Mounting BTRFS root at $mount_point"
    
    if [[ "$MOCK_MODE" == "true" ]]; then
        mkdir -p "$MOCK_ROOT$mount_point"
    else
        mount -t btrfs -o subvolid=5 "$device" "$mount_point"
    fi
    
    for entry in "${BTRFS_SUBVOLUMES[@]}"; do
        local subvol_name="${entry%%:*}"
        local subvol_mount="${entry#*:}"
        
        btrfs_create_subvolume "$mount_point" "$subvol_name"
        
        if btrfs_is_nocow "$subvol_name"; then
            log_debug "Setting NoCOW attribute on $subvol_name"
            if [[ "$MOCK_MODE" != "true" ]]; then
                chattr +C "$mount_point/$subvol_name" 2>/dev/null || true
            fi
        fi
    done
    
    if [[ "$MOCK_MODE" != "true" ]]; then
        umount "$mount_point"
    fi
    
    log_info "BTRFS layout created successfully"
}

btrfs_mount_subvolumes() {
    local device="$1"
    local mount_point="${2:-/mnt}"
    local compress="${3:-$BTRFS_DEFAULT_COMPRESS}"
    
    _log_section "Mounting BTRFS Subvolumes"
    
    local root_opts
    root_opts=$(btrfs_get_mount_opts "$compress" "@")
    root_opts="subvol=/@,$root_opts"
    
    log_info "Mounting root subvolume"
    mock_cmd "Mount root" mount -t btrfs -o "$root_opts" "$device" "$mount_point"
    
    for entry in "${BTRFS_SUBVOLUMES[@]:1}"; do
        local subvol_name="${entry%%:*}"
        local subvol_mount="${entry#*:}"
        
        local subvol_path="$mount_point$subvol_mount"
        mkdir -p "$subvol_path"
        
        local opts
        opts=$(btrfs_get_mount_opts "$compress" "$subvol_name")
        opts="subvol=/$subvol_name,$opts"
        
        log_info "Mounting $subvol_name at $subvol_mount"
        mock_cmd "Mount $subvol_name" mount -t btrfs -o "$opts" "$device" "$subvol_path"
    done
    
    log_info "All subvolumes mounted"
}

btrfs_create_swapfile() {
    local mount_point="${1:-/mnt}"
    local size_mb="${2:-4096}"
    local swap_path="${3:-/.swap/swapfile}"
    
    _log_section "Creating Swapfile"
    
    local full_path="$mount_point$swap_path"
    local swap_dir
    swap_dir=$(dirname "$full_path")
    
    mkdir -p "$swap_dir"
    
    log_info "Creating $size_mb MB swapfile at $swap_path"
    
    if [[ "$MOCK_MODE" == "true" ]]; then
        mock_cmd "Create swapfile" truncate -s "${size_mb}M" "$full_path"
        mock_cmd "Set NoCOW" chattr +C "$full_path"
        mock_cmd "Set permissions" chmod 600 "$full_path"
        mock_cmd "Format swap" mkswap "$full_path"
    else
        truncate -s "${size_mb}M" "$full_path"
        chattr +C "$full_path" 2>/dev/null || true
        chmod 600 "$full_path"
        mkswap "$full_path"
    fi
    
    log_info "Swapfile created"
}

btrfs_list_snapshots() {
    local mount_point="${1:-/}"
    
    btrfs subvolume list -s "$mount_point" 2>/dev/null | while read -r line; do
        local id parent path
        read -r _ id _ parent _ _ _ path <<< "$line"
        echo "ID: $id | Parent: $parent | Path: $path"
    done
}

btrfs_scrub_start() {
    local mount_point="${1:-/}"
    
    log_info "Starting BTRFS scrub on $mount_point"
    mock_cmd "Start scrub" btrfs scrub start "$mount_point"
}

btrfs_scrub_status() {
    local mount_point="${1:-/}"
    
    btrfs scrub status "$mount_point" 2>/dev/null
}

btrfs_balance_start() {
    local mount_point="${1:-/}"
    local usage="${2:-50}"
    
    log_info "Starting BTRFS balance on $mount_point (usage < $usage%)"
    mock_cmd "Start balance" btrfs balance start -dusage="$usage" "$mount_point"
}

btrfs_get_usage() {
    local mount_point="${1:-/}"
    
    btrfs filesystem df "$mount_point" 2>/dev/null
}

btrfs_compress_test() {
    local file="$1"
    
    log_info "Testing compression algorithms on $file"
    
    local algorithms=("zstd:1" "zstd:3" "zstd:6" "zstd:10" "lzo" "lz4")
    
    for algo in "${algorithms[@]}"; do
        local size
        size=$(btrfs property get "$file" compression 2>/dev/null || echo "N/A")
        log_debug "Algorithm: $algo -> Size would be calculated"
    done
}

btrfs_defragment() {
    local path="$1"
    local compress="${2:-$BTRFS_DEFAULT_COMPRESS}"
    
    log_info "Defragmenting $path with $compress compression"
    mock_cmd "Defragment" btrfs filesystem defragment -r -c "$compress" "$path"
}

btrfs_quota_enable() {
    local mount_point="${1:-/}"
    
    log_info "Enabling BTRFS quotas on $mount_point"
    mock_cmd "Enable quota" btrfs quota enable "$mount_point"
}

btrfs_quota_disable() {
    local mount_point="${1:-/}"
    
    log_info "Disabling BTRFS quotas on $mount_point"
    mock_cmd "Disable quota" btrfs quota disable "$mount_point"
}

btrfs_get_default_layout() {
    echo "Standard BTRFS subvolume layout:"
    echo ""
    for entry in "${BTRFS_SUBVOLUMES[@]}"; do
        local subvol_name="${entry%%:*}"
        local subvol_mount="${entry#*:}"
        local nocow=""
        btrfs_is_nocow "$subvol_name" && nocow=" [NoCOW]"
        printf "  %-20s -> %s%s\n" "$subvol_name" "$subvol_mount" "$nocow"
    done
}

btrfs_validate_device() {
    local device="$1"
    
    if [[ ! -b "$device" ]]; then
        log_error "Device $device does not exist"
        return 1
    fi
    
    if [[ "$MOCK_MODE" == "true" ]]; then
        return 0
    fi
    
    if ! btrfs filesystem show "$device" &>/dev/null; then
        log_error "Device $device is not a BTRFS filesystem"
        return 1
    fi
    
    return 0
}

btrfs_get_uuid() {
    local device="$1"
    
    if [[ "$MOCK_MODE" == "true" ]]; then
        echo "mock-uuid-$(date +%s)"
    else
        blkid -s UUID -o value "$device"
    fi
}
