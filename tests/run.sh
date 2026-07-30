#!/bin/bash
# tab-tint.shの単体テスト。CI環境にはptyが無いため、実際に色が変わることまでは
# 検証できない。代わりに「ptyが見つからない環境では静かに何もせず正常終了する」
# ことと、引数のバリデーションを検証する。
set -uo pipefail
cd "$(dirname "$0")/.."

pass=0
fail=0

check() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $desc (expected [$expected], got [$actual])"
  fi
}

check "script is executable" "true" "$([ -x hooks/tab-tint.sh ] && echo true || echo false)"

# CI runnerには制御端末が無いことが多く、その場合resolve_ttyが失敗して
# exit 0で静かに終了するはず（ptyがある環境ではon/offどちらも正常系として0）。
out=$(hooks/tab-tint.sh on < /dev/null 2>&1); rc=$?
check "'on' never errors out" "0" "$rc"

out=$(hooks/tab-tint.sh off < /dev/null 2>&1); rc=$?
check "'off' never errors out" "0" "$rc"

out=$(hooks/tab-tint.sh bogus < /dev/null 2>&1); rc=$?
check "invalid arg exits 1" "1" "$rc"
check "invalid arg prints usage" "true" "$(echo "$out" | grep -q '^usage:' && echo true || echo false)"

# cmdの呼び出し方の回帰ガード。`//c`のまま渡すとcmdはスイッチとして解釈せず
# 対話起動して即終了し、copyを実行しないのにexit 0を返す——「成功したように
# 見えて何もしない」ので、実機で見るまで気づけない。コマンド全体を1つの文字列に
# まとめる形も、cmdに`\"`がリテラルで渡りERROR_INVALID_NAMEになる。
check "cmd is invoked with a single-slash /c" "true" \
  "$(grep -q 'cmd.exe /c copy /b' hooks/tab-tint.sh && echo true || echo false)"
check "cmd is not invoked with //c" "true" \
  "$(grep -q 'cmd.exe //c' hooks/tab-tint.sh && echo false || echo true)"
check "the copy command is not wrapped in one quoted string" "true" \
  "$(grep -q 'cmd.exe /c "' hooks/tab-tint.sh && echo false || echo true)"

# Windows側だけが状態ファイルを持つ（cmdの起動を状態が変わるときだけに抑えるため）。
# POSIX側は書き込みが実質無償なので状態を持たない——その差をここで固定する。
sd=$(mktemp -d "${TMPDIR:-/tmp}/tab-tint-test.XXXXXX")
run_isolated() {
  TAB_TINT_STATE_DIR="$sd" CLAUDE_CODE_SESSION_ID=test-session \
    hooks/tab-tint.sh "$@" < /dev/null > /dev/null 2>&1
}

if [ "${OS:-}" = "Windows_NT" ]; then
  run_isolated on
  check "windows: state file is written under TAB_TINT_STATE_DIR" "true" \
    "$([ -f "$sd/state-test-session" ] && echo true || echo false)"
  # 端末があれば"on"、届かなければ"unsupported"。どちらでも次回以降を短絡できる値。
  state=$(cat "$sd/state-test-session" 2>/dev/null)
  check "windows: state holds a short-circuitable value" "true" \
    "$([ "$state" = "on" ] || [ "$state" = "unsupported" ] && echo true || echo false)"

  run_isolated on
  check "windows: repeating the same action never errors out" "0" "$?"

  printf 'unsupported\n' > "$sd/state-test-session"
  run_isolated on
  check "windows: 'unsupported' is left untouched" "unsupported" "$(cat "$sd/state-test-session")"

  printf 'on\n' > "$sd/state-test-session"
  run_isolated off end
  check "windows: 'off end' leaves no state file" "false" \
    "$([ -f "$sd/state-test-session" ] && echo true || echo false)"
else
  run_isolated on
  check "posix: no state file is created" "0" \
    "$(find "$sd" -type f | wc -l | tr -d ' ')"
fi
rm -rf "$sd"

for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json hooks/hooks.json skills/off/SKILL.md skills/on/SKILL.md README.md README.en.md; do
  check "$f exists" "true" "$([ -f "$f" ] && echo true || echo false)"
done

for f in skills/off/SKILL.md skills/on/SKILL.md; do
  check "$f has frontmatter description" "true" "$(head -1 "$f" | grep -q '^---$' && grep -q '^description:' "$f" && echo true || echo false)"
done

# WindowsのPATHに載っている /WindowsApps/python3 はMicrosoft Storeを開くだけの
# スタブで、実行すると応答が返らずテストが止まる。実体のあるものだけを選ぶ
# （実行して確かめる方法は、その確認自体がスタブで止まるので使えない）。
pick_python() {
  local name path
  for name in python3 python py; do
    path=$(command -v "$name" 2>/dev/null) || continue
    case "$path" in */WindowsApps/*) continue ;; esac
    printf '%s' "$path"; return 0
  done
  return 1
}

if PYTHON=$(pick_python); then
  for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json hooks/hooks.json; do
    check "$f is valid JSON" "true" "$("$PYTHON" -c "import json,sys; json.load(open('$f', encoding='utf-8'))" 2>/dev/null && echo true || echo false)"
  done
else
  echo "SKIP: no usable python found; JSON validation skipped"
fi

echo "---"
echo "pass: $pass, fail: $fail"
[ "$fail" -eq 0 ]
