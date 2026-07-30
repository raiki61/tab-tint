# tab-tint

[![test](https://github.com/raiki61/tab-tint/actions/workflows/test.yml/badge.svg)](https://github.com/raiki61/tab-tint/actions/workflows/test.yml)

> **English** — A Claude Code plugin that tints the terminal background while Claude is waiting for your input, and clears it the moment you reply or Claude resumes working. Useful when you run several Claude Code sessions side by side and want to tell at a glance which one is idle. Uses the standard OSC 11/111 escape sequences, so it isn't tied to one terminal emulator — confirmed working in VS Code's integrated terminal; iTerm2, kitty, and VTE-based terminals (GNOME Terminal etc.) support the same sequences. README is Japanese-first; ask Claude to translate if you need it.

Claude Codeのプラグイン。**応答待ちの間だけターミナル背景を控えめな色に変え、返信・作業再開で自動的に戻す。**

複数のClaude Codeセッションを並行して開いていると、通知だけでは「どれが待ち状態か」が分かりにくい。デスクトップ通知は今見ているタブ以外でも気づけるが、クリックして初めて「あ、これだった」となる。逆にタブの背景色は、今見ているセッションが本当に待っているかどうかを一目で確認できる（ただし裏タブの色までは見えないので、通知と組み合わせるのが実用的）。

## しくみ

- 応答が一段落した（`Stop`）／本当に放置されて待ち状態になった（`Notification` = `idle_prompt`／`permission_prompt`）→ 背景色を変える
- 返信した・作業が動き出した（`UserPromptSubmit` / `PreToolUse`）→ 元に戻す
- セッションを終了した（`SessionEnd`）→ 念のため元に戻す

`Stop`は応答のたびに毎回発火するため、色が強すぎると「読んでいる間」も光って気が散ることがある。デフォルトの色（控えめな`#2a2a2e`）ならその心配は薄いのでデフォルトで有効にしているが、気になる場合は`Stop`での点灯だけをオフにできる。

```bash
export TAB_TINT_ON_STOP=0
```

hookはClaude Codeのサブプロセスとして動き、素の制御端末を持たない。そのためプロセスツリーを遡って実際のpty（`ttysNNN` / `pts/N`）を見つけてから、OSC 11（背景色設定）/ OSC 111（リセット）を直接書き込んでいる。

## インストール

```
/plugin marketplace add raiki61/tab-tint
/plugin install tab-tint
/reload-plugins
```

セットアップは要らない。入れたらすぐ動く。

個人配布のマーケットプレイスは自動更新がデフォルトOFFなので、何もしないとインストール時点のバージョンに固定される。更新を追いたい場合は次のどちらか。

- 手動で更新: `/plugin marketplace update tab-tint` → `/reload-plugins`
- 自動追従にする: `/plugin` → **Marketplaces** タブ → `tab-tint` を選び **Enable auto-update**（以降はセッション起動後しばらくして自動チェックが入り、更新があれば`/reload-plugins`を促す通知が出る）

## 設定

デフォルトの色は目立ちすぎない暗いスレートーン（`#2a2a2e`）。変えたい場合は環境変数で上書きできる。

```bash
export TAB_TINT_COLOR="#123456"
```

## 対応環境

OSC 11/111はターミナル固有の拡張ではなく標準的なエスケープシーケンスなので、対応するターミナルなら基本的にどれでも動く。

- **動作確認済み**: VS Code統合ターミナル（macOS）
- **対応しているはず（未検証）**: iTerm2、kitty、GNOME Terminal等のVTEベース端末（Linux/macOS）
- **Windows**: Git BashなどでOSC 11/111自体には対応した端末（Windows Terminal等）が必要。加えてClaude Code側に、hookが指す`.sh`スクリプトをbash経由で実行しないことがある既知の問題があるため（[#21847](https://github.com/anthropics/claude-code/issues/21847)）、`hooks.json`では`bash "..."`を明示的に前置している。実機未検証

macOSの`ttysNNN`・Linuxの`pts/N`どちらの命名も扱うが、CIではLinux/macOS/Windows上でスクリプトの終了コードとJSON妥当性のみ検証しており、実機での色変化そのものはテストできていない。

## 動作確認

```bash
bash tests/run.sh
```

ptyが見つからない環境（CI等）でも`on`/`off`が静かに正常終了すること、不正な引数を渡したときにexit 1で拒否すること、プラグインの各JSONファイルが妥当な形式であることを検証する。
