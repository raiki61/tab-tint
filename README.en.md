# tab-tint

[![test](https://github.com/raiki61/tab-tint/actions/workflows/test.yml/badge.svg)](https://github.com/raiki61/tab-tint/actions/workflows/test.yml)

[日本語](README.md) | **English**

A Claude Code plugin. **Tints the terminal background a subdued color while a response is wrapping up or you're genuinely waiting, and clears it automatically the moment you reply or work resumes.**

When you run several Claude Code sessions side by side, a plain notification doesn't tell you which one is actually waiting. A desktop notification can reach you even when you're looking at a different tab, but you only find out which session it was once you click through. A background tint, on the other hand, lets you tell at a glance whether the session you're currently looking at is really waiting (it can't show you the color of tabs you aren't looking at, so pairing it with notifications is the practical setup).

## How it works

- When a response wraps up (`Stop`), or the session is genuinely left idle (`Notification` = `idle_prompt` / `permission_prompt`) → tint the background
- When you reply or work resumes (`UserPromptSubmit` / `PreToolUse`) → revert it
- When the session ends (`SessionEnd`) → revert it as a safety net

`Stop` fires on every single response, so if the color were too strong it would be distracting even while you're reading. The default color is subdued (`#2a2a2e`) enough that this isn't a real concern, so it's enabled by default — but if it still bothers you, you can turn off just the `Stop` trigger.

```bash
export TAB_TINT_ON_STOP=0
```

A hook runs as a subprocess of Claude Code and has no controlling terminal of its own. So it walks up the process tree to find the real pty (`ttysNNN` / `pts/N`) and writes OSC 11 (set background color) / OSC 111 (reset) directly to it.

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

Because `Stop` is enabled by default alongside genuine idle detection, **this color shows up while you're reading the response too** — it's effectively the default reading experience for almost every turn. So the priority wasn't "an attention-grabbing warning color" but "a color that doesn't tire you out to read against."

Candidates considered, and the reasoning:

- **Neutral gray (chosen, `#2a2a2e`)**: a study directly comparing reading comfort on screen found gray backgrounds more comfortable than white or black ones ([Visual comfort models based on coloured text and neutral background combinations](https://www.sciencedirect.com/science/article/abs/pii/S0042698924001688)). Having no particular hue also means it's unlikely to clash with whatever color scheme any given user's terminal already has, which matters for something distributed to strangers.
- **Warm charcoal (`#2e2b28`, selectable via the env var)**: based on the f.lux-style finding that lower color temperature (shifted toward yellow) reduces eye strain. That research, though, is mostly about reducing blue light at night before sleep, not about daytime reading comfort during work specifically.
- **Cool tones (a Solarized-style dark teal or blue-gray, not chosen)**: I looked at Solarized's design philosophy (keep brightness contrast low while preserving hue contrast; cool tones are said to support deep concentration), but weighed against it a more direct piece of reading-comfort research suggesting that hue itself barely affects comfort and that the text/background contrast relationship matters far more — so the case for cool tones was weaker.
- A near-pure warm hue (red) was avoided. It reads too easily as a warning color, and testing it in practice got the verdict "too much."

## Supported environments

OSC 11/111 aren't a proprietary extension of any one terminal — they're standard escape sequences, so this should work on essentially any terminal that supports them.

- **Confirmed working**: VS Code's integrated terminal (macOS)
- **Should work (untested)**: iTerm2, kitty, and VTE-based terminals such as GNOME Terminal (Linux/macOS)
- **Windows**: needs a terminal that supports OSC 11/111 itself (e.g. Windows Terminal) via something like Git Bash. On top of that, Claude Code has a known issue where a hook pointing at a `.sh` script isn't always run through bash ([#21847](https://github.com/anthropics/claude-code/issues/21847)), so `hooks.json` explicitly prefixes the command with `bash "..."`. Not tested on real hardware.

Both macOS's `ttysNNN` and Linux's `pts/N` naming are handled, but CI only verifies the script's exit codes and JSON validity on Linux/macOS/Windows — it can't test the actual background color change on real hardware.

## Testing

```bash
bash tests/run.sh
```

Verifies that `on`/`off` exit quietly and successfully even in environments with no pty (e.g. CI), that an invalid argument is rejected with exit 1, and that each of the plugin's JSON files is well-formed.
