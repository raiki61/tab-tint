---
description: tab-tintの背景色を今すぐ元に戻す
disable-model-invocation: true
---

以下をBashツールで実行して、tab-tintの背景色を元に戻してください。

```bash
script="${CLAUDE_PLUGIN_ROOT}/hooks/tab-tint.sh"
[ -x "$script" ] || script=$(find ~/.claude/plugins -type f -name tab-tint.sh 2>/dev/null | head -1)
bash "$script" off
```

実行したら「背景色を元に戻しました」とだけ報告してください。長い説明は不要です。
