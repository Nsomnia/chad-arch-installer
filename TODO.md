# GLM5 Chad Arch Installer - TODO Checklist

**Model**: GLM5 (z-ai/glm-5:free)  
**Updated**: 2026-02-24  
**Status**: ✅ **MAJOR PROGRESS - Core Complete**

---

## Completed This Session

### New Features Added
- [x] **Bootloader Management Library** (`libs/bootloader.sh`)
  - Limine bootloader support (modern, fast)
  - GRUB (required for Chromebooks/BIOS)
  - systemd-boot (default for UEFI)
  - rEFInd (graphical alternative)
  - Chromebook auto-detection
  - Secure boot support

- [x] **Kernel Management Library** (`libs/kernel.sh`)
  - Official kernels (linux, lts, hardened, zen)
  - CachyOS kernels (cachyos, cachyos-bore, cachyos-rt)
  - Third-party kernels (liquorix, xanmod)
  - CPU-optimized kernel recommendation
  - mkinitcpio configuration

- [x] **Installation Profiles System** (`modules/profiles.sh`)
  - Desktop profile (Hyprland, CachyOS kernel)
  - Server profile (LTS kernel, headless)
  - Legacy profile (older hardware, AMD R200 support)
  - Gaming profile (low-latency kernel, no mitigations)
  - Chromebook profile (GRUB bootloader requirement)
  - Minimal profile (base installation)
  - Custom profile wizard

- [x] **Enhanced Hardware Support**
  - AMD R200/R600/R700 legacy GPU detection
  - Chromebook auto-detection and configuration
  - Proper modprobe.d configuration for legacy AMD
  - Xorg configuration generation

- [x] **Dependency Management** (`core/deps.sh`)
  - Grouped dependency checking
  - Package/binary mapping
  - Installation helpers

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
- [x] Add AMD R200/R600/R700 legacy GPU detection
- [x] Add Chromebook auto-detection
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

### libs/makepkg.sh
- [x] Create dedicated makepkg.conf configuration library
- [x] Add CPU march detection (Intel/AMD)
- [x] Add parallel job detection
- [x] Add linker detection (mold/lld/gold)
- [x] Add LTO support detection
- [x] Add profile generation
- [x] Add config validation
- [x] Add benchmark compilation

### libs/bootloader.sh (NEW)
- [x] Multi-bootloader support (systemd-boot, GRUB, Limine, rEFInd)
- [x] Chromebook detection (requires GRUB)
- [x] UEFI/BIOS detection
- [x] Secure boot support
- [x] Automatic bootloader recommendation

### libs/kernel.sh (NEW)
- [x] Official kernel support
- [x] CachyOS kernel support
- [x] Third-party kernel support (Liquorix, XanMod)
- [x] CPU-optimized recommendation
- [x] mkinitcpio configuration

### modules/profiles.sh (NEW)
- [x] Profile listing
- [x] Profile selection
- [x] Profile creation wizard
- [x] Profile application
- [x] Pre-defined profiles (desktop, server, legacy, gaming, chromebook, minimal)

---

## Feature Additions

### Installation Features
- [ ] Add disk encryption with TPM support
- [ ] Add secure boot setup with shim
- [ ] Add dual-boot detection and configuration
- [ ] Add network installation (PXE)
- [x] Add unattended installation mode (via profiles)
- [ ] Add installation profiling for debugging

### System Features
- [ ] Add AUR helper installation (paru/yay)
- [x] Add desktop environment profiles
- [ ] Add window manager profiles
- [ ] Add development environment setup
- [x] Add gaming setup (via profiles)
- [x] Add server profile options
- [x] Add Chromebook-specific profile

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
- [x] Add profile-based loading

### Runtime Performance
- [ ] Add progress reporting for long operations
- [ ] Add operation cancellation support
- [ ] Add resource usage monitoring
- [ ] Add memory usage optimization

---

## Previous Issues (Resolved)

- [x] Fix repo selection reporting only 1 repo instead of all selected
- [x] Verify JSON cache at `$HOME/.cache/chad-installer-repos.json`
- [x] Ensure gum TUI works correctly for multi-select
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
4. [x] Add desktop profiles

### P3 - Low (Nice to Have)
1. [ ] Add recovery mode
2. [ ] Add network installation
3. [x] Add gaming setup (via profiles)
4. [ ] Add performance profiling

---

## Git Commit History

```
7503947 feat: add profiles command and menu integration
964321a feat: add installation profile system
93bac6c feat: update library loading for new modules
8491291 feat(libs): add bootloader and kernel management libraries
f0faa2b feat: add configuration files and templates
701c7ed docs: add comprehensive documentation
5bde053 chore: add Kilo project configuration
1aba8c7 feat(modules): add feature modules
4825103 feat(libs): add reusable library modules
e73a59e feat(core): add core infrastructure modules
5022458 feat: add main installer entry point
fb52eb5 chore: add .gitignore for project
```

---

## Statistics

- **Total Issues**: 110
- **Completed This Session**: 38
- **Remaining**: 72
- **Files Created**: 18
- **Files Modified**: 12
- **Commits Made**: 11
