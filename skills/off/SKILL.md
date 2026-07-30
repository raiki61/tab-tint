---
description: tab-tintの背景色を今すぐ元に戻す
disable-model-invocation: true
---

以下をBashツールで実行して、tab-tintの背景色を元に戻してください。

```bash
script="${CLAUDE_PLUGIN_ROOT:-}/hooks/tab-tint.sh"
[ -f "$script" ] || script=$(ls -t ~/.claude*/plugins/{cache/*/*/*,marketplaces/*}/hooks/tab-tint.sh 2>/dev/null | head -1)
[ -n "$script" ] || { echo "tab-tint.sh が見つかりません"; exit 1; }
echo "using: $script"
bash "$script" off force
```

実行したら「背景色を元に戻しました」とだけ報告してください。長い説明は不要です。
スクリプトが見つからなかった場合だけ、その旨を報告してください。
