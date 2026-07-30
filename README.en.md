# tab-tint

[![test](https://github.com/raiki61/tab-tint/actions/workflows/test.yml/badge.svg)](https://github.com/raiki61/tab-tint/actions/workflows/test.yml)

[日本語](README.md) | **English**

A Claude Code plugin. **Tints the terminal background a subdued color while Claude is actively working (generating a response), and reverts it the moment it stops — whether that's because you're reading the reply or it's genuinely waiting on you.**

When you run several Claude Code sessions side by side, a plain notification doesn't tell you which one is actually busy right now. A background tint lets you tell at a glance whether the session you're currently looking at is working or has stopped (it can't show you the color of tabs you aren't looking at, so pairing it with notifications is the practical setup).

The stopped state — reading, waiting, anything not actively generating — always stays your normal, untouched color. The tint only shows up while Claude is working, on purpose: having the terminal change color while you're in the middle of reading a response is distracting, so the color is deliberately confined to the "busy" period instead.

## How it works

- You reply, or work resumes (`UserPromptSubmit` / `PreToolUse`) → tint the background
- A response wraps up, or the session is genuinely left idle (`Stop` / `Notification` = `idle_prompt` / `permission_prompt`) → revert to normal
- The session ends (`SessionEnd`) → revert it as a safety net

A hook runs as a subprocess of Claude Code and has no controlling terminal of its own. So it walks up the process tree to find the real pty (`ttysNNN` / `pts/N`) and writes OSC 11 (set background color) / OSC 111 (reset) directly to it.

### The design principle: what this actually measures

tab-tint measures exactly one thing: **can you type into this screen's input box right now?** It does not measure "does this need attention" or "is something important in progress."

That line is drawn on purpose. Kick off a background task — a subagent via `/code-review`, say — and the interactive turn itself completes, `Stop` fires, and the color reverts to normal. Work is still happening behind the scenes, so this can look like a bug at first. It isn't: input to this screen was never blocked, so you could send another message right away, and that's the only thing the color is supposed to reflect. Trying to track every kind of "something is happening" — wiring up `SubagentStart`/`SubagentStop`/`TaskCreated`/`TaskCompleted` and the rest — adds real state-tracking complexity and, worse, actually drifts away from the one thing this is meant to answer. When in doubt, judge by that single question alone: can you type here right now?

## Manual toggle

Commands for switching on the spot, without waiting for the automatic on/off.

```
/tab-tint:off   # revert right now
/tab-tint:on    # light it up right now (for previewing the look)
```

Note that this works differently from the hooks. Hooks (`Notification` / `Stop`, etc.) are deterministic processes registered directly with the OS — they run instantly and for free, without involving the AI. This command, however, is a skill, so **Claude (the AI) reads the instructions in `SKILL.md` and decides to call the Bash tool** — that's a full conversational turn. It takes a few seconds and costs tokens. Using it for every single wait isn't practical; it's meant as a manual override for when you need it right now.

Given how Claude Code is built, there's no way to make a command that a user can invoke on demand *and* that runs deterministically without the AI (skills/commands are always interpreted by the AI; hooks only fire on lifecycle events and can't be invoked on demand; keybindings can only reassign fixed built-in actions, not run arbitrary commands).

## Install

```
/plugin marketplace add raiki61/tab-tint
/plugin install tab-tint
/reload-plugins
```

No setup needed — it works the moment it's installed.

Personally-distributed marketplaces have auto-update disabled by default, so without further action you stay pinned to whatever version you installed. To keep up to date, do one of the following.

- Update manually: `/plugin marketplace update tab-tint` → `/reload-plugins`
- Track it automatically: `/plugin` → **Marketplaces** tab → select `tab-tint` → **Enable auto-update** (Claude Code then checks for updates a while after each session starts, and shows a notification prompting `/reload-plugins` if one is found)

## Configuration

The default color is a subdued dark slate tone (`#2a2a2e`) chosen not to stand out too much. Override it with an environment variable if you'd like something else.

```bash
export TAB_TINT_COLOR="#123456"
```

### Why this color

The tint only shows while Claude is working, and reverts once it stops — so it's never in front of you while you're actually reading. Even so, it appears on essentially every turn, so the priority wasn't "an attention-grabbing warning color" but "a color that's unremarkable to see often."

Candidates considered, and the reasoning:

- **Neutral gray (chosen, `#2a2a2e`)**: a study directly comparing reading comfort on screen found gray backgrounds more comfortable than white or black ones ([Visual comfort models based on coloured text and neutral background combinations](https://www.sciencedirect.com/science/article/abs/pii/S0042698924001688)). Having no particular hue also means it's unlikely to clash with whatever color scheme any given user's terminal already has, which matters for something distributed to strangers.
- **Warm charcoal (`#2e2b28`, selectable via the env var)**: based on the f.lux-style finding that lower color temperature (shifted toward yellow) reduces eye strain. That research, though, is mostly about reducing blue light at night before sleep, not about daytime reading comfort during work specifically.
- **Cool tones (a Solarized-style dark teal or blue-gray, not chosen)**: I looked at Solarized's design philosophy (keep brightness contrast low while preserving hue contrast; cool tones are said to support deep concentration), but weighed against it a more direct piece of reading-comfort research suggesting that hue itself barely affects comfort and that the text/background contrast relationship matters far more — so the case for cool tones was weaker.
- A near-pure warm hue (red) was avoided. It reads too easily as a warning color, and testing it in practice got the verdict "too much."

## Supported environments

OSC 11/111 aren't a proprietary extension of any one terminal — they're standard escape sequences, so this should work on essentially any terminal that supports them.

- **Confirmed working**: VS Code's integrated terminal (macOS)
- **Should work (untested)**: iTerm2, kitty, and VTE-based terminals such as GNOME Terminal (Linux/macOS)
- **Windows (Windows Terminal): works.** The background really does change.
- **Windows (Android Studio / IntelliJ built-in terminal, VS Code integrated terminal): no color change.** Not because of the terminal itself — the ConPTY host in front of it swallows OSC 11 (see below).

Both macOS's `ttysNNN` and Linux's `pts/N` naming are handled, but CI only verifies the script's exit codes, state-file handling, and JSON validity on Linux/macOS/Windows — it can't test the actual background color change on real hardware.

### Where the bytes go on Windows

On Windows there is no pty a hook can walk to. `/dev/tty` fails to open with `ENXIO`, and the `ps` bundled with Git Bash doesn't implement `-o` at all (`ps: unknown option -- o`), so walking the process tree isn't possible either. **Those two facts alone mean the pty-resolving code can never succeed on Windows.**

Instead the bytes go to the console device `CON`. There are two traps here as well.

- Redirecting to `> CON` from bash just **creates a real file named `CON` in the cwd** — nothing reaches the terminal.
- `cmd` refuses `CONOUT$` as a redirection target (`ERROR_INVALID_NAME`).

What does work is `cmd`'s `copy /b <file> CON`. Opening `CONOUT$` and calling `WriteConsoleW` works equally well, but the `cmd` route needs no extra executable, so that's what's used.

On Windows each write costs a `cmd` launch (a few hundred ms in some environments). `PreToolUse` fires on every single tool call, so the current state is tracked per `CLAUDE_CODE_SESSION_ID` and the write only happens **when the state actually changes**. If a write never lands, it isn't retried for the rest of that session (so a terminal that can't receive it doesn't cost a few hundred ms per tool call; `SessionEnd` clears the state, so the next session tries again). The POSIX side keeps no state, because there a write is essentially free.

`hooks.json` prefixes the command with `bash "..."` to work around a known issue where a hook pointing at a `.sh` script isn't always run through bash ([#21847](https://github.com/anthropics/claude-code/issues/21847)).

### On Windows, whether it works is decided by the ConPTY host

Whether the bytes reach the terminal is decided not by the terminal's own capabilities but by **whether the `OpenConsole.exe` the terminal bundles forwards OSC 11**. This was measured.

Opening `CONOUT$` from the same context a hook runs in (a Claude Code subprocess):

```
mode=0x0007 VT=True                  <- VT processing is enabled
WriteConsoleW(text)  ok=True         <- text does land in the visible buffer (read back to confirm)
WriteConsoleW(osc11) ok=True
before: attr=0x0007 table0=0x0C0C0C
after:  attr=0x0007 table0=0x0C0C0C  <- OSC 11 vanishes without even changing internal state
```

Text arrives; only OSC 11 disappears. The console is swallowing it.

- **Windows Terminal**: its bundled `OpenConsole.exe` forwards OSC 10/11/12 to the terminal. **Works.**
- **Android Studio / IntelliJ**: pty4j's bundled `OpenConsole.exe` (`lib/pty4j/win/x86-64/`). **Swallows it.**
- **VS Code**: node-pty's bundled `OpenConsole.exe`. **Swallows it.**

Note this is separate from terminal support. VS Code's terminal (xterm.js) fully supports OSC 11, and opening an SSH session to macOS in VS Code does change the background. It only fails when the bytes pass through a local Windows ConPTY. JediTerm has an open request for OSC 11 too ([IJPL-218303](https://youtrack.jetbrains.com/projects/IJPL/issues/IJPL-218303/Support-OSC-11-escape-sequence-for-dynamic-terminal-background-colors)), but in this environment the sequence dies before it ever gets there.

One warning about verifying this: **the measurement method was the most dangerous part.** Capturing the whole screen and sampling pixels reads whatever window is on top, so the moment the target window loses z-order you measure a different window and conclude "it doesn't work" about a route that does. Per-window `PrintWindow` (with `PW_RENDERFULLCONTENT`) measures independently of z-order.

## Testing

```bash
bash tests/run.sh
```

Verifies that `on`/`off` exit quietly and successfully even in environments with no pty (e.g. CI), that an invalid argument is rejected with exit 1, and that each of the plugin's JSON files is well-formed.
