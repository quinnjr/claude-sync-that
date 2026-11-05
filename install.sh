#!/usr/bin/env bash
# Install the thatpet-wsl Claude Code plugin from GitHub.
#
#   curl -fsSL https://raw.githubusercontent.com/quinnjr/claude-sync-that/main/install.sh | bash
#
# Options (pass after `bash -s --` when piping from curl):
#   --config-dir DIR   Install into this Claude Code config dir. Repeatable.
#                      Default: $CLAUDE_CONFIG_DIR, or ~/.claude.
#   --uninstall        Remove the plugin and its marketplace instead.
#   -h, --help         Show this help.

set -euo pipefail

REPO="${THATPET_WSL_REPO:-quinnjr/claude-sync-that}"
MARKETPLACE="claude-sync-that"
PLUGIN="thatpet-wsl@${MARKETPLACE}"

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Install the thatpet-wsl Claude Code plugin from GitHub.

  curl -fsSL https://raw.githubusercontent.com/quinnjr/claude-sync-that/main/install.sh | bash
  curl -fsSL .../install.sh | bash -s -- [options]

Options:
  --config-dir DIR   Install into this Claude Code config dir. Repeatable.
                     Default: $CLAUDE_CONFIG_DIR, or ~/.claude.
  --uninstall        Remove the plugin and its marketplace instead.
  -h, --help         Show this help.
EOF
}

find_claude() {
  if [ -n "${CLAUDE_BIN:-}" ]; then
    echo "$CLAUDE_BIN"
    return 0
  fi
  if command -v claude >/dev/null 2>&1; then
    command -v claude
    return 0
  fi
  local candidate
  for candidate in "$HOME/.local/bin/claude" "$HOME/.claude/local/claude"; do
    if [ -x "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

# Runs claude with CLAUDE_CONFIG_DIR set to $1 (empty = leave the environment alone).
run_claude() {
  local dir="$1"
  shift
  if [ -n "$dir" ]; then
    CLAUDE_CONFIG_DIR="$dir" "$claude_bin" "$@" </dev/null
  else
    "$claude_bin" "$@" </dev/null
  fi
}

# Prints the source of our marketplace in this config dir: "github:<repo>", "other", or nothing.
marketplace_source() {
  local json
  json=$(run_claude "$1" plugin marketplace list --json 2>/dev/null) || return 0
  local entry
  entry=$(printf '%s\n' "$json" | grep -A4 "\"name\": \"${MARKETPLACE}\"" || true)
  if [ -z "$entry" ]; then
    return 0
  fi
  if printf '%s\n' "$entry" | grep -q "\"repo\": \"${REPO}\""; then
    echo "github:${REPO}"
  else
    echo "other"
  fi
}

plugin_installed() {
  run_claude "$1" plugin list --json 2>/dev/null | grep -q "\"id\": \"${PLUGIN}\""
}

install_into() {
  local dir="$1" label="${1:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}"
  say "Installing ${PLUGIN} into ${label}"
  case "$(marketplace_source "$dir")" in
    "github:${REPO}")
      run_claude "$dir" plugin marketplace update "$MARKETPLACE" >/dev/null
      ;;
    other)
      say "Replacing the existing ${MARKETPLACE} marketplace with github:${REPO}"
      run_claude "$dir" plugin marketplace remove "$MARKETPLACE" >/dev/null
      run_claude "$dir" plugin marketplace add "$REPO" >/dev/null
      ;;
    *)
      run_claude "$dir" plugin marketplace add "$REPO" >/dev/null
      ;;
  esac
  if plugin_installed "$dir"; then
    run_claude "$dir" plugin update "$PLUGIN" >/dev/null
  else
    run_claude "$dir" plugin install "$PLUGIN" >/dev/null
  fi
  say "Installed. New Claude Code sessions will show up on ThatPet."
}

uninstall_from() {
  local dir="$1" label="${1:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}"
  say "Removing ${PLUGIN} from ${label}"
  if plugin_installed "$dir"; then
    run_claude "$dir" plugin uninstall "$PLUGIN" >/dev/null
  fi
  if [ -n "$(marketplace_source "$dir")" ]; then
    run_claude "$dir" plugin marketplace remove "$MARKETPLACE" >/dev/null
  fi
  say "Removed."
}

check_thatpet() {
  local cmd="" local_app_data exe
  if [ -n "${THATPET_EXE:-}" ]; then
    if [ -f "$THATPET_EXE" ]; then
      return 0
    fi
    warn "THATPET_EXE is set to ${THATPET_EXE}, which doesn't exist."
    return 0
  fi
  if command -v cmd.exe >/dev/null 2>&1; then
    cmd=$(command -v cmd.exe)
  elif [ -x /mnt/c/Windows/System32/cmd.exe ]; then
    cmd=/mnt/c/Windows/System32/cmd.exe
  fi
  if [ -z "$cmd" ] || ! command -v wslpath >/dev/null 2>&1; then
    warn "can't reach Windows from here (is WSL interop on?). The pet won't hear from WSL until it is."
    return 0
  fi
  local_app_data=$( (cd / && timeout 3 "$cmd" /d /c 'echo %LOCALAPPDATA%' 2>/dev/null) | tr -d '\r\n') || true
  exe="$(wslpath -u "$local_app_data" 2>/dev/null || true)/Programs/ThatPet/thatpet.exe"
  if [ -z "$local_app_data" ] || [ ! -f "$exe" ]; then
    warn "ThatPet wasn't found under %LOCALAPPDATA%\\Programs\\ThatPet. Install it from https://thatpet.app, or set THATPET_EXE."
    return 0
  fi
  say "Found ThatPet at ${exe}"
}

# Everything runs from main, so a partial download (curl | bash cut off mid-stream)
# runs nothing, and no command can read the rest of the script from stdin.
main() {
  config_dirs=()
  uninstall=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --config-dir)
        if [ $# -lt 2 ]; then
          die "--config-dir needs a directory"
        fi
        config_dirs+=("$2")
        shift 2
        ;;
      --config-dir=*)
        config_dirs+=("${1#--config-dir=}")
        shift
        ;;
      --uninstall)
        uninstall=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown option: $1 (try --help)"
        ;;
    esac
  done

  claude_bin=$(find_claude) || die "Claude Code (claude) was not found. Install it first: https://claude.com/claude-code"

  if [ -z "${WSL_DISTRO_NAME:-}" ] && ! grep -qi microsoft /proc/version 2>/dev/null; then
    warn "this doesn't look like WSL. The plugin only does something when Claude Code runs inside WSL."
  fi

  if [ ${#config_dirs[@]} -eq 0 ]; then
    config_dirs=("")
  fi

  for dir in "${config_dirs[@]}"; do
    if [ "$uninstall" -eq 1 ]; then
      uninstall_from "$dir"
    else
      install_into "$dir"
    fi
  done

  if [ "$uninstall" -eq 0 ]; then
    check_thatpet
  fi
}

main "$@"
