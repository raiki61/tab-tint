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

この2つはhookと違って**状態の短絡を通らない**。Windows側には「状態が変わるときだけ書く」短絡があるが（後述）、手動で呼んだときにそれに従うと「もうonのはずだ」と判断して何も書かず、それでも成功したように見えてしまう。見た目を確認するための道具が黙ってno-opになるのは最悪なので、手動のときは必ず書きに行き、書いた結果で状態も上書きする（上書きしないと、手動で消灯した画面をhookが「まだonのはずだ」と短絡して二度と点けない）。

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
- **Windows（Windows Terminal）: 動く**。実際に背景色が変わることを確認した
- **Windows（Android Studio / IntelliJ内蔵ターミナル）: 変わらない。** JediTermがOSC 11の「設定」を実装していないため（後述）。プラグイン側では手が出せない
- **Windows（VS Code統合ターミナル）: 効くが、保持されない。** 端末は適用するが、タブ切り替えとテーマ再適用で既定色へ戻される（[vscode#312815](https://github.com/microsoft/vscode/issues/312815)）。ターンの頭で毎回書き直して復帰させている（後述）

macOSの`ttysNNN`・Linuxの`pts/N`どちらの命名も扱うが、CIではLinux/macOS/Windows上でスクリプトの終了コード・状態ファイルの扱い・JSON妥当性のみ検証しており、実機での色変化そのものはテストできていない。

### Windows側の書き込み先

Windowsにはhookから辿れるptyが無い。`/dev/tty`は`ENXIO`で開けず、Git Bash同梱の`ps`は`-o`自体を実装していない（`ps: unknown option -- o`）ので、プロセスツリーを遡る手も使えない。**この2つが理由で、pty探索のコードはWindowsでは必ず失敗する。**

代わりにコンソールデバイス`CON`へ書く。ここにも罠が2つある。

- bashから`> CON`すると、`CON`という名前の**実ファイルがcwdに作られるだけ**で端末には届かない
- `cmd`は`CONOUT$`をリダイレクト先として受け付けない（`ERROR_INVALID_NAME`）

通るのは`cmd`の`copy /b <file> CON`。`CONOUT$`を開いて`WriteConsoleW`する経路も同様に効くが、`cmd`経由なら追加の実行ファイルが要らないのでこちらを採った。

Windowsでは1回の書き込みに`cmd`の起動が要る（環境によっては数百ms）。`PreToolUse`は毎ツール呼び出しで発火するため、`CLAUDE_CODE_SESSION_ID`ごとに現在の状態を持ち、**状態が実際に変わるときだけ**書きに行く。書き込みが一度も届かなかった端末では、そのセッション中は再試行しない（届かない環境で毎ツール数百msを払い続けないため。`SessionEnd`で状態を消すので次のセッションでは再挑戦する）。POSIX側は書き込みが実質無償なので、この状態管理は持たない。

例外が1つある。**`UserPromptSubmit`（ターンの頭）だけは、状態が同じでも書き直す。** 端末側が一度効いた色を取り上げることがあるためで、VS Codeはタブ切り替えとテーマ再適用のたびに既定色へ戻す（[vscode#312815](https://github.com/microsoft/vscode/issues/312815)）。短絡に任せると次にon/offが切り替わるまで色が戻らない。コストはターンあたり`cmd`起動1回で、毎ツール発火する`PreToolUse`の短絡はそのまま残している。届かないと分かっている端末（`unsupported`）ではこの書き直しも払わない。

状態の置き場は`%LOCALAPPDATA%\Temp\tab-tint`に固定してある（`TAB_TINT_STATE_DIR`で上書き可、テスト用）。プラグイン用の`CLAUDE_PLUGIN_DATA`を使わないのは、**hookには渡るが、手動コマンドには渡らない**ため。スキルはBashツールから走るのでこの変数が無く、そこを見ると置き場が2つに割れて、状態を共有しているつもりで共有できていない状態になる（手動で消灯したのにhookは「まだon」と思い込む）。`CLAUDE_CODE_SESSION_ID`はどちらの文脈にも渡るので、ファイル名の側は割れない。

`hooks.json`が`bash "..."`を前置しているのは、hookが指す`.sh`をbash経由で実行しないことがある既知の問題（[#21847](https://github.com/anthropics/claude-code/issues/21847)）への対策。

### ConPTYは何も飲まない（測定で確定）

**書き込みが端末に届かないのではない。届いた先の端末で結果が分かれる。**

以前ここには「WindowsローカルのConPTYがOSC 11を消費する」と書いてあったが、**それは誤りだった**。自分でConPTYを作り、その中で`cmd /c copy /b <file> CON`（このプラグインと同じ書き方）を走らせて、ConPTYの出力パイプに何が出てくるかを直接読むと、3つの実装すべてがそのまま転送している。

| ConPTY実装 | OSC 11 | DECSCNM（`CSI ?5h`） |
| --- | --- | --- |
| OS（`kernel32!CreatePseudoConsole`） | 転送する | 転送する |
| Android Studio / IntelliJ 同梱（`lib/pty4j/win/x86-64/conpty.dll`） | 転送する | 転送する |
| VS Code 同梱（node-pty、`1.25.2603.03002`） | 転送する | 転送する |

```
<ESC>[1t<ESC>[c<ESC>[?1004h<ESC>[?9001h<ESC>]11;#004a00<BEL>
                                       ^^^^^^^^^^^^^^^^^^^^ 出力パイプにそのまま出る
```

この測り方には端末もスクリーンショットも人の目も要らない。以前の否定的な結論は、`GetConsoleScreenBufferInfoEx`のカラーテーブル（**16色しか無い**）を見て「内部状態すら変わっていない」と判断したことに由来する。OSC 11が書き換えるのは既定背景の別名である**パレット262番**なので、そこには原理的に映らない（[microsoft/terminal discussion #14142](https://github.com/microsoft/terminal/discussions/14142)）。

### 端末ごとの事情

**Android Studio / IntelliJ: JediTermがOSC 11の「設定」を実装していない。** [JediEmulator.javaの`doProcessOsc()`](https://github.com/JetBrains/jediterm/blob/master/core/src/com/jediterm/terminal/emulator/JediEmulator.java)は次のとおりで、OSC 10/11は**クエリ応答専用**。

```java
case 10:
case 11:
  return processColorQuery(args);   // '?' に答えるだけ。設定は無い
```

扱われているのはOSC 0/1/2（タイトル）、7（スタブ）、8（ハイパーリンク）、10/11（クエリのみ）、104（no-op）、1341（独自）で、**OSC 4と12は未処理**。要望は出ているが未実装（[IJPL-218303](https://youtrack.jetbrains.com/issue/IJPL-218303) はOpenのまま）。書式や終端子の問題ではない——BEL/ST、`#rrggbb`/`rgb:RR/GG/BB`/16bitの5通りを実機で試して全滅している。埋め込みターミナルのVTエミュレータはプラットフォーム側なので、**プラグインで差し替えることもできない**（マーケットプレイスの「terminal」系はどれも外部ターミナルのランチャ）。

**VS Code: 効くが、保持されない。** 端末（xterm.js）はOSC 11の設定を[フルサポート](https://xtermjs.org/docs/api/vtfeatures/)していて、VS Code側も[#139645](https://github.com/microsoft/vscode/issues/139645)で2021-12-22に対応済み。ただし**タブ切り替え（エディタ領域のターミナル）とテーマ再適用のたびに既定色へ戻される**（[#312815](https://github.com/microsoft/vscode/issues/312815)、open）。このプラグインは`UserPromptSubmit`で毎ターン書き直して復帰させている。

**効果が出るのは既定背景のセルだけ。** OSC 11が変えるのは「端末の*既定*背景色」なので、色が乗るのは既定背景のまま描かれているセルと、文字グリッドが割り切れない端の余りだけ。素のシェル（ほぼ全面が既定背景）なら全体が染まるが、自前の色でセルを塗るフルスクリーンTUIでは作用する面積が小さい（[opentui#950](https://github.com/anomalyco/opentui/issues/950)）。同じ理由で、JediTermが実装しているDECSCNM（画面反転）を送っても見た目はほとんど変わらない——反転するのも既定色のセルだから。

IntelliJ系には`Help | Edit Custom VM Options`に`-Dcom.pty4j.windows.disable.bundled.conpty=true`を足して同梱ConPTYをやめる手があるが、**転送は元々されている**ので状況は変わらない。原因はJediTerm側にある。

なお**この検証で一番危なかったのは計測方法**だった。この節の結論は3回ひっくり返っていて、原因は毎回「測れていないものを測ったつもりになった」ことにある。

- 画面全体をキャプチャして色を測ると、対象のウィンドウが前面から外れた瞬間に別のウィンドウを測ってしまう。動いている経路まで「効かない」と誤判定した。ウィンドウ単位の`PrintWindow`（`PW_RENDERFULLCONTENT`）ならz順に依存しない
- `GetConsoleScreenBufferInfoEx`のカラーテーブルは16色しか無い。OSC 11が書き換えるパレット262番はそこに映らないので、「内部状態も変わっていない」は証拠にならない
- 一番確実なのは**ConPTYを自分で作って出力パイプを読む**こと。端末もスクリーンショットも人の目も要らず、「転送されたか」だけを直接見られる。`ReadConsoleOutputCharacterW`の読み戻しと組み合わせれば、「書き込みが着地したか」と「端末に届いたか」を別々に判定できる

## 動作確認

```bash
bash tests/run.sh
```

ptyが見つからない環境（CI等）でも`on`/`off`が静かに正常終了すること、不正な引数を渡したときにexit 1で拒否すること、プラグインの各JSONファイルが妥当な形式であることを検証する。
