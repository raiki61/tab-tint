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

Unlike the hooks, these two **bypass the state short-circuit**. The Windows side only writes when the state actually changes (see below), but honoring that for a manual invocation means deciding "it should already be on" and writing nothing — while still looking like it succeeded. A tool whose whole job is to show you the look must never silently become a no-op, so a manual toggle always writes, and overwrites the recorded state with the result (without that write-back, a manually darkened terminal would be short-circuited as "still on" and never light up again).

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
- **Windows (Android Studio / IntelliJ built-in terminal): no color change.** JediTerm doesn't implement *setting* via OSC 11 (see below), and nothing on the plugin side can fix that.
- **Windows (VS Code integrated terminal): applied, but not retained.** The terminal does apply it, then resets to the theme default on tab switches and theme re-application ([vscode#312815](https://github.com/microsoft/vscode/issues/312815)). The tint is re-asserted at the start of every turn (see below).

Both macOS's `ttysNNN` and Linux's `pts/N` naming are handled, but CI only verifies the script's exit codes, state-file handling, and JSON validity on Linux/macOS/Windows — it can't test the actual background color change on real hardware.

### Where the bytes go on Windows

On Windows there is no pty a hook can walk to. `/dev/tty` fails to open with `ENXIO`, and the `ps` bundled with Git Bash doesn't implement `-o` at all (`ps: unknown option -- o`), so walking the process tree isn't possible either. **Those two facts alone mean the pty-resolving code can never succeed on Windows.**

Instead the bytes go to the console device `CON`. There are two traps here as well.

- Redirecting to `> CON` from bash just **creates a real file named `CON` in the cwd** — nothing reaches the terminal.
- `cmd` refuses `CONOUT$` as a redirection target (`ERROR_INVALID_NAME`).

What does work is `cmd`'s `copy /b <file> CON`. Opening `CONOUT$` and calling `WriteConsoleW` works equally well, but the `cmd` route needs no extra executable, so that's what's used.

On Windows each write costs a `cmd` launch (a few hundred ms in some environments). `PreToolUse` fires on every single tool call, so the current state is tracked per `CLAUDE_CODE_SESSION_ID` and the write only happens **when the state actually changes**. If a write never lands, it isn't retried for the rest of that session (so a terminal that can't receive it doesn't cost a few hundred ms per tool call; `SessionEnd` clears the state, so the next session tries again). The POSIX side keeps no state, because there a write is essentially free.

There is one exception. **`UserPromptSubmit` (the start of a turn) always rewrites, even when the state is unchanged.** A terminal can take the colour back after it was applied: VS Code resets to the theme default on tab switches and theme re-application ([vscode#312815](https://github.com/microsoft/vscode/issues/312815)). Honoring the short-circuit there would leave the terminal uncolored until the next on/off transition. The cost is one `cmd` launch per turn — the `PreToolUse` short-circuit, which fires on every tool call, is untouched. Terminals already known to be out of reach (`unsupported`) don't pay for the rewrite either.

The state lives in a fixed location, `%LOCALAPPDATA%\Temp\tab-tint` (`TAB_TINT_STATE_DIR` overrides it, for tests). It deliberately does *not* use the plugin's `CLAUDE_PLUGIN_DATA` directory: that variable is handed to hooks but **not** to the manual commands, which run through the Bash tool. Reading it would split the state across two directories — sharing state in name only, so a manual "off" would leave the hook convinced it is still on. `CLAUDE_CODE_SESSION_ID` *is* present in both contexts, so the file name never splits.

`hooks.json` prefixes the command with `bash "..."` to work around a known issue where a hook pointing at a `.sh` script isn't always run through bash ([#21847](https://github.com/anthropics/claude-code/issues/21847)).

### ConPTY swallows nothing (measured)

**It is not that the bytes fail to reach the terminal. They arrive, and then the terminals differ.**

This section used to claim that a local Windows ConPTY consumes OSC 11. **That was wrong.** Creating a ConPTY, running `cmd /c copy /b <file> CON` inside it (exactly what this plugin does) and reading the ConPTY's output pipe directly shows all three implementations forwarding it verbatim.

| ConPTY implementation | OSC 11 | DECSCNM (`CSI ?5h`) |
| --- | --- | --- |
| OS (`kernel32!CreatePseudoConsole`) | forwarded | forwarded |
| Android Studio / IntelliJ (`lib/pty4j/win/x86-64/conpty.dll`) | forwarded | forwarded |
| VS Code (node-pty, `1.25.2603.03002`) | forwarded | forwarded |

```
<ESC>[1t<ESC>[c<ESC>[?1004h<ESC>[?9001h<ESC>]11;#004a00<BEL>
                                       ^^^^^^^^^^^^^^^^^^^^ straight out of the output pipe
```

This measurement needs no terminal, no screenshot and no human eye. The earlier negative conclusion came from reading the `GetConsoleScreenBufferInfoEx` colour table — which holds **only 16 colours**. OSC 11 rewrites palette entry **262**, the alias for the default background, so it can never show up there ([microsoft/terminal discussion #14142](https://github.com/microsoft/terminal/discussions/14142)).

### What each terminal does with it

**Android Studio / IntelliJ: JediTerm doesn't implement *setting* via OSC 11.** [`doProcessOsc()` in JediEmulator.java](https://github.com/JetBrains/jediterm/blob/master/core/src/com/jediterm/terminal/emulator/JediEmulator.java) reads:

```java
case 10:
case 11:
  return processColorQuery(args);   // only answers '?'; there is no setter
```

What it handles is OSC 0/1/2 (title), 7 (stub), 8 (hyperlinks), 10/11 (query only), 104 (no-op) and 1341 (custom); **OSC 4 and 12 are unhandled**. The feature has been requested but not implemented ([IJPL-218303](https://youtrack.jetbrains.com/issue/IJPL-218303), still open). It isn't a syntax or terminator problem either — five variants (BEL/ST × `#rrggbb`/`rgb:RR/GG/BB`/16-bit) were tried on real hardware and none had any effect. The embedded terminal's VT emulator is part of the IDE platform, so **no plugin can swap it out** either; the marketplace "terminal" plugins all just launch an external terminal.

**VS Code: applied, but not retained.** Its terminal (xterm.js) [fully supports setting via OSC 11](https://xtermjs.org/docs/api/vtfeatures/), and VS Code itself shipped support in [#139645](https://github.com/microsoft/vscode/issues/139645) on 2021-12-22. But the colour is **reset to the theme default on tab switches (for editor-area terminals) and on theme re-application** ([#312815](https://github.com/microsoft/vscode/issues/312815), open). This plugin re-asserts the tint on every `UserPromptSubmit` to recover from that.

**Only default-background cells are affected.** OSC 11 changes the terminal's *default* background, so the colour lands on cells still drawn with the default background plus the leftover gutter where the character grid doesn't divide evenly. A bare shell (almost entirely default background) turns fully tinted; a full-screen TUI that paints its own cell colours leaves far less surface for it ([opentui#950](https://github.com/anomalyco/opentui/issues/950)). The same reasoning explains why DECSCNM — which JediTerm *does* implement — is barely visible: it swaps the default colours, and those are what the TUI has already overpainted.

IntelliJ-family IDEs offer `-Dcom.pty4j.windows.disable.bundled.conpty=true` via `Help | Edit Custom VM Options` to drop the bundled ConPTY, but since forwarding was never the problem it changes nothing. The cause is on the JediTerm side.

One warning about verifying this: **the measurement method was the most dangerous part.** The conclusion in this section flipped three times, and every time the cause was measuring something that couldn't answer the question.

- Capturing the whole screen and sampling pixels reads whatever window is on top, so the moment the target window loses z-order you measure a different window and conclude "it doesn't work" about a route that does. Per-window `PrintWindow` (with `PW_RENDERFULLCONTENT`) measures independently of z-order.
- The `GetConsoleScreenBufferInfoEx` colour table holds 16 entries; OSC 11 rewrites palette entry 262, so "internal state didn't change either" proves nothing.
- The reliable method is to **create a ConPTY yourself and read its output pipe** — no terminal, no screenshot, no human eye, and it answers exactly one question: was it forwarded? Combined with a `ReadConsoleOutputCharacterW` read-back, "did the write land" and "did it reach the terminal" become separate, independently answerable questions.

## Testing

```bash
bash tests/run.sh
```

Verifies that `on`/`off` exit quietly and successfully even in environments with no pty (e.g. CI), that an invalid argument is rejected with exit 1, and that each of the plugin's JSON files is well-formed.
