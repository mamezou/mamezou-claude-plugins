# harness-ja

クラウド変更コマンドの停止と、設定・規則ファイルの保護を中心に、応答の文体検査を任意で
加える Claude Code プラグインです。hook が実行前・応答終了時に検査し、条件を満たさない
操作と応答を止めます。日本語で応答するプロジェクト向けで、プロジェクト固有の設定は利用側の
`.claude/harness.json` に置きます。

主な機能は次の3つです。

1. az / aws / cdk の変更系コマンドの停止。手順書の Read と、利用者の承認の文字列の両方が必要
2. `.claude/` 配下(設定・hook・rules・skills)の書き換えの停止。利用者の承認の文字列が必要
3. 応答の文体検査。既定は4種類のみで、設定で増やせる

送付文面の検査、必読資料の先読みの強制、ツールの結果の検査、インライン PowerShell の検査(任意)も行います。
条件は「hook の一覧」を参照してください。

`.claude/harness.json` が無い間、hook は何もしません。まず `/harness-ja:harness-init` を
実行してください。

## 収録物

| 種別 | 内容 |
|---|---|
| hooks(7本) | クラウド変更コマンドの停止、設定・規則ファイルの保護、応答の文体検査、送付文面の事前検査、必読資料の先読みの強制、ツールの結果の検査、インライン PowerShell の禁止 |
| Output Style | `Concise JA`。簡潔な日本語応答と、返信文体の規則 |
| rules テンプレート(2本) | 着手と承認、文章の書き方 |
| Skills(2本) | `/harness-ja:harness-init`(初期設定)、`/harness-ja:harness-review`(検知ログのレビュー) |
| tests | hook 7本の合成入力テスト。`bash tests/run.sh` |

## 用語

| 語 | 意味 |
|---|---|
| 差し戻し | hook が終了コード2を返し、Claude に応答を作り直させること |
| Stop | 返信の終了時に走る検査 |
| PreToolUse | ツールの実行直前に走る検査。終了コード2でツールを実行させない |
| 承認の文字列 | 利用者が書くと操作が通る文字列(`[change-go: <案件>]`、`[harness-go]`)。それだけの行に書いたときだけ有効 |
| バイパスの文字列 | 利用者が書くと検査を飛ばす文字列(`[hook-bypass: <検査名>]`)。それだけの行に書いたときだけ有効 |
| `principal` | 通知文で使う利用者の呼称(既定「依頼者」)。権限を識別する設定ではない |
| `cwdMatch` | 案件を選ぶためのパスの一部。パス区切り単位で cwd かコマンド中のパスと照合する(`/work/project-a-old` は `project-a` に一致しない) |
| `runbookPattern` | 手順書のパスに当てる `grep -E` 形式の正規表現 |

承認の文字列とバイパスの文字列は、利用者が自分のメッセージに書く運用です。引用・質問の中に
書いた場合(「`[harness-go]` とは何ですか」)は無効です。

## 動作環境

- Linux(bash、GNU coreutils、`jq`)。macOS は未検証

## インストール

次の2行は Claude Code 内で実行します。

```
/plugin marketplace add mamezou/mamezou-claude-plugins
/plugin install harness-ja@mamezou-claude-plugins
```

利用側プロジェクトで初期設定を行います。

```
/harness-ja:harness-init
```

`.claude/harness.json` の作成、rules テンプレートの複製、`.gitignore` の追記を行います。
作成された `harness.json` をプロジェクト固有の設定に書き換えてください。Output Style は
`/config` で「Concise JA」を選んでください。

## hook の一覧

| hook | イベント | 止める条件 | バイパス |
|---|---|---|---|
| `cloud-change-check.sh` | PreToolUse(Bash) | az / aws / cdk の変更系コマンドで、手順書の Read と `[change-go: <案件>]` のいずれかが無い。変更系を検知したのに設定のどの案件にも一致しないときも止める | `[hook-bypass: cloud-change]` |
| `harness-change-check.sh` | PreToolUse(Bash / Write / Edit / MultiEdit) | `.claude/` 配下(hooks / rules / skills / settings 等)の書き換えで、`[harness-go]` が無い。例外として、プラグイン配下からの `cp`、`mkdir`、`.claude/harness.json` の新規作成は初期設定のため通す | なし(承認の文字列がバイパスを兼ねる) |
| `response-quality.sh` | Stop | 応答本文に文体違反(既定は4種類。下の表を参照) | `[hook-bypass: response-quality]` |
| `draft-precheck.sh` | PreToolUse(Write / Edit / MultiEdit / MCP のツール) | 送付文面に内部パス・ローカル拡張子・組版記号・外部 AI 言及・禁止語・長い識別子の繰り返し。MCP のツールは `draftPrecheck.toolRules[]` に書いたものだけ、`subject` と `body` などの文字列を検査する | `[hook-bypass: draft-precheck]` |
| `require-reading.sh` | PreToolUse(Write / Edit / MultiEdit / MCP のツール) | 必読資料を直近で Read せずに対象ファイルを編集。対応する読み取りのツールを呼ばずに、外部へ書き込むツールを呼び出し | `[hook-bypass: resource-reading]` |
| `tool-result-check.sh` | PostToolUse(MCP のツール) | 止めない。ツールの結果に成立の印が無いとき、作成・更新が成立していないことを Claude へ知らせる | なし |
| `no-inline-powershell.sh` | Stop | 5行以上の PowerShell をファイル化せずにコードブロックで提示(既定は無効)。`pasteRun` を有効にすると、貼り付けて実行する形に合わないスクリプトと、`-File` での実行を書いた文書・応答も止める | なし |

設定ファイルが見つからない場合、7本とも何もしません。設定ファイルはあるが JSON として
読めない場合、PreToolUse の4本は「設定ファイルが読めません: <パス>」を出してツールを止めます。
Stop の2本と PostToolUse の1本は同じ文を出しますが、応答とツールは止めません。

## 応答の文体検査

`responseQuality.patterns` に書いた番号のパターンだけを実行します。既定は
`[3, 4, 8, 19]` です。

| No. | 名前 | 既定 |
|---:|---|---|
| 1 | 選択肢の羅列 + 末尾の確認質問 | 無効 |
| 2 | 英語 UI 名の和訳なしの使用 | 無効 |
| 3 | ひな形・叩きを完了扱い | 有効 |
| 4 | 組版記号(§ ¶ ‡ †)の使用 | 有効 |
| 5 | 装飾語・抽象語での文末(文末にある語だけを見る) | 無効 |
| 6 | 言い換え対象語を2語以上 | 無効 |
| 7 | 指示語が3回以上 | 無効 |
| 8 | 空約束・態度の宣言 | 有効 |
| 9 | 質問への応答での無指示の作業宣言 | 無効 |
| 10 | 長い識別子のフル表記を3回以上 | 無効 |
| 11 | 整理用ラベル(通1 / 2通目)での報告 | 無効 |
| 12 | 指示待ちで締める | 無効 |
| 13 | 送付文面の1文が60字超 | 無効 |
| 14 | (欠番) | — |
| 15 | 見出し・表のセルが文で終わる | 無効 |
| 16 | 表のセルと本文の重複 | 無効 |
| 17 | 括弧の中の述語 | 無効 |
| 18 | 前置き・自己評価の定型句(文頭・行頭にある語だけを見る) | 無効 |
| 19 | 確認質問への根拠なしの否定断定 | 有効 |
| 20 | 確認点の番号の飛び・重なり(【確認点N】の番号が1から1ずつ増えていない) | 無効 |
| 21 | 確認点の数の宣言(「お聞きしたいことは1つ」「確認点は2件」等) | 無効 |
| 22 | 作業ディレクトリから開けない相対パス(バッククォートの中のパスが cwd から開けず、リポジトリの中に同じパスで終わるファイル・ディレクトリがある) | 無効 |

パターン20と21は、コードブロック(字下げしたものを含む)、行頭が「>」の引用行、
バッククォート・「」・『』・() の中を数えません。前の応答の確認点や規則の文を引用した箇所では
止めません。パターン20は行頭の【確認点N】だけを数え、文の途中の【確認点N】と、直後に助詞が
続く【確認点N】(「【確認点1】の答えで」等)は参照として数えません。

パターン22は、コードブロックと行頭が「>」の引用行の外で、バッククォートで囲んだ「/」を含むパスを
見ます。リポジトリに無いパス(ブランチ名など)は止めません。止めたときは、リポジトリの中で
見つけた絶対パスを示します。

差し戻し後の再生成(`stop_hook_active=true`)も検査します。同じ利用者入力への差し戻しが
3回に達したら、4回目の生成を `[regen-limit]` 付きで通します(無限ループ防止)。

検知の記録は `.claude/harness-detections.log` に1行1件で残り、
`/harness-ja:harness-review` の集計元になります。行の形式は
`<時刻>\t[session:<ID>] [input:<UUID>] <検知内容>` です。タグの無い旧形式の行は集計に
入りません。

## 設定ファイル `.claude/harness.json`

`examples/harness.json` が全キーの例です。使わない機能は `"enabled": false` で止めます。

| キー | 用途 |
|---|---|
| `principal` | 通知文で使う利用者の呼称(既定「依頼者」) |
| `responseQuality.patterns` | 実行するパターン番号の配列(既定 `[3, 4, 8, 19]`) |
| `responseQuality.uiTerms` / `fluffTerms` / `bannedLeads` | パターン2 / 5 / 18 の辞書への追加 |
| `responseQuality.logPath` | 検知ログの置き場(プロジェクトルートからの相対パス) |
| `responseQuality.regenLimitPerInput` | 同じ利用者入力への差し戻しの上限回数(既定3) |
| `cloudChange.projects[]` | クラウド変更コマンドの停止の対象。`clis`(az / aws / cdk)、`cwdMatch`、`runbookPattern`、`runbookHint`、`guideRef` |
| `harnessChange.token` / `excludePatterns[]` | 設定・規則ファイルの保護で使う承認の文字列(既定 `[harness-go]`)と除外パス(既定 `.claude/projects/`) |
| `draftPrecheck.targets[]` | 送付文面の置き場(bash の case パターン)。`excludePatterns[]`、`bannedTerms[]`、`honorific` |
| `draftPrecheck.toolRules[]` | 本文を検査する MCP のツール(`tool`、`jq` の `test()` の正規表現)と、検査する引数(`fields`、既定は `subject` と `body`)。`requiredFields` に挙げた引数がない呼び出しは止める。既定は空 |
| `draftPrecheck.checks` | 検査項目ごとの on / off。`bannedTerms` / `internalPaths` / `extensions` / `typography` / `externalAi` / `honorific` / `longIdentifiers`(既定すべて true) |
| `requireReading.rules[]` | 編集対象(`target`)と必読資料(`requiredReadPattern`)の対応表。`mode: "logs"` で作業ログの特例 |
| `requireReading.toolRules[]` | 外部へ書き込むツール(`tool`)と、先に呼んでおく読み取りのツール(`requiredTool`)の対応表。`sameInput` に、値が等しいことを求める引数の組を書く。既定は空 |
| `toolResultCheck.rules[]` | ツール(`tool`)と、結果にあるはずの成立の印(`successPattern`)の対応表。既定は空 |
| `noInlinePowershell.enabled` | 既定は `false`。使う場合だけ `true` にする |
| `noInlinePowershell.cwdMatch` | 指定すると、cwd がそのディレクトリ名を含むときだけインライン提示を検査する(案件を限る用途) |
| `noInlinePowershell.pasteRun` | 貼り付けて実行する形の検査。`enabled`(既定 `false`)、`scriptGlobs` と `docGlobs`(リポジトリ直下からの bash のパターン)、`hint`。cwdMatch によらず、依頼者の最後の入力より後に変えたファイルと、応答の本文を見る。スクリプトは、全体が `& { }` で包まれ、`param(`・`-ExecutionPolicy … -File`・ブロックの中の空行がないこと。文書と応答は `-ExecutionPolicy … -File` がないこと。差し戻し後の再生成ではファイルを見ない |

hook は設定ファイルを `HARNESS_CONFIG` 環境変数、`$CLAUDE_PROJECT_DIR/.claude/harness.json`、
hook 実行時の cwd から上へ辿った `.claude/harness.json` の順で探します。

### MCP のツールの規則

`requireReading.toolRules[]`、`toolResultCheck.rules[]`、`draftPrecheck.toolRules[]` は、MCP の
ツール(名前が `mcp__` で始まるツール)に効きます。ツール名と引数名は利用側の設定に書き、プラグインは特定のサービスの
名前を持ちません。`tool`、`requiredTool`、`successPattern` は正規表現です。

次は、チャットの下書きを作るツールに使う例です。ツール名、引数名、結果の項目名は架空の
ものです。接続している MCP サーバーのツールに合わせて書き換えてください。

```json
"requireReading": {
  "toolRules": [
    {
      "tool": "__create_draft$",
      "requiredTool": "__read_thread$",
      "sameInput": { "room_id": "room_id", "reply_to": "thread_id" },
      "hint": "送付先のスレッド"
    }
  ]
},
"toolResultCheck": {
  "rules": [
    {
      "tool": "__create_draft$",
      "successPattern": "\"created_id\":\\s*\"[0-9A-Za-z]+\"",
      "hint": "下書きの ID"
    }
  ]
}
```

- `toolRules` は、下書きを作る前に、同じスレッドを読んで結果を受け取っていることを求めます。
  `sameInput` の左が書き込むツールの引数名、右が読み取りのツールの引数名です。左の引数が
  呼び出しに無いとき(スレッドの指定が無い下書き)は、その規則を使いません
- 読み取りは、利用者の入力ごとに要ります。前の入力のときに読んだ内容は数えません
- `toolResultCheck` は、結果に下書きの ID が無いとき、作成が成立していないことを Claude へ
  知らせます。ツールは実行済みのため、止めることはしません
- `successPattern` の `\\s*` は、結果の JSON がコロンの後に空白を入れる場合に備えたものです
- `requiredTool` や `successPattern` の無い規則は使わず、次の規則を見ます

メールの下書きのように、本文をツールの引数で渡す呼び出しは、`draftPrecheck.toolRules[]` で
本文を検査します。ツール名と引数名は、接続している MCP サーバーの定義に合わせて書きます。

```json
"draftPrecheck": {
  "toolRules": [
    { "tool": "__create_draft$", "requiredFields": ["body"] },
    { "tool": "__update_draft$" }
  ]
}
```

- `tool` は、`requireReading.toolRules` と同じ、`jq` の `test()` の正規表現です
- `fields` は、`tool_input` の中で検査する引数名で、文字列を1件以上含む配列に限ります。既定は
  `["subject", "body"]` です。HTML の引数(`htmlBody` など)は、タグが検査に混ざるため、既定に
  入れていません
- `requiredFields` に挙げた引数が、`tool_input` にない、空白だけ、文字列でないときは、止めます。
  既定は空で、何も求めません。メールの下書きを作るツールには `["body"]` を書いてください。
  件名があっても、`body` がなく `htmlBody` だけで本文を渡す呼び出しは、`requiredFields` を
  書かないと検査されずに通ります。更新のツールのように、本文を省いて宛先だけを変えられる
  ツールや、下書きの ID だけで送るツールには、書きません
- `toolRules` の形の誤り(配列でない、要素がオブジェクトでない、`tool` がない、`fields` や
  `requiredFields` が文字列の配列でない)、`tool` の正規表現の誤り、`tool_input` が配列や文字列の
  呼び出しは、検査できないため、終了コード 2 で止めます。形の誤りは、MCP のツールの呼び出しの
  すべてを止めます
- `tool` に一致しない MCP のツールの呼び出しでは、何もしません
- 検査の項目は、ファイルの編集と同じです。`checks` で止める項目を選べます
- 本文の意味(依頼にない内容の追加、依頼にある内容の欠落)は、この hook では判定できません。
  `docs-tools` の `draft-precheck` と `doc-review` で照合します

## rules テンプレートについて

プラグインは `.claude/rules/` 相当の常に読み込まれる指示を配布できないため、
`rules-templates/` を `/harness-ja:harness-init` で利用側へ複製します。複製後は利用側で
自由に編集してください。`start-approval.md` は作者の作業様式です。破壊的操作・クラウド
変更・根拠確認の項目以外は削ってかまいません。

複製は初回だけです。プラグインを更新しても、複製済みの `.claude/rules/` は変わりません。
0.4.7 以前に複製した `writing-style.md` は、先頭に `paths:` があり、メールやチャットの下書きでは
読み込まれません。0.4.8 のテンプレートは `paths:` を付けず、「実例の確認」の節を持ちます。
0.4.11 の `start-approval.md` は、「応答を確定する前」の節を持ち、完了と丸投げの決まりに、
自分で続けられる作業を報告の前に済ませることと、検証用の環境で試す案を推奨することを足しています。
「応答を確定する前」には、事実の出典を挙げること、主語の範囲を確かめた範囲に合わせること、
取り消しに手間のかかる操作の前にできなくなることを書くことも入っています。
`/harness-ja:harness-init` を再実行すると、差分を示します。

文章の規則のうち、次の3つは grep や hook で検知できないため、`writing-style.md` の
手順で読み取り専用のサブエージェント(model: sonnet)へ読者としての通し読みを委任して
確かめます。主語と述語の対応も同じ依頼で見させます。

- 読者として頭から通して読み、つかえた箇所を段落を単位に直す
- 文は主語と述語だけを抜き出して読み、対応しない文を直す
- 段落は「読み手がこの段落を読んで次に何をするか」で組む

## 検知ログのレビュー `/harness-ja:harness-review`

`skills/harness-review/summarize.sh` が検知ログを集計し、Markdown で出します。

| 節 | 内容 |
|---|---|
| 期間と件数 | 直近28日(`--days` で変更)と前期間の件数、差し戻し上限で通過した件数 |
| 週別件数 | 月曜起点の週ごとの件数 |
| 種別ごとの件数 | 今期間・前期間・増減 |
| 種別ごとの検出例 | 各3件。誤検知か実違反かを読んで判断する材料 |
| 検出語の頻度 | 辞書から外す語、閾値を上げる語の候補 |
| 常に読み込まれる指示の行数 | CLAUDE.md と rules の合計。増え続けていないかの確認 |

`skills/harness-review/replay.sh` は過去の会話の記録に hook を流し直し、止めた点と hook ごとの件数を
出します。正誤のラベル(`--labels`)を渡すと、止めるべきでないのに止めた件数も出します。本物の
検知ログと設定には書き込みません。使い方は `skills/harness-review/SKILL.md` にあります。

Skill は集計を読み、`harness.json`・hook・規則の変更前後を【確認点】の型で提示します。hook と
辞書・閾値の案には、`replay.sh` で流した結果を添えます。承認された項目だけ反映します。
1回のレビューで変える項目は3件までとし、効果を次回の件数で確かめてから次を変えます。

## テスト

リポジトリを clone した開発者向けです(インストールした利用側プロジェクトには
`tests/` が入りません)。

```bash
bash tests/run.sh
```

hook 7本に合成の会話履歴 JSONL と入力 JSON を与え、差し戻し(終了コード2)と通過
(終了コード0)、承認の文字列、バイパスの文字列、設定なし、設定の壊れ、差し戻し回数の
上限、検知ログの UTF-8 を確認します。hook や辞書を変えたら実行してください。

## ライセンス

MIT
