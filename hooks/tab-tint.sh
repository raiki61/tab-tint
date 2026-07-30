#!/bin/bash
# Claude Codeが作業中(応答生成中)の間だけ、そのセッションのターミナル背景を
# 控えめな色にする。止まっている間(読んでいる間・待っている間)は常に
# いつもの色のまま。
#
# hookはClaude Codeのサブプロセスとして動くため素の制御端末を持たない。
# OSC 11/111の書き込み先の見つけ方がOSで違うので、そこだけを差し替えている:
#   POSIX   … プロセスツリーを遡って実際のpty(ttysNNN/pts/N)を見つけ、そこへ書く
#   Windows … ptyが見えないのでコンソールデバイス(CON)へ書く
set -euo pipefail

WORKING_COLOR="${TAB_TINT_COLOR:-#2a2a2e}"

is_windows() { [ "${OS:-}" = "Windows_NT" ]; }

# エスケープシーケンスを標準出力へ。$()を使わないのは、Windowsではプロセス生成が
# 重く(環境によっては数百ms)、hookが毎ツール呼び出しで走るため。
emit_seq() {
  case "$1" in
    on)  printf '\033]11;%s\007' "$WORKING_COLOR" ;;
    off) printf '\033]111\007' ;;
  esac
}

# ---- POSIX ----

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

posix_write() {
  local tty_path
  tty_path=$(resolve_tty) || return 1
  [ -w "$tty_path" ] || return 1
  emit_seq "$1" > "$tty_path"
}

# ---- Windows ----
#
# hookから辿れるptyが無い。/dev/ttyはENXIOで開けず、Git Bash同梱のpsは-o自体を
# 実装していない(`ps: unknown option -- o`)のでプロセスツリーも遡れない。残るのは
# コンソールデバイスへの直接書き込みだが、ここにも罠が2つある:
#   - bashから`> CON`すると、CONという名前の実ファイルがcwdに作られるだけで届かない
#   - cmdはCONOUT$をリダイレクト先として受け付けない(ERROR_INVALID_NAME)
# 通るのはcmdの`copy /b <file> CON`。Windows Terminalで実際に背景色が変わることを
# 確認済み(計測はPrintWindow。画面合成を撮ると前面のウィンドウを測ってしまう)。

# 状態の置き場。hookと手動コマンド(/tab-tint:on)で必ず同じ場所を見る必要がある。
# ここでCLAUDE_PLUGIN_DATAを見てはいけない——hookには渡るが、スキルはBashツールから
# 走るので渡らない。置き場が2つに割れると、手動で消灯した画面をhookが「まだonだ」と
# 思い込んで二度と点けなくなる（状態を共有しているつもりで共有できていない)。
# 状態は使い捨てなのでTempで足りる。セッション終了時に消す。
#
# バックスラッシュのままではbash側のファイル操作が通らないので、正規化して
# 前スラッシュで持つ。cmdへ渡す直前にだけ戻す。
win_state_dir() {
  local dir="${TAB_TINT_STATE_DIR:-${LOCALAPPDATA}/Temp/tab-tint}"
  printf '%s' "${dir//\\//}"
}

win_state_file() {
  printf '%s/state-%s' "$(win_state_dir)" "${CLAUDE_CODE_SESSION_ID:-shared}"
}

win_save_state() {
  local state_file="$1" value="$2"
  mkdir -p "$(dirname "$state_file")" 2>/dev/null || return 1
  printf '%s\n' "$value" > "$state_file" 2>/dev/null || true
}

win_write() {
  local action="$1" dir seq_file win_path
  dir=$(win_state_dir)
  # 消灯(OSC 111)に色は入らないので、色ごとに分けるのは点灯側だけ
  case "$action" in
    on)  seq_file="$dir/seq-on-${WORKING_COLOR//[^0-9A-Za-z]/}.bin" ;;
    off) seq_file="$dir/seq-off.bin" ;;
  esac
  if [ ! -s "$seq_file" ]; then
    mkdir -p "$dir" 2>/dev/null || return 1
    emit_seq "$action" > "$seq_file" 2>/dev/null || return 1
  fi
  win_path="${seq_file//\//\\}"
  # 呼び出し方に2つ落とし穴がある。どちらも「成功したように見えて何もしない」
  # 形になるので注意:
  #   - msysの引数変換を止める(MSYS_NO_PATHCONV/MSYS2_ARG_CONV_EXCL)必要がある。
  #     止めないとWindowsパスが書き換えられる。ただし止めると`//c`→`/c`の変換も
  #     効かなくなるので、スイッチは`/c`を直接渡す。`//c`のまま渡すとcmdは
  #     スイッチとして解釈せず対話起動して即終了し、copyを実行しないのに
  #     exit 0を返す
  #   - コマンド全体を1つの文字列にまとめてはいけない。`cmd /c "... \"path\" ..."`
  #     の形だとcmdに`\"`がリテラルで渡り(cmdはバックスラッシュエスケープを
  #     解釈しない)ERROR_INVALID_NAMEになる。トークンごとに別の引数で渡せば
  #     空白入りパスも通る
  MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' \
    cmd.exe /c copy /b "$win_path" CON >/dev/null 2>&1
}

# ---- 本体 ----

action="${1:-}"
source_event="${2:-}"

case "$action" in
  on|off) ;;
  *) echo "usage: $0 {on|off} [source]" >&2; exit 1 ;;
esac

# 手動での切り替え(/tab-tint:on, /tab-tint:off)は必ず書きに行く。状態の短絡に
# 任せると「もうonだ」「この端末はunsupportedだ」と判断して何も書かず、それでも
# 成功したように見えてしまう。見た目を確認するための道具が黙ってno-opになるのは
# 最悪なので、ここだけ短絡を外す。
#
# 書いたあとは状態も上書きする。書き戻さないと、手動で消灯した画面をhookが
# 「まだonのはずだ」と短絡して二度と点けない。
if [ "$source_event" = "force" ]; then
  if ! is_windows; then
    posix_write "$action" || true
    exit 0
  fi
  if win_write "$action"; then
    win_save_state "$(win_state_file)" "$action"
  else
    win_save_state "$(win_state_file)" "unsupported"
  fi
  exit 0
fi

if ! is_windows; then
  posix_write "$action" || exit 0
  exit 0
fi

# Windowsは1回の書き込みにcmdの起動が要る。PreToolUseは毎ツール呼び出しで発火する
# ので、状態が変わらないときに起動しないだけで体感がまるごと変わる。POSIX側は
# 書き込みが実質無償なので、この短絡は入れない(挙動を変えないため)。
state_file="$(win_state_file)"
prev=""
if [ -r "$state_file" ]; then
  read -r prev < "$state_file" || true
fi

# 一度も届かなかった端末では以降試さない。届かない環境で毎ツール数百msを
# 払い続けるのを避ける。セッション終了時に状態を消すので次回は再挑戦する。
if [ "$prev" = "unsupported" ]; then
  exit 0
fi

# ターンの頭(UserPromptSubmit)だけは、状態が同じでも書き直す。効いた色を端末側が
# 取り上げてしまうことがあるため——VS Codeはタブ切り替えとテーマ再適用のたびに
# 既定色へ戻す(microsoft/vscode#312815)。短絡に任せると次にon/offが切り替わるまで
# 色が戻らないので、ターンごとに1回だけ書き直して復帰させる。毎ツール発火する
# PreToolUseの短絡はそのまま残す(cmdの起動コストを毎回払わないため)。
if [ "$prev" = "$action" ] && [ "$source_event" != "prompt" ]; then
  [ "$source_event" = "end" ] && rm -f "$state_file" 2>/dev/null
  exit 0
fi

if win_write "$action"; then
  new_state="$action"
else
  new_state="unsupported"
fi

if [ "$source_event" = "end" ]; then
  rm -f "$state_file" 2>/dev/null || true
else
  win_save_state "$state_file" "$new_state" || exit 0
fi
