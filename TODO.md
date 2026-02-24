# GLM5 Chad Arch Installer - TODO Checklist

**Model**: GLM5 (z-ai/glm-5:free)  
**Updated**: 2026-02-24  
**Status**: 🔧 **IN PROGRESS - COMPREHENSIVE REFACTOR**

---

## Critical Architecture Issues

### Module Dependencies & Load Order
- [x] Add explicit dependency declarations to each module
- [x] Fix `detect_cpu_info()` - moved to hardware.sh
- [x] Fix `detect_cpu_vendor()` - moved to hardware.sh
- [x] Create `core/deps.sh` for cross-module dependency resolution
- [ ] Add module load verification at startup

### Error Handling Standardization
- [ ] Standardize error return codes (1=fail, 2=missing dep, 3=permission, 4=validation)
- [ ] Add `set -E` for ERR trap inheritance across functions
- [ ] Create centralized error handler in logging.sh
- [ ] Add stack traces to all error exits

### Global State Management
- [ ] Namespace all global variables with `CHAD_` prefix
- [ ] Create `core/state.sh` for centralized state management
- [ ] Add state validation functions
- [ ] Document all global variables in AGENTS.md

---

## Critical Bug Fixes

### core/logging.sh
- [x] Fix permission handling for log directory creation
- [ ] Add `LOG_TO_STDERR` option for non-interactive mode
- [ ] Fix `stat` command compatibility (use `find -printf` for size)
- [ ] Add log file permission check before writing

### core/config.sh
- [x] Fix CONFIG_DIR path resolution when SCRIPT_DIR undefined
- [ ] Add yq availability check with fallback
- [ ] Add config schema validation
- [ ] Add config migration for version upgrades
- [ ] Fix `_parse_yaml` to handle nested arrays

### core/tui.sh
- [x] Fix gum detection and fallback logic
- [x] Fix multiselect cleanup trap
- [x] Fix arrow key escape sequence handling
- [ ] Add `_tui_progress_bar()` for file operations
- [ ] Add `_tui_file_select()` for file picker
- [ ] Add `_tui_directory_select()` for directory picker

### core/mock.sh
- [x] Add `bc` availability check for time multiplier
- [ ] Remove unused `MOCK_FILE_CONTENTS` array
- [ ] Add mock state serialization for debugging
- [ ] Add mock validation assertions
- [ ] Add mock file permission tracking

### modules/install.sh
- [x] Move `detect_cpu_vendor()` to hardware.sh
- [x] Fix `mock_write_file` with stdin (`-` argument)
- [x] Fix locale.gen write to use `mock_write_file`
- [ ] Add device path validation before partitioning
- [ ] Add disk space verification before install
- [ ] Add installation rollback capability
- [ ] Add installation resume from checkpoint

### modules/hardware.sh
- [x] Fix `detect_cpu_info()` dependency issue
- [x] Add `detect_cpu_vendor()` function
- [ ] Add GPU detection fallback without lspci (use /sys)
- [ ] Add PCI device enumeration
- [ ] Add USB device detection
- [ ] Add hardware profile generation

### modules/backup.sh
- [x] Add zstd availability check before tar operations
- [x] Fix HOME variable for root user
- [ ] Add backup verification (checksums)
- [ ] Add incremental backup support
- [ ] Add backup compression level option
- [ ] Add backup encryption support

### modules/optimize.sh
- [x] Fix LTO detection (use makepkg.sh library)
- [x] Make I/O scheduler changes persistent via udev rules
- [ ] Add CPU microcode version detection
- [ ] Add GPU optimization settings

### modules/repos.sh
- [ ] Add repo URL validation
- [ ] Add repo availability check (ping)
- [ ] Add repo mirror speed test
- [ ] Add repo backup before modification
- [ ] Add repo synchronization for offline mode

### libs/btrfs.sh
- [ ] Add chattr attribute verification
- [ ] Add BTRFS feature detection
- [ ] Add filesystem health check
- [ ] Add RAID support
- [ ] Add compression benchmark

### libs/snapper.sh
- [ ] Add existing config detection and update
- [ ] Add snapper installation verification
- [ ] Add snapshot size estimation
- [ ] Add snapshot comparison tool

### libs/makepkg.sh (NEW)
- [x] Create dedicated makepkg.conf configuration library
- [x] Add CPU march detection (Intel/AMD)
- [x] Add parallel job detection
- [x] Add linker detection (mold/lld/gold)
- [x] Add LTO support detection
- [x] Add profile generation
- [x] Add config validation
- [x] Add benchmark compilation

---

## Feature Additions

### Installation Features
- [ ] Add disk encryption with TPM support
- [ ] Add secure boot setup with shim
- [ ] Add dual-boot detection and configuration
- [ ] Add network installation (PXE)
- [ ] Add unattended installation mode
- [ ] Add installation profiling for debugging

### System Features
- [ ] Add AUR helper installation (paru/yay)
- [ ] Add desktop environment profiles
- [ ] Add window manager profiles
- [ ] Add development environment setup
- [ ] Add gaming setup (steam, lutris, wine)
- [ ] Add server profile options

### Recovery Features
- [ ] Add system recovery mode
- [ ] Add snapshot browser
- [ ] Add boot repair tool
- [ ] Add pacman database repair
- [ ] Add BTRFS recovery tool

---

## Code Quality Improvements

### Documentation
- [x] Add comprehensive AGENTS.md with architecture overview
- [ ] Add inline documentation for all public functions
- [ ] Add usage examples in each module
- [ ] Create TESTING.md with test procedures
- [ ] Document TUI backend behavior differences

### Testing
- [ ] Add unit tests for each module
- [ ] Add integration tests for installation flow
- [ ] Add CI/CD configuration
- [ ] Add shellcheck integration
- [ ] Add shfmt integration

### Security
- [ ] Add input sanitization for all user inputs
- [ ] Add path traversal protection
- [ ] Add command injection protection
- [ ] Add secure temporary file handling
- [ ] Add privilege escalation audit

---

## Performance Optimizations

### Startup Performance
- [ ] Lazy load modules on demand
- [ ] Cache hardware detection results
- [ ] Parallelize repository fetching
- [ ] Add profile-based loading

### Runtime Performance
- [ ] Add progress reporting for long operations
- [ ] Add operation cancellation support
- [ ] Add resource usage monitoring
- [ ] Add memory usage optimization

---

## Previous Issues (Resolved)

- [x] Fix repo selection reporting only 1 repo instead of all selected
- [x] Verify JSON cache at `$HOME/.cache/chad-installer-repos.json`
- [x] Ensure gum/dialog TUI works correctly for multi-select
- [x] Add repos_enable_interactive() with proper multi-repo selection
- [x] Add test mode (`./installer.sh test`)
- [x] Add check-deps command
- [x] Improve logging with more context
- [x] Add search/filter capability for large lists

---

## Priority Order

### P0 - Critical (Blocks Installation)
1. [x] Fix module dependencies and load order
2. [x] Fix detect_cpu_vendor/detect_cpu_info location
3. [ ] Add device validation before partitioning
4. [x] Fix mock_write_file stdin handling

### P1 - High (Affects Reliability)
1. [ ] Add installation rollback capability
2. [x] Fix I/O scheduler persistence
3. [x] Add zstd availability checks
4. [ ] Standardize error handling

### P2 - Medium (Improves UX)
1. [ ] Add progress bars for long operations
2. [ ] Add installation checkpoints
3. [ ] Add AUR helper installation
4. [ ] Add desktop profiles

### P3 - Low (Nice to Have)
1. [ ] Add recovery mode
2. [ ] Add network installation
3. [ ] Add gaming setup
4. [ ] Add performance profiling

---

## Statistics

- **Total Issues**: 89
- **Critical**: 15
- **High**: 28
- **Medium**: 31
- **Low**: 15
- **Resolved**: 28
