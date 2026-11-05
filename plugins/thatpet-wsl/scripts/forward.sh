#!/usr/bin/env bash
# Forward one Claude Code hook event (JSON on stdin) to ThatPet on the Windows host.
# Never fails the hook: any problem means the pet just doesn't hear about this event.

set -u

cache_file="${XDG_CACHE_HOME:-$HOME/.cache}/thatpet-wsl/exe-path"

find_cmd_exe() {
  if [ -n "${THATPET_CMD_EXE:-}" ]; then
    if [ -x "$THATPET_CMD_EXE" ]; then
      echo "$THATPET_CMD_EXE"
      return 0
    fi
    return 1
  fi
  if command -v cmd.exe >/dev/null 2>&1; then
    command -v cmd.exe
    return 0
  fi
  local candidate
  for candidate in /mnt/c/Windows/System32/cmd.exe /mnt/c/WINDOWS/system32/cmd.exe; do
    if [ -x "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

discover_exe() {
  local cmd local_app_data linux_dir exe
  cmd=$(find_cmd_exe) || return 1
  command -v wslpath >/dev/null 2>&1 || return 1
  # Run from / so cmd.exe doesn't complain about a UNC working directory.
  local_app_data=$(cd / && timeout 3 "$cmd" /d /c 'echo %LOCALAPPDATA%' 2>/dev/null | tr -d '\r\n')
  if [ -z "$local_app_data" ] || [ "$local_app_data" = "%LOCALAPPDATA%" ]; then
    return 1
  fi
  linux_dir=$(wslpath -u "$local_app_data" 2>/dev/null) || return 1
  exe="$linux_dir/Programs/ThatPet/thatpet.exe"
  if [ ! -f "$exe" ]; then
    return 1
  fi
  echo "$exe"
}

resolve_exe() {
  if [ -n "${THATPET_EXE:-}" ]; then
    echo "$THATPET_EXE"
    return 0
  fi
  local exe=""
  if [ -r "$cache_file" ]; then
    exe=$(cat "$cache_file")
  fi
  if [ -n "$exe" ] && [ -f "$exe" ]; then
    echo "$exe"
    return 0
  fi
  exe=$(discover_exe) || return 1
  mkdir -p "$(dirname "$cache_file")" 2>/dev/null && printf '%s' "$exe" > "$cache_file" 2>/dev/null
  echo "$exe"
}

if exe=$(resolve_exe); then
  timeout 4 "$exe" hook --provider claude >/dev/null 2>&1
else
  cat >/dev/null
fi
exit 0
