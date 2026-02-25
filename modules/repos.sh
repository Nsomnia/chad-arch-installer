#!/usr/bin/env bash
#
# GLM5 Chad Arch Installer - Unofficial Repository Manager
# Parses ArchWiki and provides dynamic repo selection
#

set -eo pipefail

if [[ -z "${_REPOS_LOADED:-}" ]]; then
    readonly _REPOS_LOADED=1
else
    return 0
fi

REPOS_DB="${REPOS_DB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../config/repos.db}"
REPOS_CACHE="${REPOS_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/chad-installer-repos.cache}"
ARCHWIKI_URL="https://wiki.archlinux.org/title/Unofficial_user_repositories?action=raw"
REPOS_JSON="${XDG_CACHE_HOME:-$HOME/.cache}/chad-installer-repos.json"
REPOS_ENABLED_JSON="${XDG_CACHE_HOME:-$HOME/.cache}/chad-installer-enabled-repos.json"

_parse_archwiki_repos_python() {
    local cache_file="$1"
    local output_file="${2:-$REPOS_JSON}"
    
    python3 - "$cache_file" "$output_file" <<'PYEOF'
import sys
import re
import json

cache_file = sys.argv[1]
output_file = sys.argv[2]

with open(cache_file, 'r', encoding='utf-8', errors='replace') as f:
    content = f.read()

lines = content.split('\n')

repos = {}
in_repo = False
in_codeblock = False
repo_name = ""
repo_server = ""
repo_key = ""
repo_desc = ""
repo_signed = "true"
current_section = "Signed"
repo_section = "Signed"

for line in lines:
    h3_match = re.match(r'^===\s+(.+?)\s+===$', line)
    if h3_match:
        if repo_name and repo_server:
            repo_signed = "false" if repo_section == "Unsigned" else "true"
            repos[repo_name] = {
                'server': repo_server,
                'key': repo_key,
                'desc': repo_desc,
                'signed': repo_signed
            }
        repo_name = h3_match.group(1).strip()
        repo_section = current_section
        repo_server = ""
        repo_key = ""
        repo_desc = ""
        repo_signed = "true"
        in_repo = True
        in_codeblock = False
        continue
    
    h2_match = re.match(r'^==\s+(Signed|Unsigned)\s+==$', line)
    if h2_match:
        current_section = h2_match.group(1)
        continue
    
    if not in_repo:
        continue
    
    if '{{bc|' in line:
        in_codeblock = True
        server_match = re.search(r'Server\s*=\s*(\S+)', line)
        if server_match:
            repo_server = server_match.group(1).rstrip('}')
        if re.search(r'\}\}\s*$', line):
            in_codeblock = False
        continue
    
    if in_codeblock:
        if re.search(r'\}\}\s*$', line):
            in_codeblock = False
        server_match = re.search(r'^Server\s*=\s*(.+)$', line)
        if server_match:
            srv = server_match.group(1).strip().split()[0].rstrip('}')
            repo_server = srv
        continue
    
    line = re.sub(r"'''", '', line)
    
    if re.search(r'\*\s*Maintainer:', line):
        pass
    elif re.search(r'\*\s*Description:', line):
        desc_match = re.search(r'\*\s*Description:\s*(.+)$', line)
        if desc_match:
            repo_desc = desc_match.group(1).split('.')[0].strip()
    elif re.search(r'\*\s*Key-ID:', line):
        key_match = re.search(r'([A-Fa-f0-9]{16,40})', line)
        if key_match:
            repo_key = key_match.group(1)
    elif 'search=0x' in line:
        key_match = re.search(r'search=0x\s*([A-Fa-f0-9]{16,40})', line)
        if key_match:
            repo_key = key_match.group(1)

if repo_name and repo_server:
    repo_signed = "false" if repo_section == "Unsigned" else "true"
    repos[repo_name] = {
        'server': repo_server,
        'key': repo_key,
        'desc': repo_desc,
        'signed': repo_signed
    }

with open(output_file, 'w') as f:
    json.dump(repos, f, indent=2)

print(len(repos))
PYEOF
}

repos_update_from_wiki() {
    _tui_info "Fetching unofficial repositories from ArchWiki..."
    
    mkdir -p "$(dirname "$REPOS_CACHE")"
    
    local fetch_rc=1
    if command -v curl &>/dev/null; then
        curl -sL --max-time 30 "$ARCHWIKI_URL" -o "$REPOS_CACHE"
        fetch_rc=$?
    elif command -v wget &>/dev/null; then
        wget -q --timeout=30 -O "$REPOS_CACHE" "$ARCHWIKI_URL"
        fetch_rc=$?
    else
        _tui_error "Neither curl nor wget available"
        return 1
    fi
    
    if [[ $fetch_rc -ne 0 ]]; then
        _tui_error "Failed to fetch (returned $fetch_rc)"
        return 1
    fi
    
    if [[ ! -f "$REPOS_CACHE" ]] || [[ ! -s "$REPOS_CACHE" ]]; then
        _tui_error "Failed to fetch repository list (empty file)"
        return 1
    fi
    
    local count
    count=$(_parse_archwiki_repos_python "$REPOS_CACHE" "$REPOS_JSON") || {
        _tui_error "Failed to parse repository data"
        return 1
    }
    
    _tui_success "Loaded $count repositories"
}

repos_ensure_cache() {
    if [[ ! -f "$REPOS_JSON" ]]; then
        log_info "Repository cache not found, fetching from ArchWiki..."
        repos_update_from_wiki || return 1
    fi
    
    if ! python3 - "$REPOS_JSON" <<'PYEOF' &>/dev/null
import sys, json
with open(sys.argv[1], 'r') as f:
    json.load(f)
PYEOF
    then
        log_warn "Repository cache is corrupted, re-fetching..."
        repos_update_from_wiki || return 1
    fi
}

repos_count() {
    python3 - "$REPOS_JSON" <<'PYEOF'
import sys, json
with open(sys.argv[1], 'r') as f:
    repos = json.load(f)
print(len(repos))
PYEOF
}

repos_get_server() {
    local name="$1"
    python3 - "$REPOS_JSON" "$name" <<'PYEOF'
import sys, json
with open(sys.argv[1], 'r') as f:
    repos = json.load(f)
name = sys.argv[2]
if name in repos:
    print(repos[name].get('server', ''))
PYEOF
}

repos_get_key() {
    local name="$1"
    python3 - "$REPOS_JSON" "$name" <<'PYEOF'
import sys, json
with open(sys.argv[1], 'r') as f:
    repos = json.load(f)
name = sys.argv[2]
if name in repos:
    print(repos[name].get('key', ''))
PYEOF
}

repos_get_desc() {
    local name="$1"
    python3 - "$REPOS_JSON" "$name" <<'PYEOF'
import sys, json
with open(sys.argv[1], 'r') as f:
    repos = json.load(f)
name = sys.argv[2]
if name in repos:
    print(repos[name].get('desc', ''))
PYEOF
}

repos_is_signed() {
    local name="$1"
    local signed
    signed=$(python3 - "$REPOS_JSON" "$name" <<'PYEOF'
import sys, json
with open(sys.argv[1], 'r') as f:
    repos = json.load(f)
name = sys.argv[2]
if name in repos:
    print(repos[name].get('signed', 'true'))
PYEOF
)
    [[ "$signed" == "true" ]]
}

repos_list_names() {
    python3 - "$REPOS_JSON" <<'PYEOF'
import sys, json
with open(sys.argv[1], 'r') as f:
    repos = json.load(f)
for name in sorted(repos.keys()):
    print(name)
PYEOF
}

repos_list() {
    repos_ensure_cache || return 1
    
    local count
    count=$(repos_count)
    
    _tui_header "Available Unofficial Repositories ($count total)"
    
    python3 - "$REPOS_JSON" <<'PYEOF'
import sys, json
with open(sys.argv[1], 'r') as f:
    repos = json.load(f)
for name in sorted(repos.keys()):
    data = repos[name]
    signed = "✓" if data.get('signed', 'true') == 'true' else "✗"
    desc = data.get('desc', '')[:50]
    print(f"{name:25} [{signed}] {desc}")
PYEOF
    
    echo ""
    echo "Legend: [✓] Signed  [✗] Unsigned"
    echo ""
    echo "Run 'repos select' to enable repositories"
}

repos_search() {
    local search_term="$1"
    repos_ensure_cache || return 1
    
    _tui_header "Search Results: '$search_term'"
    
    python3 - "$REPOS_JSON" "$search_term" <<'PYEOF'
import sys, json
with open(sys.argv[1], 'r') as f:
    repos = json.load(f)
search = sys.argv[2].lower()
found = False
for name in sorted(repos.keys()):
    data = repos[name]
    desc = data.get('desc', '').lower()
    if search in name.lower() or search in desc:
        found = True
        signed = "✓" if data.get('signed', 'true') == 'true' else "✗"
        print(f"{name:25} [{signed}] {data.get('desc', '')[:50]}")
if not found:
    print("No repositories found matching search term.")
PYEOF
}

repos_select() {
    local prompt="${1:-Select repositories to enable (Space to toggle):}"
    
    repos_ensure_cache || return 1
    
    local options=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        options+=("$line")
    done < <(python3 - "$REPOS_JSON" <<'PYEOF'
import sys, json
with open(sys.argv[1], 'r') as f:
    repos = json.load(f)
for name in sorted(repos.keys()):
    data = repos[name]
    desc = data.get('desc', '')[:40]
    signed = "✓" if data.get('signed', 'true') == 'true' else "✗"
    print(f"{name} [{signed}] {desc}")
PYEOF
)
    
    if [[ ${#options[@]} -eq 0 ]]; then
        log_error "No repositories available"
        return 1
    fi
    
    log_info "Found ${#options[@]} repositories"
    
    local selected
    mapfile -t selected < <(_tui_menu_multi "$prompt" "${options[@]}")
    local rc=$?
    
    if [[ $rc -ne 0 ]]; then
        log_info "Selection cancelled"
        return 0
    fi
    
    if [[ ${#selected[@]} -eq 0 ]]; then
        log_info "No repositories selected"
        return 0
    fi
    
    log_info "Selected ${#selected[@]} repositories:"
    
    local repo_names=()
    for s in "${selected[@]}"; do
        local name="${s%% \[*}"
        repo_names+=("$name")
        log_info "  - $name"
    done
    
    printf '%s\n' "${repo_names[@]}"
}

repo_add_key() {
    local name="$1"
    local key="$2"
    
    if [[ "$MOCK_MODE" == "true" ]]; then
        mock_cmd "Add GPG key for $name" pacman-key --recv-keys "$key" --keyserver keyserver.ubuntu.com
        mock_cmd "Sign key locally" pacman-key --lsign-key "$key"
        return 0
    fi
    
    log_info "Adding GPG key for $name: $key"
    
    pacman-key --recv-keys "$key" --keyserver keyserver.ubuntu.com 2>/dev/null || {
        log_error "Failed to receive key: $key"
        return 1
    }
    
    pacman-key --lsign-key "$key" 2>/dev/null || {
        log_error "Failed to sign key locally: $key"
        return 1
    }
    
    log_success "Key $key added and signed"
}

repo_is_enabled() {
    local name="$1"
    grep -q "^\[$name\]" /etc/pacman.conf 2>/dev/null
}

repo_enable() {
    local name="$1"
    local server
    server=$(repos_get_server "$name")
    
    if [[ -z "$server" ]]; then
        log_error "Unknown repository: $name"
        return 1
    fi
    
    if repo_is_enabled "$name"; then
        log_info "Repository $name is already enabled"
        return 0
    fi
    
    if repos_is_signed "$name"; then
        local key
        key=$(repos_get_key "$name")
        
        if [[ -n "$key" ]]; then
            case "$name" in
                chaotic-aur)
                    log_info "Installing Chaotic-AUR keyring..."
                    if [[ "$MOCK_MODE" != "true" ]]; then
                        pacman-key --recv-keys FBA220DFC880C036 --keyserver keyserver.ubuntu.com
                        pacman-key --lsign-key FBA220DFC880C036
                        pacman -U --noconfirm \
                            'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
                            'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
                    fi
                    ;;
                cachyos*)
                    log_info "Installing CachyOS repository..."
                    if [[ "$MOCK_MODE" != "true" ]]; then
                        pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com
                        pacman-key --lsign-key F3B607488DB35A47
                        pacman -U --noconfirm \
                            'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-keyring-20240331-1-any.pkg.tar.zst' \
                            'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-mirrorlist-22-1-any.pkg.tar.zst'
                    fi
                    ;;
                archlinuxcn)
                    log_info "Installing Arch Linux CN keyring..."
                    if [[ "$MOCK_MODE" != "true" ]]; then
                        pacman-key --lsign-key "farseerfc@archlinux.org"
                    fi
                    ;;
                ALHP)
                    log_info "Installing ALHP keyring..."
                    if [[ "$MOCK_MODE" != "true" ]]; then
                        pacman -U --noconfirm \
                            'https://alhp.dev/assets/keyrings/alhp-keyring-20250108-1-any.pkg.tar.zst' \
                            'https://alhp.dev/assets/keyrings/alhp-mirrorlist-20250218-1-any.pkg.tar.zst'
                    fi
                    ;;
                *)
                    repo_add_key "$name" "$key"
                    ;;
            esac
        fi
    fi
    
    local pacman_conf="/etc/pacman.conf"
    local repo_entry="
[$name]
SigLevel = Optional TrustAll
Server = $server
"
    
    if [[ "$MOCK_MODE" == "true" ]]; then
        mock_append_file "$pacman_conf" "$repo_entry"
    else
        echo "$repo_entry" >> "$pacman_conf"
    fi
    
    log_success "Repository enabled: $name"
}

repo_disable() {
    local name="$1"
    
    if ! repo_is_enabled "$name"; then
        log_info "Repository $name is not enabled"
        return 0
    fi
    
    local pacman_conf="/etc/pacman.conf"
    
    if [[ "$MOCK_MODE" == "true" ]]; then
        log_info "[MOCK] Would disable repository: $name"
        return 0
    fi
    
    local tmp_file
    tmp_file=$(mktemp)
    local in_repo=false
    
    while IFS= read -r line; do
        if [[ "$line" == "[$name]" ]]; then
            in_repo=true
            continue
        fi
        
        if $in_repo; then
            if [[ "$line" =~ ^\[.*\] ]]; then
                in_repo=false
            else
                continue
            fi
        fi
        
        echo "$line"
    done < "$pacman_conf" > "$tmp_file"
    
    mv "$tmp_file" "$pacman_conf"
    log_success "Repository disabled: $name"
}

repos_enable_selected() {
    local repos=("$@")
    
    if [[ ${#repos[@]} -eq 0 ]]; then
        log_warn "No repositories specified"
        return 0
    fi
    
    log_info "Enabling ${#repos[@]} repositories..."
    
    for repo in "${repos[@]}"; do
        repo_enable "$repo"
    done
    
    if [[ "$MOCK_MODE" != "true" ]]; then
        log_info "Refreshing package databases..."
        pacman -Sy
    fi
}

repos_status() {
    _tui_header "Enabled Repositories"
    
    local enabled=()
    local pacman_conf="/etc/pacman.conf"
    
    if [[ -f "$pacman_conf" ]]; then
        while IFS= read -r line; do
            if [[ "$line" =~ ^\[([a-zA-Z0-9_-]+)\]$ ]] && [[ "$line" != "[core]" ]] && [[ "$line" != "[extra]" ]] && [[ "$line" != "[core-testing]" ]] && [[ "$line" != "[extra-testing]" ]] && [[ "$line" != "[multilib]" ]]; then
                enabled+=("${BASH_REMATCH[1]}")
            fi
        done < "$pacman_conf"
    fi
    
    if [[ ${#enabled[@]} -eq 0 ]]; then
        echo "No unofficial repositories enabled."
    else
        for repo in "${enabled[@]}"; do
            local desc
            desc=$(repos_get_desc "$repo" 2>/dev/null || echo "")
            printf "%-25s %s\n" "$repo" "${desc:0:50}"
        done
    fi
    
    echo ""
    echo "Total: ${#enabled[@]} unofficial repositories enabled"
}

detect_optimized_repo() {
    log_info "Detecting CPU capabilities for optimized repositories..."
    
    local cpu_flags
    cpu_flags=$(cat /proc/cpuinfo 2>/dev/null | grep -m1 "^flags" | cut -d: -f2)
    
    local has_v3=false
    local has_v4=false
    
    if echo "$cpu_flags" | grep -q "avx2"; then
        has_v3=true
    fi
    
    if echo "$cpu_flags" | grep -qE "avx512f|avx512dq|avx512cd|avx512bw|avx512vl"; then
        has_v4=true
    fi
    
    if $has_v4; then
        echo "cachyos-v4"
    elif $has_v3; then
        echo "cachyos-v3"
    else
        echo ""
    fi
}

repos_auto_detect() {
    local optimal_repo
    optimal_repo=$(detect_optimized_repo)
    
    if [[ -n "$optimal_repo" ]]; then
        log_info "Detected optimal repository: $optimal_repo"
        
        if _tui_confirm "Enable $optimal_repo repository for optimized packages?"; then
            repo_enable "$optimal_repo"
        fi
    else
        log_info "No optimized repository available for this CPU"
    fi
}

repos_menu() {
    while true; do
        local status_info=""
        local enabled_count
        enabled_count=$(grep -c '^\[' /etc/pacman.conf 2>/dev/null || echo "0")
        status_info="($enabled_count repos in pacman.conf)"
        
        local options=(
            "List Available Repositories"
            "Select Repositories to Enable"
            "Disable a Repository"
            "Show Enabled Repositories"
            "Search Repositories"
            "Auto-detect Optimized Repo"
            "Update from ArchWiki"
            "Back"
        )
        
        local choice
        choice=$(_tui_menu_select "Repository Options $status_info" "${options[@]}")
        
        case "$choice" in
            *"List"*)
                repos_list
                ;;
            *"Select"*)
                local selected
                mapfile -t selected < <(repos_select)
                if [[ ${#selected[@]} -gt 0 ]]; then
                    _tui_box "Selected Repositories (${#selected[@]})" "$(printf '  - %s\n' "${selected[@]}")" "rounded" "141"
                    if _tui_confirm "Enable these ${#selected[@]} repositories?"; then
                        repos_enable_selected "${selected[@]}"
                    fi
                else
                    log_info "No repositories selected"
                fi
                ;;
            *"Disable"*)
                local enabled_repos=()
                while IFS= read -r line; do
                    if [[ "$line" =~ ^\[([a-zA-Z0-9_-]+)\]$ ]] && [[ "$line" != "[core]" ]] && [[ "$line" != "[extra]" ]] && [[ "$line" != "[multilib]" ]]; then
                        enabled_repos+=("${BASH_REMATCH[1]}")
                    fi
                done < /etc/pacman.conf 2>/dev/null
                
                if [[ ${#enabled_repos[@]} -eq 0 ]]; then
                    log_info "No unofficial repositories to disable"
                else
                    local to_disable
                    to_disable=$(_tui_menu_select "Select repository to disable:" "${enabled_repos[@]}")
                    if [[ -n "$to_disable" ]]; then
                        repo_disable "$to_disable"
                    fi
                fi
                ;;
            *"Show Enabled"*)
                repos_status
                ;;
            *"Search"*)
                local search_term
                search_term=$(_tui_input "Search repositories")
                if [[ -n "$search_term" ]]; then
                    repos_search "$search_term"
                fi
                ;;
            *"Auto"*)
                repos_auto_detect
                ;;
            *"Update"*)
                repos_update_from_wiki
                ;;
            *"Back"*)
                return 0
                ;;
        esac
        
        _tui_wait
    done
}

repos_init() {
    repos_ensure_cache 2>/dev/null || true
}
