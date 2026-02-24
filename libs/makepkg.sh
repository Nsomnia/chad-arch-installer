#!/usr/bin/env bash
#
# GLM5 Chad Arch Installer - Makepkg Configuration Library
#
# Handles /etc/makepkg.conf and /etc/makepkg.conf.d/ management
# with CPU-specific optimizations and profile support
#

set -eo pipefail

if [[ -z "${_MAKEPKG_LOADED:-}" ]]; then
    readonly _MAKEPKG_LOADED=1
else
    return 0
fi

MAKEPKG_CONF="${MAKEPKG_CONF:-/etc/makepkg.conf}"
MAKEPKG_CONF_DIR="${MAKEPKG_CONF_DIR:-/etc/makepkg.conf.d}"
MAKEPKG_PROFILE_DIR="${MAKEPKG_PROFILE_DIR:-${SCRIPT_DIR}/../profiles/makepkg}"

declare -A MAKEPKG_OPTIMIZATIONS=(
    [native]="-march=native -mtune=native -O2 -pipe -fno-plt -fexceptions"
    [x86-64]="-march=x86-64 -mtune=generic -O2 -pipe -fno-plt -fexceptions"
    [x86-64-v2]="-march=x86-64-v2 -mtune=generic -O2 -pipe -fno-plt -fexceptions"
    [x86-64-v3]="-march=x86-64-v3 -mtune=generic -O2 -pipe -fno-plt -fexceptions"
    [x86-64-v4]="-march=x86-64-v4 -mtune=generic -O2 -pipe -fno-plt -fexceptions"
    [znver2]="-march=znver2 -mtune=znver2 -O2 -pipe -fno-plt -fexceptions"
    [znver3]="-march=znver3 -mtune=znver3 -O2 -pipe -fno-plt -fexceptions"
    [znver4]="-march=znver4 -mtune=znver4 -O2 -pipe -fno-plt -fexceptions"
)

declare -A MAKEPKG_LINKER_FLAGS=(
    [mold]="-fuse-ld=mold"
    [lld]="-fuse-ld=lld"
    [gold]="-fuse-ld=gold"
    [bfd]=""
)

makepkg_get_cpu_march() {
    local cpu_info vendor model flags
    
    cpu_info=$(grep -m1 "^vendor_id" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | tr -d ' ')
    vendor="${cpu_info:-unknown}"
    
    model=$(grep -m1 "^model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^[[:space:]]//')
    flags=$(grep -m1 "^flags" /proc/cpuinfo 2>/dev/null | cut -d: -f2)
    
    local has_avx2=0
    local has_avx512=0
    local has_sse4_2=0
    
    echo "$flags" | grep -q "avx2" && has_avx2=1
    echo "$flags" | grep -qE "avx512f|avx512dq|avx512cd|avx512bw|avx512vl" && has_avx512=1
    echo "$flags" | grep -q "sse4_2" && has_sse4_2=1
    
    case "$vendor" in
        GenuineIntel)
            if [[ $has_avx512 -eq 1 ]]; then
                echo "x86-64-v4"
            elif [[ $has_avx2 -eq 1 ]]; then
                echo "x86-64-v3"
            elif [[ $has_sse4_2 -eq 1 ]]; then
                echo "x86-64-v2"
            else
                echo "x86-64"
            fi
            ;;
        AuthenticAMD)
            if echo "$model" | grep -qiE "Ryzen.*9[89]|EPYC.*[89]"; then
                echo "znver4"
            elif echo "$model" | grep -qiE "Ryzen.*[56]|EPYC.*[67]"; then
                echo "znver3"
            elif echo "$model" | grep -qiE "Ryzen|EPYC"; then
                echo "znver2"
            elif [[ $has_avx2 -eq 1 ]]; then
                echo "x86-64-v3"
            else
                echo "native"
            fi
            ;;
        *)
            if [[ $has_avx2 -eq 1 ]]; then
                echo "x86-64-v3"
            else
                echo "native"
            fi
            ;;
    esac
}

makepkg_get_parallel_jobs() {
    local cores threads
    
    cores=$(grep "^cpu cores" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | tr -d ' ')
    threads=$(grep "^siblings" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | tr -d ' ')
    
    cores="${cores:-1}"
    threads="${threads:-$cores}"
    
    echo $((cores + 1))
}

makepkg_detect_linker() {
    if command -v mold &>/dev/null; then
        echo "mold"
    elif command -v ld.lld &>/dev/null; then
        echo "lld"
    elif command -v ld.gold &>/dev/null; then
        echo "gold"
    else
        echo "bfd"
    fi
}

makepkg_has_lto_support() {
    if command -v gcc &>/dev/null; then
        gcc -v 2>&1 | grep -q -- "--enable-lto" && return 0
    fi
    return 1
}

makepkg_has_pgo_support() {
    if command -v gcc &>/dev/null; then
        gcc -v 2>&1 | grep -q "profile-guided" && return 0
    fi
    return 1
}

makepkg_get_cflags() {
    local march="${1:-$(makepkg_get_cpu_march)}"
    local enable_lto="${2:-true}"
    local enable_pgo="${3:-false}"
    
    local cflags="${MAKEPKG_OPTIMIZATIONS[$march]:-${MAKEPKG_OPTIMIZATIONS[native]}}"
    
    if [[ "$enable_lto" == "true" ]] && makepkg_has_lto_support; then
        cflags+=" -flto=auto"
    fi
    
    if [[ "$enable_pgo" == "true" ]] && makepkg_has_pgo_support; then
        cflags+=" -fprofile-generate -fprofile-use"
    fi
    
    echo "$cflags"
}

makepkg_get_cxxflags() {
    makepkg_get_cflags "$@"
}

makepkg_get_ldflags() {
    local linker="${1:-$(makepkg_detect_linker)}"
    
    echo "${MAKEPKG_LINKER_FLAGS[$linker]:-}"
}

makepkg_get_rustflags() {
    local march="${1:-$(makepkg_get_cpu_march)}"
    
    case "$march" in
        native|x86-64-v3|x86-64-v4|znver2|znver3|znver4)
            echo "-C target-cpu=native -C opt-level=3"
            ;;
        *)
            echo "-C opt-level=3"
            ;;
    esac
}

makepkg_get_compress_settings() {
    local threads="${1:-0}"
    local zstd_level="${2:-19}"
    local xz_level="${3:-6}"
    
    cat <<EOF
COMPRESSZST=(zstd -c -z -q - --threads=$threads -$zstd_level)
COMPRESSXZ=(xz -c -z - --threads=$threads -$xz_level)
COMPRESSZ=(compress -c -f)
COMPRESSGZ=(gzip -c -f -n)
COMPRESSBZ2=(bzip2 -c -f)
COMPRESSLRZ=(lrzip -q)
COMPRESSLZO=(lzop -q)
COMPRESSZST=(zstd -q -T$threads -$zstd_level)
COMPRESSLZ4=(lz4 -q)
COMPRESSLZ=(lzip -c -f)
EOF
}

makepkg_backup_config() {
    local config_file="${1:-$MAKEPKG_CONF}"
    local backup_dir="${2:-/var/backups/chad-installer}"
    local timestamp
    
    timestamp=$(date +%Y%m%d_%H%M%S)
    mkdir -p "$backup_dir"
    
    if [[ -f "$config_file" ]]; then
        cp "$config_file" "$backup_dir/makepkg.conf.$timestamp"
        log_info "Backup created: $backup_dir/makepkg.conf.$timestamp"
        echo "$backup_dir/makepkg.conf.$timestamp"
    fi
}

makepkg_restore_config() {
    local backup_file="$1"
    local config_file="${2:-$MAKEPKG_CONF}"
    
    if [[ -f "$backup_file" ]]; then
        cp "$backup_file" "$config_file"
        log_info "Restored makepkg.conf from: $backup_file"
        return 0
    else
        log_error "Backup file not found: $backup_file"
        return 1
    fi
}

makepkg_parse_config() {
    local config_file="${1:-$MAKEPKG_CONF}"
    
    declare -A config=()
    
    if [[ ! -f "$config_file" ]]; then
        log_error "Config file not found: $config_file"
        return 1
    fi
    
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            value="${value#\"}"
            value="${value%\"}"
            config["$key"]="$value"
        fi
    done < "$config_file"
    
    for key in "${!config[@]}"; do
        echo "$key=${config[$key]}"
    done
}

makepkg_generate_conf() {
    local output_file="${1:-}"
    local march="${2:-$(makepkg_get_cpu_march)}"
    local linker="${3:-$(makepkg_detect_linker)}"
    local jobs="${4:-$(makepkg_get_parallel_jobs)}"
    local enable_lto="${5:-true}"
    
    local cflags cxxflags ldflags rustflags
    
    cflags=$(makepkg_get_cflags "$march" "$enable_lto")
    cxxflags=$(makepkg_get_cxxflags "$march" "$enable_lto")
    ldflags=$(makepkg_get_ldflags "$linker")
    rustflags=$(makepkg_get_rustflags "$march")
    
    local conf="# Generated by GLM5 Chad Arch Installer
# Architecture: $march
# Linker: $linker
# Parallel Jobs: $jobs
# LTO: $enable_lto

# Parallel compilation
MAKEFLAGS=\"-j$jobs --no-print-directory\"

# Compiler flags
CFLAGS=\"$cflags\"
CXXFLAGS=\"$cxxflags\"
LDFLAGS=\"$ldflags\"
RUSTFLAGS=\"$rustflags\"

# Compression settings
$(makepkg_get_compress_settings 0 19 6)

# Build environment
BUILDENV=(!distcc color ccache check !sign)

# Package options
OPTIONS=(!strip docs libtool staticlibs emptydirs !debug !buildflags)

# Strip options
STRIP_BINARIES=\"--strip-all\"
STRIP_SHARED=\"--strip-unneeded\"
STRIP_STATIC=\"--strip-debug\"

# Documentation directories
DOC_DIRS=(usr/{,local/}{,share/}{doc,man,man/*,info} usr/share/gtk-doc usr/share/doc)

# Package signing
INTEGRITY_CHECK=(sha256)
STRIP_BINARIES=\"--strip-all\"
STRIP_SHARED=\"--strip-unneeded\"
STRIP_STATIC=\"--strip-debug\"
MAN_DIRS=({usr{,/local}{,/share},opt/*}/{man,info})
"

    if [[ -n "$output_file" ]]; then
        mock_write_file "$output_file" "$conf"
        log_info "Generated makepkg.conf: $output_file"
    else
        echo "$conf"
    fi
}

makepkg_generate_profile() {
    local name="$1"
    local output_file="${2:-}"
    local march="${3:-$(makepkg_get_cpu_march)}"
    local linker="${4:-$(makepkg_detect_linker)}"
    local jobs="${5:-$(makepkg_get_parallel_jobs)}"
    
    local conf="# GLM5 Chad Arch Installer - Makepkg Profile: $name
# Generated: $(date)
# CPU: $(grep -m1 "^model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)
# Cores: $jobs

MAKEFLAGS=\"-j$jobs\"
CFLAGS=\"$(makepkg_get_cflags "$march")\"
CXXFLAGS=\"$(makepkg_get_cxxflags "$march")\"
LDFLAGS=\"$(makepkg_get_ldflags "$linker")\"
RUSTFLAGS=\"$(makepkg_get_rustflags "$march")\"
"

    if [[ -n "$output_file" ]]; then
        mock_write_file "$output_file" "$conf"
        log_info "Generated profile: $output_file"
    else
        echo "$conf"
    fi
}

makepkg_install_conf_d() {
    local name="${1:-99-chad-optimizations}"
    local output_dir="${2:-$MAKEPKG_CONF_DIR}"
    local mount_point="${3:-}"
    
    [[ -n "$mount_point" ]] && output_dir="$mount_point$output_dir"
    
    mkdir -p "$output_dir"
    
    local output_file="$output_dir/${name}.conf"
    
    makepkg_generate_conf "$output_file"
    
    log_info "Installed makepkg.conf.d: $output_file"
}

makepkg_validate_config() {
    local config_file="${1:-$MAKEPKG_CONF}"
    local errors=0
    
    if [[ ! -f "$config_file" ]]; then
        log_error "Config file not found: $config_file"
        return 1
    fi
    
    local required_keys=("CFLAGS" "CXXFLAGS" "MAKEFLAGS")
    
    for key in "${required_keys[@]}"; do
        if ! grep -q "^$key=" "$config_file"; then
            log_warn "Missing recommended key: $key"
            ((errors++))
        fi
    done
    
    local cflags
    cflags=$(grep "^CFLAGS=" "$config_file" 2>/dev/null | cut -d= -f2- | tr -d '"')
    
    if [[ "$cflags" == *"-march=native"* ]] || [[ "$cflags" == *"-march=x86-64"* ]]; then
        log_debug "Valid march detected in CFLAGS"
    else
        log_warn "No march specified in CFLAGS - may be suboptimal"
        ((errors++))
    fi
    
    if grep -q "^CFLAGS=.*-O0" "$config_file"; then
        log_warn "Optimization level -O0 detected - may be debug build"
    fi
    
    [[ $errors -eq 0 ]]
}

makepkg_benchmark_compile() {
    local test_file="${1:-/tmp/makepkg_benchmark.c}"
    local output_file="${2:-/tmp/makepkg_benchmark}"
    
    cat > "$test_file" << 'EOF'
#include <stdio.h>
int main() {
    volatile int sum = 0;
    for (int i = 0; i < 1000000; i++) {
        sum += i;
    }
    printf("%d\n", sum);
    return 0;
}
EOF
    
    local cflags=("-O2" "-O3" "-O3 -march=native" "-O3 -march=native -flto")
    
    log_info "Benchmarking compiler flags..."
    
    for flag in "${cflags[@]}"; do
        local start end duration
        start=$(date +%s%N)
        gcc $flag "$test_file" -o "$output_file" 2>/dev/null
        end=$(date +%s%N)
        duration=$(( (end - start) / 1000000 ))
        log_info "  Flags: $flag -> ${duration}ms"
        rm -f "$output_file"
    done
    
    rm -f "$test_file"
}

makepkg_show_current() {
    _tui_header "Current Makepkg Configuration"
    
    echo "Config file: $MAKEPKG_CONF"
    echo "Config dir:  $MAKEPKG_CONF_DIR"
    echo ""
    
    if [[ -f "$MAKEPKG_CONF" ]]; then
        echo "=== Main Configuration ==="
        grep -v "^[[:space:]]*#" "$MAKEPKG_CONF" | grep -v "^$" | head -20
        echo ""
    fi
    
    if [[ -d "$MAKEPKG_CONF_DIR" ]]; then
        echo "=== Additional Configs ==="
        for f in "$MAKEPKG_CONF_DIR"/*.conf; do
            [[ -f "$f" ]] && echo "  $(basename "$f")"
        done
        echo ""
    fi
    
    echo "=== Detected Optimizations ==="
    echo "  CPU March:    $(makepkg_get_cpu_march)"
    echo "  Parallel:     $(makepkg_get_parallel_jobs) jobs"
    echo "  Linker:       $(makepkg_detect_linker)"
    echo "  LTO Support:  $(makepkg_has_lto_support && echo 'Yes' || echo 'No')"
    echo ""
}

makepkg_menu() {
    _tui_header "Makepkg Configuration Manager"
    
    local options=(
        "Show Current Configuration"
        "Generate Optimized Config"
        "Generate Profile"
        "Backup Current Config"
        "Validate Config"
        "Benchmark Compile Flags"
        "Install to makepkg.conf.d"
        "Back"
    )
    
    while true; do
        local choice
        choice=$(_tui_menu_select "Makepkg Options:" "${options[@]}")
        
        case "$choice" in
            *"Show Current"*)
                makepkg_show_current
                ;;
            *"Generate Optimized"*)
                local output
                output=$(_tui_input "Output file" "/etc/makepkg.conf.d/99-optimized.conf")
                makepkg_generate_conf "$output"
                ;;
            *"Generate Profile"*)
                local name
                name=$(_tui_input "Profile name" "optimized")
                makepkg_generate_profile "$name"
                ;;
            *"Backup"*)
                makepkg_backup_config
                ;;
            *"Validate"*)
                if makepkg_validate_config; then
                    log_success "Configuration is valid"
                else
                    log_error "Configuration has issues"
                fi
                ;;
            *"Benchmark"*)
                makepkg_benchmark_compile
                ;;
            *"Install"*)
                makepkg_install_conf_d
                ;;
            *"Back"*)
                return 0
                ;;
        esac
        
        _tui_wait
    done
}
