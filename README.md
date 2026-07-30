# tab-tint

[![test](https://github.com/raiki61/tab-tint/actions/workflows/test.yml/badge.svg)](https://github.com/raiki61/tab-tint/actions/workflows/test.yml)

**日本語** | [English](README.en.md)

Claude Codeのプラグイン。**Claudeが作業中（応答生成中）の間だけターミナル背景を控えめな色に変え、止まったら（読んでいる間・待っている間）いつもの色に戻す。**

複数のClaude Codeセッションを並行して開いていると、通知だけでは「どれが今動いているか」が分かりにくい。逆にタブの背景色を見れば、今見ているセッションが動いているのか止まっているのかが一目で分かる（ただし裏タブの色までは見えないので、通知と組み合わせるのが実用的）。

止まっている間＝読んでいる間・待っている間は常にいつもの色のままにしてある。応答を読んでいる最中にターミナルの色が変わっていると気が散るため、あえて「動いている間だけ」色を付ける設計にした。

## しくみ

- 返信した・作業が動き出した（`UserPromptSubmit` / `PreToolUse`）→ 背景色を変える
- 応答が一段落した・待ち状態になった（`Stop` / `Notification` = `idle_prompt`／`permission_prompt`）→ いつもの色に戻す
- セッションを終了した（`SessionEnd`）→ 念のためいつもの色に戻す

hookはClaude Codeのサブプロセスとして動き、素の制御端末を持たない。そのためプロセスツリーを遡って実際のpty（`ttysNNN` / `pts/N`）を見つけてから、OSC 11（背景色設定）/ OSC 111（リセット）を直接書き込んでいる。

### 判断基準：何を測っているか

tab-tintが測っているのは**「今この画面の入力欄に書き込めるか」**、それだけ。「注意が必要か」「重要な作業が進んでいるか」は測らない。

これは意図的な線引きで、たとえば`/code-review`のようなバックグラウンドタスク（サブエージェント）を起動すると、対話ターン自体は完了して`Stop`が発火し、色はいつもの色に戻る。裏では作業が続いているのに色が戻るのは一見バグに見えるが、実際にはこの画面への入力はブロックされていない（すぐ次のメッセージを送れる）ので、正しい挙動として扱っている。「進行中の作業を全部拾う」方向に広げると、`SubagentStart`/`SubagentStop`/`TaskCreated`/`TaskCompleted`のような状態を全部追跡する必要が出て複雑になる割に、本来の目的（今書き込めるか）からはむしろ外れる。迷ったときはこの一点（入力できるか）だけで判断する。

## 手動での切り替え

自動のon/offを待たずに、その場で切り替えたいときのコマンド。

```
/tab-tint:off   # 今すぐ元に戻す
/tab-tint:on    # 今すぐ試しに点灯する（見た目の確認用）
```

これはhookとは仕組みが違う点に注意。hook（`Notification`/`Stop`等）はOSに直接登録された決定的な処理で、AIを介さず一瞬・無料で動く。一方このコマンドはスキルなので、**Claude(AI)がSKILL.mdの指示を読んでBashツールを呼ぶ**という1ターンのやり取りが発生する。数秒かかり、トークンも消費する。毎回の待ち状態でこれを使うのは実用的ではなく、緊急時の手動オーバーライド用。

Claude Codeの仕組み上、「ユーザーが能動的に呼び出せて、かつAIを介さず決定的に実行される」コマンドは作れない（skills/commandsは必ずAIが解釈する。hooksはライフサイクルイベント発火時のみでユーザーが能動的に呼べない。keybindingsは固定アクションの再割り当てのみで任意のコマンド実行はできない）。

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

### なぜこの色か

色がつくのは「動いている間」だけで、読んでいる間・待っている間はいつもの色に戻るとはいえ、この色は**応答のたびに毎回目に入る**。なので警告色のような主張の強さではなく、頻繁に見ても気にならない色であることを優先して選んだ。

検討した候補と根拠:

- **ニュートラルグレー（採用・`#2a2a2e`）**: 画面上でテキストを読む快適さを直接比較した研究で、白・黒背景よりグレー背景の方が快適だと報告されている（[Visual comfort models based on coloured text and neutral background combinations](https://www.sciencedirect.com/science/article/abs/pii/S0042698924001688)）。特定の色相を持たないため、利用者ごとに異なるターミナル配色とも衝突しにくく、配布物としても無難
- **暖色チャコール（`#2e2b28`、環境変数で選択可）**: 色温度を下げる（黄色寄りにする）ほど眼精疲労が少ないというf.lux由来の知見に基づく。ただしこれは主に夜間・就寝前のブルーライト低減の文脈の研究で、日中の作業中の「読む快適さ」を直接測ったものではない
- **寒色系（Solarizedのようなダークティール・ブルーグレー、不採用）**: Solarizedの設計思想（明度差を抑えつつ色相コントラストは保持、寒色は深い集中を助ける）を参考にしたが、「色相そのものは快適さへの影響が小さく、文字と背景のコントラスト関係の方が重要」という、より読書快適性に直接踏み込んだ研究結果と比べると根拠が弱いと判断した
- 純色に近い暖色（赤系）は避けた。警告色として認識されやすく、実際に試したところ「やりすぎ」という評価だった

## 対応環境

OSC 11/111はターミナル固有の拡張ではなく標準的なエスケープシーケンスなので、対応するターミナルなら基本的にどれでも動く。

- **動作確認済み**: VS Code統合ターミナル（macOS）
- **対応しているはず（未検証）**: iTerm2、kitty、GNOME Terminal等のVTEベース端末（Linux/macOS）
- **Windows（Git Bash + Windows Terminal）: 動作確認済み**。Windows Terminalで実際に背景色が変わることを確認した
- **Windows（Android Studio / IntelliJ内蔵ターミナル）: 変わらない。** JediTermがOSC 11を実装していないため（[IJPL-218303](https://youtrack.jetbrains.com/projects/IJPL/issues/IJPL-218303/Support-OSC-11-escape-sequence-for-dynamic-terminal-background-colors)）。プラグイン側では手の打ちようが無い

macOSの`ttysNNN`・Linuxの`pts/N`どちらの命名も扱うが、CIではLinux/macOS/Windows上でスクリプトの終了コード・状態ファイルの扱い・JSON妥当性のみ検証しており、実機での色変化そのものはテストできていない。

### Windows側の書き込み先

Windowsにはhookから辿れるptyが無い。`/dev/tty`は`ENXIO`で開けず、Git Bash同梱の`ps`は`-o`自体を実装していない（`ps: unknown option -- o`）ので、プロセスツリーを遡る手も使えない。**この2つが理由で、pty探索のコードはWindowsでは必ず失敗する。**

代わりにコンソールデバイス`CON`へ書く。ここにも罠が2つある。

- bashから`> CON`すると、`CON`という名前の**実ファイルがcwdに作られるだけ**で端末には届かない
- `cmd`は`CONOUT$`をリダイレクト先として受け付けない（`ERROR_INVALID_NAME`）

通るのは`cmd`の`copy /b <file> CON`。`CONOUT$`を開いて`WriteConsoleW`する経路も同様に効くが、`cmd`経由なら追加の実行ファイルが要らないのでこちらを採った。

Windowsでは1回の書き込みに`cmd`の起動が要る（環境によっては数百ms）。`PreToolUse`は毎ツール呼び出しで発火するため、`CLAUDE_CODE_SESSION_ID`ごとに現在の状態を持ち、**状態が実際に変わるときだけ**書きに行く。書き込みが一度も届かなかった端末では、そのセッション中は再試行しない（届かない環境で毎ツール数百msを払い続けないため。`SessionEnd`で状態を消すので次のセッションでは再挑戦する）。POSIX側は書き込みが実質無償なので、この状態管理は持たない。

`hooks.json`が`bash "..."`を前置しているのは、hookが指す`.sh`をbash経由で実行しないことがある既知の問題（[#21847](https://github.com/anthropics/claude-code/issues/21847)）への対策。

なお**この検証で一番危なかったのは計測方法**だった。画面全体をキャプチャして色を測ると、対象のウィンドウが前面から外れた瞬間に別のウィンドウを測ってしまい、動いている経路まで「効かない」と誤判定する。ウィンドウ単位で`PrintWindow`（`PW_RENDERFULLCONTENT`）を使えばz順に依存せず測れる。

## 動作確認

```bash
bash tests/run.sh
```

ptyが見つからない環境（CI等）でも`on`/`off`が静かに正常終了すること、不正な引数を渡したときにexit 1で拒否すること、プラグインの各JSONファイルが妥当な形式であることを検証する。
