#!/usr/bin/env bash
# Tests for plugins/thatpet-wsl/scripts/forward.sh using a stand-in thatpet.exe.
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
forward="$root/plugins/thatpet-wsl/scripts/forward.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0

pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; failures=$((failures + 1)); }

# Stand-in exe: records its arguments and stdin.
fake="$tmp/thatpet.exe"
cat > "$fake" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$tmp/args"
cat > "$tmp/stdin"
echo "noise on stdout"
exit 3
EOF
chmod +x "$fake"

payload='{"session_id":"t1","hook_event_name":"PreToolUse","tool_name":"Bash"}'

# 1. Forwards stdin unchanged with the right arguments, swallows output and exit code.
out=$(printf '%s' "$payload" | THATPET_EXE="$fake" XDG_CACHE_HOME="$tmp/cache" "$forward")
code=$?
if [ "$code" -eq 0 ]; then pass "exits 0 even when thatpet.exe fails"; else fail "exit code was $code"; fi
if [ -z "$out" ]; then pass "prints nothing"; else fail "printed: $out"; fi
if [ "$(cat "$tmp/args")" = "hook --provider claude" ]; then pass "passes hook --provider claude"; else fail "args were: $(cat "$tmp/args")"; fi
if [ "$(cat "$tmp/stdin")" = "$payload" ]; then pass "forwards stdin unchanged"; else fail "stdin was: $(cat "$tmp/stdin")"; fi

# 2. Uses the cached exe path when THATPET_EXE is unset.
rm -f "$tmp/args"
mkdir -p "$tmp/cache/thatpet-wsl"
printf '%s' "$fake" > "$tmp/cache/thatpet-wsl/exe-path"
printf '%s' "$payload" | env -u THATPET_EXE XDG_CACHE_HOME="$tmp/cache" "$forward"
if [ -f "$tmp/args" ]; then pass "uses cached exe path"; else fail "cached exe path was not used"; fi

# 3. No cmd.exe available: exits 0 quietly without calling anything.
rm -f "$tmp/args"
out=$(printf '%s' "$payload" | env -u THATPET_EXE XDG_CACHE_HOME="$tmp/empty" THATPET_CMD_EXE="$tmp/no-cmd.exe" "$forward" 2>&1)
code=$?
if [ "$code" -eq 0 ] && [ -z "$out" ]; then pass "no Windows interop exits 0 silently"; else fail "no interop: code=$code out=$out"; fi

# 4. Discovery: a stand-in cmd.exe reports %LOCALAPPDATA%; the exe under it is found and cached.
appdata="$tmp/appdata"
mkdir -p "$appdata/Programs/ThatPet"
cp "$fake" "$appdata/Programs/ThatPet/thatpet.exe"
unc='\\wsl.localhost\'"${WSL_DISTRO_NAME:-Ubuntu}$(printf '%s' "$appdata" | tr '/' '\\')"
fakecmd="$tmp/cmd.exe"
printf '#!/usr/bin/env bash\nprintf "%%s\\r\\n" %q\n' "$unc" > "$fakecmd"
chmod +x "$fakecmd"
rm -f "$tmp/args"
printf '%s' "$payload" | env -u THATPET_EXE XDG_CACHE_HOME="$tmp/disc" THATPET_CMD_EXE="$fakecmd" "$forward"
if [ -f "$tmp/args" ]; then pass "discovers thatpet.exe under %LOCALAPPDATA%"; else fail "discovery did not find the exe"; fi
if [ "$(cat "$tmp/disc/thatpet-wsl/exe-path" 2>/dev/null)" = "$appdata/Programs/ThatPet/thatpet.exe" ]; then pass "caches the discovered path"; else fail "cache was: $(cat "$tmp/disc/thatpet-wsl/exe-path" 2>/dev/null)"; fi

# 5. A stale cache entry falls back to discovery.
printf '%s' "$tmp/gone.exe" > "$tmp/disc/thatpet-wsl/exe-path"
rm -f "$tmp/args"
printf '%s' "$payload" | env -u THATPET_EXE XDG_CACHE_HOME="$tmp/disc" THATPET_CMD_EXE="$fakecmd" "$forward"
code=$?
if [ "$code" -eq 0 ] && [ -f "$tmp/args" ]; then pass "stale cache falls back to discovery"; else fail "stale cache: code=$code"; fi

if [ "$failures" -eq 0 ]; then
  echo "all tests passed"
  exit 0
fi
echo "$failures test(s) failed"
exit 1
