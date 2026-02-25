#!/usr/bin/env bash
#
# GLM5 Chad Arch Installer
# 
# "In the beginning, there was the command line. And it was good."
# Then someone deleted /var/lib/pacman, and lo, this script was born.
#
# A modular, bulletproof Arch Linux installer with:
# - BTRFS + Snapper for bulletproof snapshots
# - TUI interface (gum)
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

check_dependencies() {
    local errors=0
    local warnings=0
    local results=()
    
    local required_tools=("bash" "python3" "sed" "awk" "grep" "tr" "cut" "gum")
    local install_tools=("parted" "mkfs.btrfs" "pacstrap" "arch-chroot")
    
    for tool in "${required_tools[@]}"; do
        if command -v "$tool" &>/dev/null; then
            results+=("✓ $tool")
        else
            results+=("✗ $tool")
            ((errors++))
        fi
    done
    
    local net_tool=""
    for tool in curl wget; do
        if command -v "$tool" &>/dev/null; then
            net_tool="$tool"
            break
        fi
    done
    [[ -n "$net_tool" ]] && results+=("✓ $net_tool (network)")
    
    for tool in "${install_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            ((warnings++))
        fi
    done
    
    local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}"
    if [[ -d "$cache_dir" ]]; then
        results+=("✓ Cache: $cache_dir")
        local repos_json="$cache_dir/chad-installer-repos.json"
        if [[ -f "$repos_json" ]]; then
            local count
            count=$(python3 -c "import json; print(len(json.load(open('$repos_json'))))" 2>/dev/null || echo "0")
            results+=("  $count repos cached")
        fi
    fi
    
    if ! _tui_box "Dependencies" "$(printf '%s\n' "${results[@]}")" "rounded" "141" 2>/dev/null; then
        printf '%s\n' "${results[@]}"
    fi
    
    if [[ $errors -gt 0 ]]; then
        _tui_error "$errors errors - some functionality will not work"
        return 1
    elif [[ $warnings -gt 0 ]]; then
        _tui_warn "$warnings warnings - install tools not found (ok for testing)"
    else
        _tui_success "All dependencies satisfied"
    fi
    return 0
}

run_tests() {
    local passed=0
    local failed=0
    local results=()
    
    results+=("✓ Library loading")
    ((passed++)) || true
    
    local backend
    backend=$(_tui_detect_backend) || backend="unknown"
    if [[ "$backend" == "gum" ]]; then
        results+=("✓ TUI backend: $backend")
        ((passed++)) || true
    else
        results+=("✗ TUI backend: $backend")
        ((failed++)) || true
    fi
    
    local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}"
    local repos_json="$cache_dir/chad-installer-repos.json"
    if [[ -f "$repos_json" ]]; then
        local count
        count=$(repos_count 2>/dev/null) || count=0
        results+=("✓ Repo cache: $count repos")
        ((passed++)) || true
    else
        results+=("✓ Repo cache: will create on first use")
        ((passed++)) || true
    fi
    
    MOCK_MODE=true
    if mock_cmd "Test" echo "test" &>/dev/null; then
        results+=("✓ Mock mode")
        ((passed++)) || true
    else
        results+=("✗ Mock mode")
        ((failed++)) || true
    fi
    
    if config_get "system_hostname" &>/dev/null; then
        results+=("✓ Config system")
        ((passed++)) || true
    else
        results+=("✗ Config system")
        ((failed++)) || true
    fi
    
    local box_color
    [[ $failed -eq 0 ]] && box_color=82 || box_color=196
    
    if _tui_box "Test Results" "$(printf '%s\n' "${results[@]}")"$'\n'"Passed: $passed | Failed: $failed" "rounded" "$box_color" 2>/dev/null; then
        :
    else
        printf '%s\n' "${results[@]}"
        echo "Passed: $passed | Failed: $failed"
    fi
    
    [[ $failed -eq 0 ]] && return 0 || return 1
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
    run-tests        Run automated tests

Examples:
    $(basename "$0")                    # Interactive menu
    $(basename "$0") check-deps         # Check dependencies
    $(basename "$0") run-tests          # Run automated tests

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

Requirements:
    gum - Required for interactive TUI (install with: pacman -S gum)
    The installer will automatically install gum if missing.

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
                _tui_error "Unknown option: $1"
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
    if ! command -v gum &>/dev/null && [[ "$NON_INTERACTIVE" != "true" ]] && [[ -t 0 ]] && [[ -t 1 ]]; then
        echo "gum is required for interactive TUI. Installing..."
        if command -v pacman &>/dev/null; then
            sudo pacman -S --noconfirm gum || {
                echo "Failed to install gum. Please install manually: pacman -S gum"
                exit 1
            }
        else
            echo "pacman not found. Please install gum manually."
            exit 1
        fi
    fi
    
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
        local title
        title=$(gum style --foreground 212 --bold "GLM5 Chad Arch Installer")
        title="$title"$'\n'"$(gum style --foreground 82 "v${VERSION}")"
        
        local options=(
            "Install Arch Linux"
            "Select Installation Profile"
            "Configuration Wizard"
            "Repository Manager"
            "Backup System"
            "Restore from Backup"
            "System Optimization"
            "Hardware Detection"
            "Mock Mode: $MOCK_MODE"
            "Check Dependencies"
            "Show Current Config"
            "Help"
            "Exit"
        )
        
        local choice
        choice=$(printf '%s\n' "${options[@]}" | gum choose --header="$title"$'\n\n'"Select an option:" --height=25 --cursor.foreground=82 --selected.foreground=82)
        
        case "$choice" in
            *"Install"*)
                _tui_confirm "This will install Arch Linux. Continue?" && install_run
                ;;
            *"Profile"*)
                profile_select
                ;;
            *"Configuration"*)
                config_wizard
                _tui_confirm "Save configuration?" && config_save
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
                [[ "$MOCK_MODE" == "true" ]] && MOCK_MODE="false" || MOCK_MODE="true"
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
                _tui_pager "$(show_help)"
                ;;
            *"Exit"*)
                exit 0
                ;;
        esac
    done
}

run_install() {
    if _tui_confirm "Run installation?" && _tui_confirm "Run in mock mode first?"; then
        local old_mock="$MOCK_MODE"
        MOCK_MODE="true"
        export MOCK_MODE
        mock_init
        install_run
        mock_summary
        
        _tui_confirm "Proceed with real installation?" || {
            MOCK_MODE="$old_mock"
            export MOCK_MODE
            return 0
        }
        
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
        run-tests)
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
    run_command "$COMMAND" "${REMAINING_ARGS[@]}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
