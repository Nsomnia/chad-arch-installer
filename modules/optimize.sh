#!/usr/bin/env bash
#
# GLM5 Chad Arch Installer - System Optimization Module
#

set -eo pipefail

if [[ -z "${_OPTIMIZE_LOADED:-}" ]]; then
    readonly _OPTIMIZE_LOADED=1
else
    return 0
fi

detect_cpu_info() {
    local cpu_info="/proc/cpuinfo"
    
    local vendor model cores threads
    vendor=$(grep -m1 "^vendor_id" "$cpu_info" 2>/dev/null | cut -d: -f2 | tr -d ' ')
    model=$(grep -m1 "^model name" "$cpu_info" 2>/dev/null | cut -d: -f2 | sed 's/^[[:space:]]//')
    cores=$(grep "^cpu cores" "$cpu_info" 2>/dev/null | head -1 | cut -d: -f2 | tr -d ' ')
    threads=$(grep "^siblings" "$cpu_info" 2>/dev/null | head -1 | cut -d: -f2 | tr -d ' ')
    
    echo "vendor=$vendor|model=$model|cores=$cores|threads=$threads"
}

detect_cpu_flags() {
    grep -m1 "^flags" /proc/cpuinfo 2>/dev/null | cut -d: -f2
}

detect_cpu_features() {
    local flags
    flags=$(detect_cpu_flags)
    
    local features=()
    
    echo "$flags" | grep -q "sse4_2" && features+=("sse4.2")
    echo "$flags" | grep -q "avx" && features+=("avx")
    echo "$flags" | grep -q "avx2" && features+=("avx2")
    echo "$flags" | grep -q "avx512f" && features+=("avx512")
    echo "$flags" | grep -q "aes" && features+=("aes-ni")
    echo "$flags" | grep -q "sha_ni" && features+=("sha-ni")
    echo "$flags" | grep -q "rdseed" && features+=("rdseed")
    echo "$flags" | grep -q "vmx" && features+=("vt-x")
    echo "$flags" | grep -q "svm" && features+=("amd-v")
    
    echo "${features[*]}"
}

optimize_makepkg_conf() {
    local output_file="${1:-/etc/makepkg.conf.d/99-chad-optimizations.conf}"
    local mount_point="${2:-}"
    
    _log_section "Optimizing makepkg.conf"
    
    if ! declare -f makepkg_generate_conf &>/dev/null; then
        log_error "makepkg library not loaded"
        return 1
    fi
    
    local effective_output="$output_file"
    [[ -n "$mount_point" ]] && effective_output="$mount_point$output_file"
    
    makepkg_generate_conf "$effective_output"
    
    log_info "makepkg.conf optimizations written to $effective_output"
}

optimize_pacman_conf() {
    local output_file="${1:-/etc/pacman.conf}"
    local mount_point="${2:-}"
    
    _log_section "Optimizing pacman.conf"
    
    [[ -n "$mount_point" ]] && output_file="$mount_point$output_file"
    
    local pacman_conf="# Optimized pacman configuration

[options]
HoldPkg     = pacman glibc
Architecture = auto
CheckSpace
Color
ILoveCandy

# Parallel downloads
ParallelDownloads = 5

# Use deltas for small updates
UseDelta    = 0.7

# Misc options
NoProgressBar
VerbosePkgLists

# Signature checking
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist
"
    
    if [[ "$MOCK_MODE" == "true" ]]; then
        mock_write_file "$output_file" "$pacman_conf"
    else
        if [[ -f "$output_file" ]]; then
            cp "$output_file" "${output_file}.bak"
        fi
        echo "$pacman_conf" > "$output_file"
    fi
    
    log_info "pacman.conf optimized"
}

optimize_sysctl() {
    local output_file="${1:-/etc/sysctl.d/99-chad-optimizations.conf}"
    local mount_point="${2:-}"
    
    _log_section "Applying Sysctl Optimizations"
    
    [[ -n "$mount_point" ]] && output_file="$mount_point$output_file"
    
    local sysctl_conf="# GLM5 Chad Arch Installer - Sysctl Optimizations

# Improve file system performance
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 1024

# Improve network performance
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_congestion_control = bbr

# Reduce swap usage
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 20
vm.dirty_background_ratio = 5

# Security hardening
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.unprivileged_bpf_disabled = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Improve desktop responsiveness
kernel.sched_autogroup_enabled = 1
"
    
    mock_write_file "$output_file" "$sysctl_conf"
    
    log_info "Sysctl optimizations applied"
}

optimize_journald() {
    local output_file="${1:-/etc/systemd/journald.conf.d/99-chad.conf}"
    local mount_point="${2:-}"
    
    _log_section "Optimizing Journald"
    
    [[ -n "$mount_point" ]] && output_file="$mount_point$output_file"
    
    local journald_conf="[Journal]
Storage=auto
Compress=yes
Seal=yes
SplitMode=uid
RateLimitIntervalSec=30s
RateLimitBurst=10000
SystemMaxUse=500M
SystemMaxFileSize=50M
MaxRetentionSec=1month
"
    
    mock_write_file "$output_file" "$journald_conf"
    
    log_info "Journald optimized"
}

optimize_systemd_services() {
    local mount_point="${1:-}"
    
    _log_section "Optimizing Systemd Services"
    
    local services_to_disable=(
        "connman.service"
        "ModemManager.service"
        "bluetooth.service"
    )
    
    local services_to_enable=(
        "fstrim.timer"
        "paccache.timer"
        "reflector.timer"
    )
    
    for service in "${services_to_disable[@]}"; do
        log_debug "Would disable: $service"
        mock_cmd "Disable $service" systemctl disable "$service" 2>/dev/null || true
    done
    
    for service in "${services_to_enable[@]}"; do
        log_debug "Would enable: $service"
        mock_cmd "Enable $service" systemctl enable "$service" 2>/dev/null || true
    done
    
    log_info "Systemd services optimized"
}

optimize_zram() {
    local mount_point="${1:-}"
    local config_file="/etc/systemd/zram-generator.conf"
    
    [[ -n "$mount_point" ]] && config_file="$mount_point$config_file"
    
    _log_section "Setting Up ZRAM"
    
    local zram_conf="[zram0]
zram-size = min(ram / 2, 4096)
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
"
    
    mock_write_file "$config_file" "$zram_conf"
    
    log_info "ZRAM configured"
}

optimize_io_scheduler() {
    local mount_point="${1:-}"
    
    _log_section "Setting I/O Scheduler"
    
    local udev_file="/etc/udev/rules.d/60-scheduler.rules"
    [[ -n "$mount_point" ]] && udev_file="$mount_point$udev_file"
    
    local udev_rules='# Set deadline scheduler for NVMe
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"

# Set BFQ scheduler for SSDs and HDDs
ACTION=="add|change", KERNEL=="sd[a-z]|mmcblk[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="bfq"
ACTION=="add|change", KERNEL=="sd[a-z]|mmcblk[0-9]*", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
'
    
    for device in /sys/block/sd* /sys/block/nvme* /sys/block/mmcblk*; do
        if [[ -d "$device" ]]; then
            local dev_name
            dev_name=$(basename "$device")
            
            if [[ "$dev_name" =~ ^nvme ]]; then
                log_debug "NVMe device $dev_name - using none scheduler"
                echo "none" > "$device/queue/scheduler" 2>/dev/null || true
            else
                log_debug "Block device $dev_name - using bfq scheduler"
                echo "bfq" > "$device/queue/scheduler" 2>/dev/null || true
            fi
        fi
    done
    
    mock_write_file "$udev_file" "$udev_rules"
    
    log_info "I/O schedulers configured and persisted via udev"
}

optimize_all() {
    local mount_point="${1:-}"
    
    _log_section "Full System Optimization"
    
    log_info "Detecting CPU capabilities..."
    local cpu_info
    cpu_info=$(detect_cpu_info)
    
    local vendor model cores threads
    for part in $cpu_info; do
        case "$part" in
            vendor=*) vendor="${part#vendor=}" ;;
            model=*) model="${part#model=}" ;;
            cores=*) cores="${part#cores=}" ;;
            threads=*) threads="${part#threads=}" ;;
        esac
    done
    
    _tui_header "CPU Information"
    echo "  Vendor:  ${vendor:-unknown}"
    echo "  Model:   ${model:-unknown}"
    echo "  Cores:   ${cores:-unknown}"
    echo "  Threads: ${threads:-unknown}"
    echo "  Features: $(detect_cpu_features)"
    
    if declare -f makepkg_get_cpu_march &>/dev/null; then
        echo "  March:    $(makepkg_get_cpu_march)"
        echo "  Jobs:     $(makepkg_get_parallel_jobs)"
        echo "  Linker:   $(makepkg_detect_linker)"
    fi
    echo ""
    
    optimize_makepkg_conf "/etc/makepkg.conf.d/99-chad-optimizations.conf" "$mount_point"
    optimize_pacman_conf "/etc/pacman.conf" "$mount_point"
    optimize_sysctl "/etc/sysctl.d/99-chad-optimizations.conf" "$mount_point"
    optimize_journald "/etc/systemd/journald.conf.d/99-chad.conf" "$mount_point"
    optimize_zram "$mount_point"
    optimize_io_scheduler "$mount_point"
    
    _log_section "Optimization Complete"
}

optimize_interactive() {
    _tui_header "Optimization Menu"
    
    local options=(
        "Full Optimization"
        "makepkg.conf Only"
        "makepkg Configuration Menu"
        "pacman.conf Only"
        "Sysctl Only"
        "Journald Only"
        "ZRAM Setup"
        "I/O Schedulers"
        "Show CPU Info"
        "Back"
    )
    
    while true; do
        local choice
        choice=$(_tui_menu_select "Optimization Options:" "${options[@]}")
        
        case "$choice" in
            "Full Optimization") optimize_all ;;
            "makepkg.conf Only") optimize_makepkg_conf ;;
            "makepkg Configuration Menu")
                if declare -f makepkg_menu &>/dev/null; then
                    makepkg_menu
                else
                    log_error "makepkg library not loaded"
                fi
                ;;
            "pacman.conf Only") optimize_pacman_conf ;;
            "Sysctl Only") optimize_sysctl ;;
            "Journald Only") optimize_journald ;;
            "ZRAM Setup") optimize_zram ;;
            "I/O Schedulers") optimize_io_scheduler ;;
            "Show CPU Info")
                local cpu_info
                cpu_info=$(detect_cpu_info)
                _tui_header "CPU Information"
                for part in $cpu_info; do
                    local key="${part%%=*}"
                    local value="${part#*=}"
                    printf "  %-10s: %s\n" "$key" "$value"
                done
                echo ""
                echo "Features: $(detect_cpu_features)"
                if declare -f makepkg_get_cpu_march &>/dev/null; then
                    echo ""
                    echo "Makepkg Settings:"
                    echo "  March:  $(makepkg_get_cpu_march)"
                    echo "  Jobs:   $(makepkg_get_parallel_jobs)"
                    echo "  Linker: $(makepkg_detect_linker)"
                fi
                ;;
            "Back") return 0 ;;
        esac
        
        _tui_wait
    done
}
