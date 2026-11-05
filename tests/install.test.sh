#!/usr/bin/env bash
# Tests for install.sh using a stand-in `claude` that records its calls.
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
installer="$root/install.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0

pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; failures=$((failures + 1)); }

# Stand-in claude. State per config dir lives in $CLAUDE_CONFIG_DIR/{marketplace,plugin}.
fake="$tmp/claude"
cat > "$fake" <<'EOF'
#!/usr/bin/env bash
dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
mkdir -p "$dir"
echo "[$dir] $*" >> "$CALLS"
# The real claude reads stdin; under curl | bash that would be the rest of the script.
cat >> "${STDIN_LOG:-/dev/null}"
case "$*" in
  "plugin marketplace list --json")
    if [ -f "$dir/marketplace" ]; then
      printf '[\n  {\n    "name": "claude-sync-that",\n    %s\n  }\n]\n' "$(cat "$dir/marketplace")"
    else
      echo '[]'
    fi
    ;;
  "plugin list --json")
    if [ -f "$dir/plugin" ]; then
      echo '[{"id": "thatpet-wsl@claude-sync-that"}]'
    else
      echo '[]'
    fi
    ;;
  "plugin marketplace add quinnjr/claude-sync-that")
    echo '"source": "github",
    "repo": "quinnjr/claude-sync-that"' > "$dir/marketplace" ;;
  "plugin marketplace remove claude-sync-that") rm -f "$dir/marketplace" ;;
  "plugin install thatpet-wsl@claude-sync-that") touch "$dir/plugin" ;;
  "plugin uninstall thatpet-wsl@claude-sync-that") rm -f "$dir/plugin" ;;
esac
EOF
chmod +x "$fake"
fakeexe="$tmp/thatpet.exe"
touch "$fakeexe"

run() {
  CALLS="$tmp/calls" CLAUDE_BIN="$fake" THATPET_EXE="$fakeexe" HOME="$tmp/home" "$installer" "$@" >"$tmp/out" 2>&1
}
calls() { cat "$tmp/calls" 2>/dev/null; }
has_call() { grep -qF -- "$1" "$tmp/calls"; }

# 1. Fresh install into two config dirs.
: > "$tmp/calls"
run --config-dir "$tmp/a" --config-dir "$tmp/b"
code=$?
if [ "$code" -eq 0 ]; then pass "fresh install exits 0"; else fail "fresh install exit $code: $(cat "$tmp/out")"; fi
for d in a b; do
  if has_call "[$tmp/$d] plugin marketplace add quinnjr/claude-sync-that" && has_call "[$tmp/$d] plugin install thatpet-wsl@claude-sync-that"; then
    pass "adds marketplace and installs into $d"
  else
    fail "missing install calls for $d: $(calls)"
  fi
done

# 2. Re-running updates instead of re-adding.
: > "$tmp/calls"
run --config-dir "$tmp/a"
if has_call "plugin marketplace update claude-sync-that" && has_call "plugin update thatpet-wsl@claude-sync-that" && ! has_call "marketplace add"; then
  pass "re-run updates in place"
else
  fail "re-run calls: $(calls)"
fi

# 3. A same-named marketplace from another source (e.g. a local folder) is replaced.
mkdir -p "$tmp/c"
echo '"source": "directory",
    "path": "/somewhere/else"' > "$tmp/c/marketplace"
: > "$tmp/calls"
run --config-dir "$tmp/c"
if has_call "[$tmp/c] plugin marketplace remove claude-sync-that" && has_call "[$tmp/c] plugin marketplace add quinnjr/claude-sync-that"; then
  pass "replaces a non-GitHub marketplace"
else
  fail "replace calls: $(calls)"
fi

# 4. Default config dir comes from CLAUDE_CONFIG_DIR.
: > "$tmp/calls"
CLAUDE_CONFIG_DIR="$tmp/env" run
if has_call "[$tmp/env] plugin install thatpet-wsl@claude-sync-that"; then pass "honours CLAUDE_CONFIG_DIR"; else fail "env calls: $(calls)"; fi

# 5. Uninstall removes plugin and marketplace.
: > "$tmp/calls"
run --uninstall --config-dir "$tmp/a"
if has_call "[$tmp/a] plugin uninstall thatpet-wsl@claude-sync-that" && has_call "[$tmp/a] plugin marketplace remove claude-sync-that"; then
  pass "uninstall removes plugin and marketplace"
else
  fail "uninstall calls: $(calls)"
fi

# 6. Missing claude fails clearly; unknown option fails.
CALLS="$tmp/calls" CLAUDE_BIN="" HOME="$tmp/nohome" PATH="/usr/bin:/bin" "$installer" >"$tmp/out" 2>&1
code=$?
if [ "$code" -ne 0 ] && grep -q "was not found" "$tmp/out"; then pass "errors when claude is missing"; else fail "missing claude: code=$code $(cat "$tmp/out")"; fi
run --bogus
code=$?
if [ "$code" -ne 0 ] && grep -q "unknown option" "$tmp/out"; then pass "rejects unknown options"; else fail "unknown option: code=$code"; fi

# 7. Works when piped into bash (curl | bash style), and claude never eats the script from stdin.
: > "$tmp/calls"
: > "$tmp/stdin-log"
STDIN_LOG="$tmp/stdin-log" CALLS="$tmp/calls" CLAUDE_BIN="$fake" THATPET_EXE="$fakeexe" HOME="$tmp/home" \
  bash -s -- --config-dir "$tmp/piped1" --config-dir "$tmp/piped2" < "$installer" >"$tmp/out" 2>&1
code=$?
if [ "$code" -eq 0 ] && has_call "[$tmp/piped1] plugin install thatpet-wsl@claude-sync-that" && has_call "[$tmp/piped2] plugin install thatpet-wsl@claude-sync-that"; then
  pass "works piped into bash for every config dir"
else
  fail "piped: code=$code $(cat "$tmp/out") calls: $(calls)"
fi
if [ ! -s "$tmp/stdin-log" ]; then pass "claude gets no stdin"; else fail "claude read stdin: $(head -c 200 "$tmp/stdin-log")"; fi
bash -s -- --help < "$installer" > "$tmp/out" 2>&1
if grep -q -- "--config-dir DIR" "$tmp/out"; then pass "--help works when piped"; else fail "piped help: $(cat "$tmp/out")"; fi

# 8. A failing cmd.exe only warns about ThatPet; the install still succeeds.
mkdir -p "$tmp/badbin"
printf '#!/usr/bin/env bash\nexit 1\n' > "$tmp/badbin/cmd.exe"
chmod +x "$tmp/badbin/cmd.exe"
CALLS="$tmp/calls" CLAUDE_BIN="$fake" HOME="$tmp/home" PATH="$tmp/badbin:$PATH" \
  env -u THATPET_EXE "$installer" --config-dir "$tmp/bad" >"$tmp/out" 2>&1
code=$?
if [ "$code" -eq 0 ] && grep -q "warning" "$tmp/out"; then pass "failing cmd.exe only warns"; else fail "failing cmd.exe: code=$code $(cat "$tmp/out")"; fi

if [ "$failures" -eq 0 ]; then
  echo "all tests passed"
  exit 0
fi
echo "$failures test(s) failed"
exit 1
