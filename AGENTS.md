# GLM5 Chad Arch Installer - Agent Documentation

## Architecture Overview

This is a modular, enterprise-grade Arch Linux installer designed for reliability, maintainability, and extensibility.

### Directory Structure

```
glm5-chad-arch-installer/
├── installer.sh          # Main entry point
├── core/                 # Core infrastructure modules
│   ├── tui.sh           # Terminal UI framework (gum)
│   ├── logging.sh       # Centralized logging system
│   ├── config.sh        # Configuration management
│   ├── mock.sh          # Mock/test mode infrastructure
│   └── deps.sh          # Dependency resolution (planned)
├── libs/                 # Reusable libraries
│   ├── btrfs.sh         # BTRFS filesystem utilities
│   ├── snapper.sh       # Snapper snapshot management
│   └── makepkg.sh       # Makepkg.conf configuration
├── modules/              # Feature modules
│   ├── install.sh       # Installation orchestration
│   ├── repos.sh         # Repository management
│   ├── backup.sh        # Backup/restore functionality
│   ├── hardware.sh      # Hardware detection
│   └── optimize.sh      # System optimization
├── config/               # Configuration files
│   ├── defaults.yaml    # Default configuration
│   └── repos.db         # Static repository database
├── templates/            # Configuration templates
└── profiles/             # Installation profiles (planned)
```

## Module Loading System

### Load Order

Modules are loaded in dependency order:

1. **Core modules** (infrastructure)
   - `logging` - Logging system
   - `tui` - Terminal UI
   - `mock` - Mock mode
   - `config` - Configuration

2. **Libraries** (reusable components)
   - `btrfs` - BTRFS utilities
   - `snapper` - Snapshot management
   - `makepkg` - Build configuration

3. **Modules** (feature implementations)
   - `repos` - Repository management
   - `install` - Installation
   - `backup` - Backup/restore
   - `optimize` - System optimization
   - `hardware` - Hardware detection

### Module Template

```bash
#!/usr/bin/env bash
#
# Module Name - Brief Description
#

set -eo pipefail

# Prevent double loading
if [[ -z "${_MODULE_LOADED:-}" ]]; then
    readonly _MODULE_LOADED=1
else
    return 0
fi

# Declare module dependencies
declare -a _MODULE_DEPS=("logging" "tui")

# Module variables
MODULE_VAR="${MODULE_VAR:-default}"

# Public functions
module_function() {
    :
}

# Private functions (underscore prefix)
_module_helper() {
    :
}

# Module initialization
_module_init() {
    :
}
```

## Global Variables

All global variables use the following prefixes:

| Prefix | Scope | Example |
|--------|-------|---------|
| `CHAD_` | Global state | `CHAD_INSTALL_MODE` |
| `MOCK_` | Mock mode | `MOCK_MODE`, `MOCK_ROOT` |
| `LOG_` | Logging | `LOG_LEVEL`, `LOG_FILE` |
| `CONFIG_` | Config system | `CONFIG_DIR`, `CONFIG_FILE` |
| `TUI_` | TUI system | `TUI_BACKEND`, `TUI_COLORS` |
| `_` | Internal | `_LOADED_LIBS`, `_TUI_BACKEND` |

### Important Global Variables

```bash
# Mode flags
MOCK_MODE="false"           # Enable mock/test mode
NON_INTERACTIVE="false"     # Non-interactive mode

# Paths
SCRIPT_DIR                  # Script installation directory
INSTALL_MOUNT="/mnt"        # Installation mount point
INSTALL_DEVICE              # Target device

# TUI
_TUI_BACKEND                # Current TUI backend (gum)
_TUI_COLORS_ENABLED         # Color output enabled

# Configuration
CONFIG_FILE                 # Active config file
USER_CONFIG                 # User config path

# Logging
LOG_LEVEL="INFO"            # Current log level
LOG_FILE                    # Log file path
```

## Error Handling

### Standard Return Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General failure |
| 2 | Missing dependency |
| 3 | Permission denied |
| 4 | Validation error |
| 5 | User cancelled |
| 130 | Interrupted (Ctrl+C) |

### Error Handling Pattern

```bash
some_function() {
    local errors=0
    
    # Validate inputs
    if [[ -z "$1" ]]; then
        log_error "Missing required argument"
        return 4
    fi
    
    # Check dependencies
    if ! command -v required_tool &>/dev/null; then
        log_error "Missing dependency: required_tool"
        return 2
    fi
    
    # Perform operation with error tracking
    if ! do_something; then
        log_error "Operation failed"
        ((errors++))
    fi
    
    # Return appropriate code
    [[ $errors -eq 0 ]] && return 0 || return 1
}
```

## TUI System

### Backend

The TUI system requires **gum** for interactive use. It will be automatically installed if missing.

- **gum** - Required for interactive TUI (install with `pacman -S gum`)
- Non-interactive mode available with `-y` flag for scripted usage

### Available Functions

```bash
# Menu selection (single) - arrow keys to navigate, Enter to select
choice=$(_tui_menu_select "Prompt" "Option 1" "Option 2" "Option 3")

# Menu selection (multiple) - Space to toggle, Enter to confirm
mapfile -t selected < <(_tui_menu_multi "Prompt" "Opt1" "Opt2" "Opt3")

# Filter/fuzzy search through options
choice=$(_tui_filter "Search..." "Option 1" "Option 2" "Option 3")

# Input
value=$(_tui_input "Prompt" "default" "placeholder")

# Password (masked input)
password=$(_tui_password "Prompt")

# Confirmation (Yes/No) - arrow keys or y/n
if _tui_confirm "Continue?"; then
    :
fi

# Progress bar
_tui_progress $current $total "Message"

# Spinner for long operations
_tui_spinner $pid "Processing..."
_tui_spin "Running command..." command args

# Display
_tui_header "Title"
_tui_section "Subtitle"
_tui_info "Info message"
_tui_success "Success message"
_tui_warn "Warning message"
_tui_error "Error message"

# Styled box for important messages
_tui_box "Title" "Content" "rounded" "141"

# Multiline text input
text=$(_tui_write "Enter description:" "default text")

# File picker
file=$(_tui_file "/path/to/browse")

# Utilities
_tui_clear
_tui_wait "Press any key..."
_tui_pager "$content"
_tui_style "Styled text"
_tui_table data_array "Col1" "Col2" "Col3"
```

## Mock Mode

Mock mode allows testing without making actual system changes.

### Enabling Mock Mode

```bash
# Via flag
./installer.sh -m install

# Via environment
MOCK_MODE=true ./installer.sh install

# In code
MOCK_MODE="true"
mock_init
```

### Mock Functions

```bash
# Execute commands in mock mode
mock_cmd "Description" actual_command args

# File operations
mock_write_file "/path/file" "content"
mock_append_file "/path/file" "content"
mock_read_file "/path/file"
mock_exists "/path/file"

# Time simulation
mock_sleep 10  # Simulates 10s sleep in 0.1s

# Progress display
mock_progress "Installing..." 30

# Summary
mock_summary
```

## Configuration System

### Configuration Sources (in order of priority)

1. Command-line arguments
2. Environment variables
3. User config (`/etc/chad-installer/config.yaml`)
4. Default config (`config/defaults.yaml`)

### Configuration Keys

```yaml
# System
system.hostname: arch-chad
system.timezone: UTC
system.locale: en_US.UTF-8
system.keymap: us
system.cpu_vendor: auto

# Storage
storage.efi_size_mb: 1024
storage.luks.enabled: false
storage.btrfs.compress: zstd:3
storage.btrfs.label: ARCH

# Boot
boot.kernel: linux
boot.loader: systemd-boot
boot.secure_boot: false

# Snapper
snapper.enabled: true
snapper.hourly: 10
snapper.daily: 7

# Repositories
repos.cachyos: false
repos.chaotic: false
```

### Using Configuration

```bash
# Get value
value=$(config_get "system.hostname")

# Get with default
value=$(config_get "system.timezone" "UTC")

# Get boolean (returns 0/1)
if config_get_bool "snapper.enabled"; then
    :
fi

# Get integer
jobs=$(config_get_int "makepkg.jobs" 4)

# Set value
config_set "system.hostname" "myhost"

# Show current config
config_show

# Interactive wizard
config_wizard

# Save configuration
config_save "/path/to/config.yaml"
```

## Repository Management

### Repository Cache

Repositories are cached at:
- `$XDG_CACHE_HOME/chad-installer-repos.json` (default: `~/.cache/`)

### Repository Commands

```bash
# Update from ArchWiki
./installer.sh repos update

# List available repos
./installer.sh repos list

# Search repos
./installer.sh repos search chaotic

# Interactive selection
./installer.sh repos select

# Show enabled repos
./installer.sh repos status

# Auto-detect optimized repo
./installer.sh repos auto
```

## Testing

### Running Tests

```bash
# Run all tests
./installer.sh test

# Check dependencies
./installer.sh check-deps

# Test in mock mode
./installer.sh -m install
```

### Test Structure

```bash
run_tests() {
    local passed=0
    local failed=0
    
    echo "=== Test 1: Description ==="
    if test_function; then
        echo "✓ Test passed"
        ((passed++))
    else
        echo "✗ Test failed"
        ((failed++))
    fi
    
    echo "Tests passed: $passed"
    echo "Tests failed: $failed"
}
```

## BTRFS Layout

### Default Subvolumes

| Subvolume | Mount Point | Options |
|-----------|-------------|---------|
| @ | / | compress |
| @home | /home | compress |
| @var | /var | nodatacow |
| @var_log | /var/log | compress |
| @var_cache | /var/cache | nodatacow |
| @snapshots | /.snapshots | compress |
| @home_snapshots | /home/.snapshots | compress |

### BTRFS Functions

```bash
# Create layout
btrfs_create_layout "$device" "/mnt" "zstd:3"

# Mount subvolumes
btrfs_mount_subvolumes "$device" "/mnt" "zstd:3"

# Create swapfile
btrfs_create_swapfile "/mnt" 4096

# List snapshots
btrfs_list_snapshots "/"

# Snapshot operations
btrfs_snapshot "/source" "/dest"
btrfs_send_receive "/snapshot" "/backup"
```

## Snapper Configuration

### Timeline Retention

| Type | Default Count |
|------|---------------|
| Hourly | 10 |
| Daily | 7 |
| Weekly | 4 |
| Monthly | 6 |
| Yearly | 2 |

### Snapper Functions

```bash
# Full setup
snapper_full_setup "/mnt" "/mnt/home"

# Create config
snapper_create_config "root" "/"

# Configure
snapper_configure "root" "/"

# Enable timeline
snapper_enable_timeline

# Pacman hooks
snapper_setup_pacman_hooks

# Manual snapshots
snapper_create_snapshot "root" "Description"
snapper_create_pre_post "root" "Package operation"
```

## Hardware Detection

### GPU Detection

```bash
# Detect GPU
gpu_info=$(hardware_detect_gpu)
# Returns: vendor=...|driver=...|device=...

# Install GPU drivers
hardware_install_drivers

# NVIDIA-specific
hardware_configure_nvidia

# AMD legacy
hardware_configure_amd_legacy
```

### CPU Detection

```bash
# Get CPU info
info=$(detect_cpu_info)
# Returns: vendor=...|model=...|cores=...|threads=...

# Get features
features=$(detect_cpu_features)
# Returns: sse4.2 avx avx2 aes-ni

# Get optimal march
march=$(makepkg_get_cpu_march)
# Returns: native, x86-64-v3, znver3, etc.
```

## Makepkg Configuration

### Profiles

The makepkg library generates optimized configurations based on CPU:

```bash
# Generate config
makepkg_generate_conf "/etc/makepkg.conf.d/99-optimized.conf"

# Generate profile
makepkg_generate_profile "name" "/path/to/profile"

# Install to makepkg.conf.d
makepkg_install_conf_d "99-chad"

# Show current
makepkg_show_current

# Validate
makepkg_validate_config "/etc/makepkg.conf"

# Benchmark
makepkg_benchmark_compile
```

## Logging

### Log Levels

| Level | Value | Use Case |
|-------|-------|----------|
| DEBUG | 0 | Detailed debugging |
| INFO | 1 | General information |
| WARN | 2 | Warnings |
| ERROR | 3 | Errors |
| FATAL | 4 | Fatal errors (exits) |

### Using Logging

```bash
# Basic logging
log_debug "Debug info"
log_info "Information"
log_warn "Warning"
log_error "Error"
log_fatal "Fatal error"  # Exits with code 1

# Section markers
_log_section "Section Title"
_log_step 1 5 "Step description"

# Variable logging
_log_var "VARIABLE_NAME"
_log_array "ARRAY_NAME"

# Stack trace
_log_stack
```

## Best Practices

### 1. Function Naming

- Public functions: `module_action_verb`
- Private functions: `_module_helper`
- Callbacks: `on_event_name`

### 2. Error Messages

```bash
# Bad
log_error "Failed"

# Good
log_error "Failed to mount $device: permission denied (run as root?)"
```

### 3. User Prompts

```bash
# Bad
echo "Enter disk:"
read disk

# Good
local disks=()
while IFS= read -r line; do
    disks+=("$line")
done < <(lsblk -ndo NAME)
disk=$(_tui_menu_select "Select target disk:" "${disks[@]}")
```

### 4. Mock Mode Support

```bash
# Bad
mkfs.btrfs -L ARCH "$device"

# Good
mock_cmd "Format BTRFS" mkfs.btrfs -L ARCH "$device"
```

### 5. File Operations

```bash
# Bad
echo "$content" > /etc/config

# Good
mock_write_file "/etc/config" "$content"
```

## Extending the Installer

### Adding a New Module

1. Create `modules/newmodule.sh`
2. Follow module template
3. Add to `load_all_libs()` in `installer.sh`
4. Add command handler in `run_command()`
5. Add menu entry in `main_menu()`

### Adding a New Library

1. Create `libs/newlib.sh`
2. Follow module template
3. Add to `load_all_libs()` in `installer.sh`

### Adding a Profile

1. Create `profiles/myprofile.yaml`
2. Add profile selection to config wizard
3. Create profile application function

## Troubleshooting

### Common Issues

1. **Gum not installed**: The installer will auto-install gum; if that fails, run `pacman -S gum`
2. **Colors not working**: Check if stdout is a TTY
3. **Mock mode not working**: Set `MOCK_MODE=true` before calling functions
4. **Config not loading**: Check YAML syntax, ensure yq or internal parser works
5. **TUI hangs**: Ensure you're running in a terminal (not piped)

### Debug Mode

```bash
# Enable debug logging
LOG_LEVEL=DEBUG ./installer.sh

# Or
./installer.sh -d
```

### Verbose Output

```bash
# See all commands
set -x
./installer.sh
set +x
```
