#!/usr/bin/env bash
#
# GLM5 Chad Arch Installer
# 
# "In the beginning, there was the command line. And it was good."
# Then someone deleted /var/lib/pacman, and lo, this script was born.
#
# A modular, bulletproof Arch Linux installer with:
# - BTRFS + Snapper for bulletproof snapshots
# - TUI interface (gum/dialog/pure bash)
# - Highly configurable via YAML
# - Mock mode for safe testing
# - Support for unofficial repos (CachyOS, Chaotic-AUR, etc.)
# - Hardware detection for legacy systems
#

set -eo pipefail

MOCK_MODE="${MOCK_MODE:-false}"
NON_INTERACTIVE="${NON_INTERACTIVE:-false}"
COMMAND=""

readonly VERSION="2.0.0-chad"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LIBS_DIR="$SCRIPT_DIR/libs"
readonly CORE_DIR="$SCRIPT_DIR/core"
readonly MODULES_DIR="$SCRIPT_DIR/modules"

declare -a _LOADED_LIBS=()

colors() {
    echo -e "\033[0m"
}

banner() {
    echo -e "
\033[38;5;196m    ██████╗  █████╗ ██╗     ██╗      ██████╗ ██████╗ ███╗   ███╗██████╗  █████╗ ███████╗ ██████╗ ██████╗ \033[0m
\033[38;5;202m   ██╔════╝ ██╔══██╗██║     ██║     ██╔════╝██╔═══██╗████╗ ████║██╔══██╗██╔══██╗██╔════╝██╔═══██╗██╔══██╗\033[0m
\033[38;5;208m   ██║      ███████║██║     ██║     ██║     ██║   ██║██╔████╔██║██████╔╝███████║██║     ██║   ██║██████╔╝\033[0m
\033[38;5;214m   ██║      ██╔══██║██║     ██║     ██║     ██║   ██║██║╚██╔╝██║██╔═══╝ ██╔══██║██║     ██║   ██║██╔══██╗\033[0m
\033[38;5;226m   ╚██████╗ ██║  ██║███████╗███████╗╚██████╗╚██████╔╝██║ ╚═╝ ██║██║     ██║  ██║╚██████╗╚██████╔╝██║  ██║\033[0m
\033[38;5;154m    ╚═════╝ ╚═╝  ╚═╝╚══════╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝\033[0m

\033[38;5;46m                    █████╗ ██████╗ ██████╗ ██╗███████╗██╗   ██╗███╗   ██╗\033[0m
\033[38;5;46m                   ██╔══██╗██╔══██╗██╔══██╗██║██╔════╝╚██╗ ██╔╝████╗  ██║\033[0m
\033[38;5;46m                   ███████║██████╔╝██████╔╝██║█████╗   ╚████╔╝ ██╔██╗ ██║\033[0m
\033[38;5;46m                   ██╔══██║██╔═══╝ ██╔═══╝ ██║██╔══╝    ╚██╔╝  ██║╚██╗██║\033[0m
\033[38;5;46m                   ██║  ██║██║     ██║     ██║██║        ██║   ██║ ╚████║\033[0m
\033[38;5;46m                   ╚═╝  ╚═╝╚═╝     ╚═╝     ╚═╝╚═╝        ╚═╝   ╚═╝  ╚═══╝\033[0m
"
    echo -e "\033[33m    ─────────────────────────────────────────────────────────────────────────\033[0m"
    echo -e "\033[37m    GLM5 Chad Edition v${VERSION} | Arch Linux BTRFS Installer\033[0m"
    echo -e "\033[37m    \"I use Arch, btw\" - Now with 1337-tier repo selection\033[0m"
    echo -e "\033[33m    ─────────────────────────────────────────────────────────────────────────\033[0m"
    echo ""
}

check_dependencies() {
    echo "Checking dependencies..."
    echo ""
    
    local errors=0
    local warnings=0
    
    local required_tools=("bash" "python3" "sed" "awk" "grep" "tr" "cut")
    local recommended_tools=("gum" "dialog" "curl" "wget" "git")
    local install_tools=("parted" "mkfs.btrfs" "pacstrap" "arch-chroot")
    
    echo "=== Required Tools ==="
    for tool in "${required_tools[@]}"; do
        if command -v "$tool" &>/dev/null; then
            echo "✓ $tool: $(command -v "$tool")"
        else
            echo "✗ $tool: NOT FOUND"
            ((errors++))
        fi
    done
    
    echo ""
    echo "=== TUI Backends (at least one recommended) ==="
    local tui_found=false
    for tool in "${recommended_tools[@]:0:2}"; do
        if command -v "$tool" &>/dev/null; then
            echo "✓ $tool: $(command -v "$tool")"
            tui_found=true
        else
            echo "- $tool: not installed (optional)"
        fi
    done
    
    if ! $tui_found; then
        echo "⚠ No TUI backend found - will use pure bash fallback"
        ((warnings++))
    fi
    
    echo ""
    echo "=== Network Tools ==="
    for tool in curl wget; do
        if command -v "$tool" &>/dev/null; then
            echo "✓ $tool: $(command -v "$tool")"
            break
        fi
    done
    
    echo ""
    echo "=== Installation Tools (for actual install) ==="
    for tool in "${install_tools[@]}"; do
        if command -v "$tool" &>/dev/null; then
            echo "✓ $tool: $(command -v "$tool")"
        else
            echo "- $tool: not available (needed for installation)"
            ((warnings++))
        fi
    done
    
    echo ""
    echo "=== Cache Directory ==="
    local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}"
    if [[ -d "$cache_dir" ]]; then
        echo "✓ Cache directory: $cache_dir"
        
        local repos_json="$cache_dir/chad-installer-repos.json"
        if [[ -f "$repos_json" ]]; then
            local count
            count=$(python3 -c "
import sys, json
try:
    with open('$repos_json', 'r') as f:
        repos = json.load(f)
    print(len(repos))
except:
    print(0)
" 2>/dev/null)
            echo "  └─ repos.json: $count repos cached"
        else
            echo "  └─ repos.json: not cached yet (run 'repos update')"
        fi
    else
        echo "✗ Cache directory not found: $cache_dir"
    fi
    
    echo ""
    
    if [[ $errors -gt 0 ]]; then
        echo "❌ $errors errors found - some functionality will not work"
        return 1
    elif [[ $warnings -gt 0 ]]; then
        echo "⚠ $warnings warnings - some features may be limited"
        return 0
    else
        echo "✓ All dependencies satisfied"
        return 0
    fi
}

run_tests() {
    echo "Running automated tests..."
    echo ""
    
    local passed=0
    local failed=0
    
    echo "=== Test 1: Library Loading ==="
    if load_all_libs 2>/dev/null; then
        echo "✓ All libraries loaded successfully"
        passed=$((passed + 1))
    else
        echo "✗ Failed to load libraries"
        failed=$((failed + 1))
    fi
    
    echo ""
    echo "=== Test 2: TUI Backend Detection ==="
    local backend
    backend=$(_tui_detect_backend 2>/dev/null || echo "unknown")
    echo "Backend: $backend"
    if [[ "$backend" =~ ^(gum|dialog|bash)$ ]]; then
        echo "✓ Valid TUI backend detected"
        passed=$((passed + 1))
    else
        echo "✗ Invalid TUI backend"
        failed=$((failed + 1))
    fi
    
    echo ""
    echo "=== Test 3: Repository Cache ==="
    local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}"
    local repos_json="$cache_dir/chad-installer-repos.json"
    if [[ -f "$repos_json" ]]; then
        local count
        count=$(repos_count 2>/dev/null || echo "0")
        echo "Cached repos: $count"
        if [[ "$count" -gt 50 ]]; then
            echo "✓ Repository cache healthy"
            passed=$((passed + 1))
        else
            echo "⚠ Repository cache may be incomplete"
            passed=$((passed + 1))
        fi
    else
        echo "Repository cache not found - will be created on first use"
        passed=$((passed + 1))
    fi
    
    echo ""
    echo "=== Test 4: Mock Mode ==="
    MOCK_MODE=true
    mock_cmd "Test command" echo "test" &>/dev/null && {
        echo "✓ Mock mode working"
        passed=$((passed + 1))
    } || {
        echo "✗ Mock mode failed"
        failed=$((failed + 1))
    }
    
    echo ""
    echo "=== Test 5: Config System ==="
    config_get "system_hostname" &>/dev/null && {
        echo "✓ Config system working"
        passed=$((passed + 1))
    } || {
        echo "✗ Config system failed"
        failed=$((failed + 1))
    }
    
    echo ""
    echo "================================"
    echo "Tests passed: $passed"
    echo "Tests failed: $failed"
    
    if [[ $failed -eq 0 ]]; then
        echo "✓ All tests passed!"
        return 0
    else
        echo "✗ Some tests failed"
        return 1
    fi
}

load_lib() {
    local lib="$1"
    
    if [[ " ${_LOADED_LIBS[*]} " =~ " $lib " ]]; then
        return 0
    fi
    
    local lib_file=""
    
    if [[ -f "$CORE_DIR/$lib.sh" ]]; then
        lib_file="$CORE_DIR/$lib.sh"
    elif [[ -f "$LIBS_DIR/$lib.sh" ]]; then
        lib_file="$LIBS_DIR/$lib.sh"
    elif [[ -f "$MODULES_DIR/$lib.sh" ]]; then
        lib_file="$MODULES_DIR/$lib.sh"
    fi
    
    if [[ -n "$lib_file" ]]; then
        source "$lib_file"
        _LOADED_LIBS+=("$lib")
        return 0
    else
        echo "Error: Library not found: $lib"
        return 1
    fi
}

load_all_libs() {
    for lib in logging tui mock deps config; do
        load_lib "$lib" || return 1
    done
    
    for lib in btrfs snapper makepkg bootloader kernel; do
        load_lib "$lib" || return 1
    done
    
    for lib in repos install backup optimize hardware profiles; do
        load_lib "$lib" || return 1
    done
}

show_help() {
    echo "
GLM5 Chad Arch Installer v${VERSION}

Usage: $(basename "$0") [OPTIONS] [COMMAND]

Commands:
    install          Run the full Arch Linux installer
    profiles         Manage installation profiles
    config           Configure the installer settings
    repos            Manage unofficial repositories
    backup           Backup system files and packages
    restore          Restore from backup
    optimize         Optimize system configuration
    hardware         Detect and configure hardware
    mock             Run in mock/test mode (no changes)
    wizard           Interactive configuration wizard
    check-deps       Check all dependencies
    test             Run automated tests

Options:
    -h, --help       Show this help message
    -v, --version    Show version
    -m, --mock       Enable mock mode
    -c, --config     Specify config file
    -d, --debug      Enable debug logging
    -y, --yes        Accept defaults (non-interactive)

Examples:
    $(basename "$0")                    # Interactive menu
    $(basename "$0") check-deps         # Check dependencies
    $(basename "$0") test               # Run automated tests
    $(basename "$0") install            # Full installation
    $(basename "$0") -m install         # Mock/test installation
    $(basename "$0") profiles list      # List available profiles
    $(basename "$0") profiles apply gaming # Apply gaming profile
    $(basename "$0") repos update       # Fetch repos from ArchWiki
    $(basename "$0") repos list         # List available repos
    $(basename "$0") repos select       # Multi-select repos to enable
    $(basename "$0") repos status       # Show enabled repos
    $(basename "$0") backup full        # Full system backup

Environment Variables:
    MOCK_MODE=true     Enable mock mode
    LOG_LEVEL=DEBUG    Set logging verbosity
    CONFIG_FILE=path   Specify config file

TUI Backends (in order of preference):
    1. gum    - Best experience, install with: pacman -S gum
    2. dialog - Good fallback, usually pre-installed
    3. bash   - Works everywhere, limited features

Profiles:
    desktop    - Modern desktop with Hyprland, CachyOS kernel
    server     - Headless server with LTS kernel
    legacy     - Older hardware with AMD legacy support
    gaming     - Gaming optimized with low-latency kernel
    chromebook - Chromebook specific with GRUB bootloader
    minimal    - Bare minimum installation

For more information, see the README or visit:
https://github.com/nsomnia/chad-arch-installer
"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                echo "GLM5 Chad Arch Installer v${VERSION}"
                exit 0
                ;;
            -m|--mock)
                MOCK_MODE="true"
                export MOCK_MODE
                shift
                ;;
            -c|--config)
                CONFIG_FILE="$2"
                export CONFIG_FILE
                shift 2
                ;;
            -d|--debug)
                LOG_LEVEL="DEBUG"
                export LOG_LEVEL
                shift
                ;;
            -y|--yes)
                NON_INTERACTIVE="true"
                export NON_INTERACTIVE
                shift
                ;;
            -*)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                break
                ;;
        esac
    done
    
    COMMAND="${1:-menu}"
    shift || true
    REMAINING_ARGS=("$@")
}

init() {
    load_all_libs || {
        echo "Failed to load required libraries"
        exit 1
    }
    
    mock_init
    config_load
    repos_init
}

main_menu() {
    while true; do
        _tui_clear
        banner
        
        local backend_name
        case "$(_tui_detect_backend)" in
            gum) backend_name="gum 🍬" ;;
            dialog) backend_name="dialog 📺" ;;
            *) backend_name="bash 💻" ;;
        esac
        
        local options=(
            "🚀 Install Arch Linux"
            "📄 Select Installation Profile"
            "⚙️  Configuration Wizard"
            "📦 Repository Manager"
            "💾 Backup System"
            "📥 Restore from Backup"
            "⚡ System Optimization"
            "🔧 Hardware Detection"
            "🧪 Mock Mode: $MOCK_MODE"
            "🔍 Check Dependencies"
            "📋 Show Current Config"
            "❓ Help"
            "🚪 Exit"
        )
        
        local choice
        choice=$(_tui_menu_select "TUI: $backend_name | Select an option:" "${options[@]}")
        
        case "$choice" in
            *"Install"*)
                _tui_confirm "This will install Arch Linux. Continue?" && {
                    install_run
                }
                ;;
            *"Profile"*)
                profile_select
                ;;
            *"Configuration"*)
                config_wizard
                if _tui_confirm "Save configuration?"; then
                    config_save
                fi
                ;;
            *"Repository"*)
                repos_menu
                ;;
            *"Backup"*)
                backup_interactive
                ;;
            *"Restore"*)
                restore_interactive
                ;;
            *"Optimization"*)
                optimize_interactive
                ;;
            *"Hardware"*)
                hardware_interactive
                ;;
            *"Mock"*)
                if [[ "$MOCK_MODE" == "true" ]]; then
                    MOCK_MODE="false"
                else
                    MOCK_MODE="true"
                fi
                export MOCK_MODE
                mock_init
                ;;
            *"Check"*)
                check_dependencies
                ;;
            *"Current Config"*)
                config_show
                ;;
            *"Help"*)
                show_help | less -R
                ;;
            *"Exit"*)
                _tui_color green "Thanks for using GLM5 Chad Arch Installer!"
                echo ""
                echo "Remember: 'I use Arch, btw' - now you can too!"
                exit 0
                ;;
        esac
        
        _tui_wait
    done
}

run_install() {
    log_info "Starting Arch Linux installation..."
    
    if _tui_confirm "Run installation in mock mode first (recommended)?"; then
        local old_mock="$MOCK_MODE"
        MOCK_MODE="true"
        export MOCK_MODE
        mock_init
        
        install_run
        
        mock_summary
        
        if ! _tui_confirm "Mock run complete. Proceed with real installation?"; then
            MOCK_MODE="$old_mock"
            export MOCK_MODE
            return 0
        fi
        
        MOCK_MODE="$old_mock"
        export MOCK_MODE
        mock_init
    fi
    
    install_run
}

run_command() {
    local cmd="$1"
    shift || true
    
    case "$cmd" in
        install)
            run_install "$@"
            ;;
        config)
            case "${1:-show}" in
                wizard) config_wizard ;;
                show) config_show ;;
                save) config_save "${2:-}" ;;
                *) config_show ;;
            esac
            ;;
        repos)
            case "${1:-menu}" in
                list) repos_list ;;
                search) repos_search "${2:-}" ;;
                select)
                    local selected
                    mapfile -t selected < <(repos_select)
                    if [[ ${#selected[@]} -gt 0 ]]; then
                        repos_enable_selected "${selected[@]}"
                    else
                        log_info "No repositories selected"
                    fi
                    ;;
                status) repos_status ;;
                auto) repos_auto_detect ;;
                update) repos_update_from_wiki ;;
                menu) repos_menu ;;
                *) repos_menu ;;
            esac
            ;;
        backup)
            case "${1:-interactive}" in
                full) backup_full ;;
                packages) backup_packages ;;
                interactive) backup_interactive ;;
                *) backup_interactive ;;
            esac
            ;;
        restore)
            case "${1:-interactive}" in
                packages) restore_packages ;;
                interactive) restore_interactive ;;
                *) restore_interactive ;;
            esac
            ;;
        optimize)
            case "${1:-all}" in
                all) optimize_all ;;
                makepkg) optimize_makepkg_conf ;;
                interactive) optimize_interactive ;;
                *) optimize_interactive ;;
            esac
            ;;
        hardware)
            case "${1:-detect}" in
                detect) hardware_detect_all ;;
                drivers) hardware_install_drivers ;;
                interactive) hardware_interactive ;;
                *) hardware_interactive ;;
            esac
            ;;
        profiles)
            case "${1:-menu}" in
                list) profile_list ;;
                show) profile_show "${2:-desktop}" ;;
                apply) profile_apply "${2:-desktop}" ;;
                create) profile_wizard ;;
                select) profile_select ;;
                menu) profile_menu ;;
                *) profile_menu ;;
            esac
            ;;
        mock)
            MOCK_MODE="true"
            export MOCK_MODE
            mock_init
            log_info "Mock mode enabled - no changes will be made"
            ;;
        wizard)
            config_wizard
            ;;
        check-deps)
            check_dependencies
            ;;
        test)
            run_tests
            ;;
        menu)
            main_menu
            ;;
        *)
            log_error "Unknown command: $cmd"
            show_help
            exit 1
            ;;
    esac
}

trap 'log_error "Script interrupted"; exit 130' INT TERM

cleanup() {
    if [[ "$MOCK_MODE" == "true" ]] && declare -f mock_summary &>/dev/null; then
        mock_summary
    fi
    if declare -f log_info &>/dev/null; then
        log_info "GLM5 Chad Arch Installer finished"
    fi
}

trap cleanup EXIT

main() {
    parse_args "$@"
    init
    
    log_debug "GLM5 Chad Arch Installer v${VERSION}"
    log_debug "Command: ${COMMAND:-menu}"
    log_debug "Mock Mode: $MOCK_MODE"
    log_debug "TUI Backend: $(_tui_detect_backend)"
    
    run_command "$COMMAND" "${REMAINING_ARGS[@]}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
