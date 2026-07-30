---
description: tab-tintの背景色を今すぐ試しに点灯する（見た目の確認用）
disable-model-invocation: true
---

以下をBashツールで実行して、tab-tintの背景色を点灯してください。

```bash
script="${CLAUDE_PLUGIN_ROOT:-}/hooks/tab-tint.sh"
[ -f "$script" ] || script=$(ls -t ~/.claude*/plugins/{cache/*/*/*,marketplaces/*}/hooks/tab-tint.sh 2>/dev/null | head -1)
[ -n "$script" ] || { echo "tab-tint.sh が見つかりません"; exit 1; }
echo "using: $script"
bash "$script" on force
```

実行したら「背景色を作業中の色に変えました」とだけ報告してください。長い説明は不要です。
スクリプトが見つからなかった場合だけ、その旨を報告してください。
