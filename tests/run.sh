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

# CIにはptyが無いのでresolve_tty側で常にexit 0になり、stopゲート自体の
# 分岐(TAB_TINT_ON_STOP有無)を出口コードだけでは判別できない。ここでは
# 追加した引数(source)を渡してもクラッシュしないことだけ検証する。
out=$(hooks/tab-tint.sh on stop < /dev/null 2>&1); rc=$?
check "'on stop' (デフォルト=有効) never errors out" "0" "$rc"

out=$(TAB_TINT_ON_STOP=0 hooks/tab-tint.sh on stop < /dev/null 2>&1); rc=$?
check "'on stop' with TAB_TINT_ON_STOP=0 never errors out" "0" "$rc"

out=$(hooks/tab-tint.sh bogus < /dev/null 2>&1); rc=$?
check "invalid arg exits 1" "1" "$rc"
check "invalid arg prints usage" "true" "$(echo "$out" | grep -q '^usage:' && echo true || echo false)"

for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json hooks/hooks.json skills/off/SKILL.md skills/on/SKILL.md README.md README.en.md; do
  check "$f exists" "true" "$([ -f "$f" ] && echo true || echo false)"
done

for f in skills/off/SKILL.md skills/on/SKILL.md; do
  check "$f has frontmatter description" "true" "$(head -1 "$f" | grep -q '^---$' && grep -q '^description:' "$f" && echo true || echo false)"
done

PYTHON=$(command -v python3 || command -v python)
for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json hooks/hooks.json; do
  check "$f is valid JSON" "true" "$("$PYTHON" -c "import json,sys; json.load(open('$f', encoding='utf-8'))" 2>/dev/null && echo true || echo false)"
done

echo "---"
echo "pass: $pass, fail: $fail"
[ "$fail" -eq 0 ]
