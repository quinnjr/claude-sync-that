# claude-sync-that

[![test](https://github.com/quinnjr/claude-sync-that/actions/workflows/test.yml/badge.svg)](https://github.com/quinnjr/claude-sync-that/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A [Claude Code](https://claude.com/claude-code) plugin that lets [ThatPet](https://thatpet.app),
running on Windows, react to Claude Code sessions running inside **WSL**.

ThatPet's own "connect Claude Code" option only reaches Claude Code on the Windows side. If you
run Claude Code in WSL, the pet never hears about it. Install this plugin in WSL and your pet
thinks, works, celebrates, waits for approval and naps for your WSL sessions the same way it
does for Windows ones.

## Install

In your WSL terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/quinnjr/claude-sync-that/main/install.sh | bash
```

Then start a new Claude Code session. Sessions that were already open won't pick up the plugin
until you restart them.

### Requirements

- Windows 10 or 11 with [ThatPet](https://thatpet.app) installed (the default
  `%LOCALAPPDATA%\Programs\ThatPet` location is found automatically)
- WSL 2 with Windows interop on (the default; you can run `cmd.exe` from WSL)
- Claude Code installed inside WSL

### Options

Pass options to the installer after `bash -s --`:

```sh
curl -fsSL https://raw.githubusercontent.com/quinnjr/claude-sync-that/main/install.sh | bash -s -- [options]
```

| Option | What it does |
| --- | --- |
| `--config-dir DIR` | Install into this Claude Code config directory. Repeat it for several profiles. Defaults to `$CLAUDE_CONFIG_DIR`, or `~/.claude`. |
| `--uninstall` | Remove the plugin and its marketplace. |
| `-h`, `--help` | Show help. |

Running the installer again updates the plugin to the latest version.

**Several Claude Code profiles?** Install into each one:

```sh
curl -fsSL https://raw.githubusercontent.com/quinnjr/claude-sync-that/main/install.sh \
  | bash -s -- --config-dir ~/.claude-work --config-dir ~/.claude-personal
```

### Install from inside Claude Code

The installer just wraps Claude Code's plugin commands, so you can also do it by hand:

```
/plugin marketplace add quinnjr/claude-sync-that
/plugin install thatpet-wsl@claude-sync-that
```

## How it works

ThatPet connects to Windows Claude Code by adding hooks that run
`thatpet.exe hook --provider claude` and pass it each hook event as JSON on stdin. This plugin
registers the same 13 hook events in WSL (`SessionStart`, `UserPromptSubmit`, `PreToolUse`,
`PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `Notification`, `SubagentStart`,
`SubagentStop`, `Stop`, `StopFailure`, `PreCompact`, `SessionEnd`) and forwards each one,
unchanged, to the Windows `thatpet.exe` through WSL interop.

```
Claude Code (WSL) ──hook event──▶ forward.sh ──stdin──▶ thatpet.exe (Windows) ──▶ 🐾
```

- **ThatPet does the reacting.** The plugin passes events through and makes no decisions of its
  own, so your pet behaves exactly as it does for Windows sessions and keeps up with ThatPet
  updates.
- **Fast.** One forwarded event takes about 40 ms.
- **Never gets in Claude's way.** If ThatPet isn't installed, interop is off, or anything fails,
  the hook exits quietly and Claude carries on.
- **Finds ThatPet by itself.** The forwarder asks Windows for `%LOCALAPPDATA%`, finds
  `Programs\ThatPet\thatpet.exe` under it, and caches the path in
  `~/.cache/thatpet-wsl/exe-path`. If ThatPet lives somewhere else, set `THATPET_EXE` to its
  WSL path, for example `export THATPET_EXE=/mnt/d/Apps/ThatPet/thatpet.exe`.

### What the pet does with WSL sessions

The same as with Windows sessions, including ThatPet's own lifecycle:

- Starting a session opens ThatPet if it isn't running.
- ThatPet closes itself when the **last** open session ends. That counts Windows and WSL
  sessions together.
- If you quit ThatPet from its menu, hooks won't reopen it until you open it yourself.

Clicking the pet to bring your terminal forward, and the Energy (usage) meter, only work for
Windows sessions.

## Troubleshooting

**The pet doesn't react.**

1. Make sure you started a *new* Claude Code session after installing.
2. Check the plugin is enabled: `claude plugin list` should show `thatpet-wsl@claude-sync-that`
   as enabled.
3. Check WSL can see ThatPet: `ls "$(wslpath -u "$(cmd.exe /c 'echo %LOCALAPPDATA%' 2>/dev/null | tr -d '\r')")/Programs/ThatPet/thatpet.exe"`
4. If you moved ThatPet, delete `~/.cache/thatpet-wsl/exe-path` or set `THATPET_EXE`.

**`cmd.exe: command not found`.** Windows interop or `appendWindowsPath` is turned off in
`/etc/wsl.conf`. The forwarder also tries `/mnt/c/Windows/System32/cmd.exe`, but interop itself
must be on.

## Uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/quinnjr/claude-sync-that/main/install.sh | bash -s -- --uninstall
```

## Development

```
.claude-plugin/marketplace.json        marketplace listing
plugins/thatpet-wsl/
  .claude-plugin/plugin.json           plugin manifest
  hooks/hooks.json                     the 13 hook registrations
  scripts/forward.sh                   forwards one event to thatpet.exe
install.sh                             curl installer
tests/                                 tests for forward.sh and install.sh
```

Run the tests. They use stand-ins for `thatpet.exe` and `claude`, so they never touch your real
pet or Claude Code setup:

```sh
bash tests/forward.test.sh
bash tests/install.test.sh
```

To try local changes, add your checkout as a marketplace:

```sh
claude plugin marketplace add /path/to/claude-sync-that
claude plugin install thatpet-wsl@claude-sync-that
```

## Disclaimer

This is an independent project and isn't affiliated with ThatPet. It doesn't include, modify or
redistribute any part of ThatPet: it only calls the `thatpet.exe hook` command that ThatPet
provides for agent integrations. Get ThatPet and its characters at
[thatpet.app](https://thatpet.app).

## License

[MIT](LICENSE) © 2026 Joseph R. Quinn
