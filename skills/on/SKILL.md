---
description: tab-tintの背景色を今すぐ試しに点灯する（見た目の確認用）
disable-model-invocation: true
---

以下をBashツールで実行して、tab-tintの背景色を点灯してください。

```bash
script="${CLAUDE_PLUGIN_ROOT}/hooks/tab-tint.sh"
[ -x "$script" ] || script=$(find ~/.claude/plugins -type f -name tab-tint.sh 2>/dev/null | head -1)
bash "$script" on
```

実行したら「背景色を点灯しました」とだけ報告してください。長い説明は不要です。
