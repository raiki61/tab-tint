#!/bin/bash
# Claude Codeが応答待ちの間だけ、そのセッションのターミナル背景を控えめな色にする。
# hookはclaudeのサブプロセスとして動くため制御端末を持たず、プロセスツリーを
# 遡って実際のpty(ttysNNN/pts/N)を見つけてから直接OSC 11/111を書き込む。
set -euo pipefail

WAIT_COLOR="${TAB_TINT_COLOR:-#3a2a10}"

resolve_tty() {
  local pid=$PPID
  for _ in 1 2 3 4 5 6 7 8; do
    read -r ppid tty_dev < <(ps -o ppid=,tty= -p "$pid" 2>/dev/null) || return 1
    case "$tty_dev" in
      ttys*|pts/*) printf '/dev/%s' "$tty_dev"; return 0 ;;
    esac
    [ -z "${ppid:-}" ] && return 1
    pid="$ppid"
  done
  return 1
}

case "${1:-}" in
  on|off) ;;
  *) echo "usage: $0 {on|off} [source]" >&2; exit 1 ;;
esac

# Stopは応答が一段落するたびに毎回発火するため、デフォルトでは無視する
# （返信してすぐ終わったセッションまで「待ち」扱いになってしまうため）。
# TAB_TINT_ON_STOP=1 でオプトインすると、Stopでも点灯するようになる。
if [ "${1}" = "on" ] && [ "${2:-}" = "stop" ] && [ "${TAB_TINT_ON_STOP:-}" != "1" ]; then
  exit 0
fi

tty_path=$(resolve_tty) || exit 0
[ -w "$tty_path" ] || exit 0

case "$1" in
  on)  printf '\033]11;%s\007' "$WAIT_COLOR" > "$tty_path" ;;
  off) printf '\033]111\007' > "$tty_path" ;;
esac
