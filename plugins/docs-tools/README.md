# docs-tools

日本語で文書を作る作業を分担するためのエージェント 2 本と Skill 7 本。
調査とレビューを読み取り専用のサブエージェントへ渡し、本体は判断と統合に専念する。送付文面は
型どおりに作り、送る前に grep、`docs-tools:doc-review` による主語と述語の確認、
`docs-tools:doc-review` に読者として読ませる通し読みの3つを組み合わせて検査する。

前提にしている運用は、先方向けの連絡と内部向けの連絡を分けて書き、作業の記録を日付ごとの
作業ログに残す進め方。置き場と宛先の書式は利用側のリポジトリで決める。

## 使い方

Claude Code では、marketplace から導入する。Claude Code を起動し、次の2行を実行する。

```
/plugin marketplace add mamezou/mamezou-claude-plugins
/plugin install docs-tools@mamezou-claude-plugins
```

Skill は `/docs-tools:send-draft` のように名前空間つきで呼ぶ。エージェントは
`docs-tools:doc-review` / `docs-tools:repo-survey` の名前で呼ぶ。

## 収録物

| パス | 内容 |
|---|---|
| `agents/doc-review.md` | ドキュメント・差分のレビュー。指摘を「対象箇所 / 問題 / 根拠 / 修正案」で返す読み取り専用エージェント。読者としての通し読みを依頼すると、読んでつかえた箇所を返す。元の資料との照らし合わせを依頼すると、元の資料と合わない記述と、裏づけのない記述を返す。依頼との照合を依頼すると、依頼者の指示にない追加と、指示にある内容の欠落と、断定の強さの違いを返す |
| `agents/repo-survey.md` | リポジトリ内の調査・横断検索・資料要約。根拠をパスと行番号で返す読み取り専用エージェント |
| `skills/send-draft/SKILL.md` | 先方向け・内部向けの送付文面ドラフトの作り方 (Teams・Slack・メール)。実例の確認、依頼の仕分け、事実や判断を述べる文面で本文の前に依頼者へ見せる設計メモ、設計 5 点の確認、メールの下書きの手順、置き場と命名、長さの目安 |
| `skills/send-draft/templates/*.txt` | 依頼・相談・返信・共有案内・報告・内部連絡・メール (新規・返信) のひな形 8 本 |
| `skills/send-draft/templates/brief.md` | 送付文面の設計メモの型。6 つの欄 (相手の問い・依頼の原文と出典、相手がすでに知っていること、1 文目に書く答え、使う事実と出典と確かめた人と方法、未確認、依頼者が決めたこと) の書き方の説明と記入例。設計メモは送らない |
| `skills/doc-draft/SKILL.md` | 設計書・手順書・共有ページなど、チャット文面より長い資料を新しく書くとき、全面的に書き直すときの手順。元の資料の調査と載せる中身の一覧の作成、中身の判断を依頼者へ 1 回で聞くこと、指示書を使った別の書き手への依頼、読者としての通し読みと元の資料との照らし合わせ、依頼者への報告 |
| `skills/doc-draft/templates/brief.md` | 書き手へ渡す指示書の型。8 項目 (何を書くか、読者、依頼者が決めたこと、載せる中身、載せない内容、文の書き方、体裁、出力) の書き方の説明と記入例 |
| `skills/draft-precheck/SKILL.md` | 送付前チェック。同梱スクリプトの grep(内部パス、組版記号、外部 AI 言及、指示語、括弧注記、同じ括弧の繰り返し、1 文 60 字、読点が 2 つ以上の文、予告の文、同じ形の文の連続、物や事柄を主語にしがちな文末、バイト数)、`docs-tools:doc-review` による主語と述語の確認と読者としての通し読み、依頼者の指示との照合 (足した内容・消した内容・断定の強さの変更)、元の資料との照らし合わせ (事実を述べる送付文面では設計メモの「使う事実」の出典を元の資料にする)、コードブロックの各行の出どころ、長文資料の構造 (節・表のセル・背景・図・手順の要素)、直す手順と自然な文の見本 |
| `skills/draft-precheck/scripts/precheck.sh` | 上記 grep の本体。`precheck.sh <ファイル>` で単体でも実行できる。1 文 60 字・読点が 2 つ以上の文・予告の文・同じ形の文の連続・物や事柄を主語にしがちな文末の検知は、行頭が `\|` の表の行とコードブロックを数えない。同じ括弧の繰り返しは、表の行も数える |
| `skills/draft-precheck/scripts/code-origin.sh` | 文面のコードブロックの各行が、会話の記録のどこ (依頼者の入力・エラーでないツールの結果・成功したコマンド・Claude の応答) に出ていたかと、どこにも出ていない行を表示する。`code-origin.sh <下書き> [<会話の記録>]` で単体でも実行できる。止めない (終了コードは常に 0) |
| `skills/session-recall/SKILL.md` | 前のセッションの会話の記録を語で探す手順と、結果の扱い (元の資料を探す手がかりで、根拠にしない。見つからないことを「行わなかった」根拠にしない) |
| `skills/session-recall/scripts/session-recall.sh` | 今の案件のディレクトリの会話の記録 (`~/.claude/projects/` の下の JSONL とサブエージェントの記録) を読み、依頼者の入力・Claude の応答・ツールの呼び出し・ツールの結果から語を含む箇所を新しい順に出す。各行の `cwd` が案件のディレクトリの下にある行だけを使い、秘匿値らしい値は伏せ字にする |
| `lib/transcript.py` | `session-recall.sh` と `code-origin.sh` が使う、会話の記録を読む共通の処理 |
| `tests/run.sh` | 同梱スクリプトの検査。`tests/fixtures/` の文書を `precheck.sh` に通し、同じ括弧の繰り返しと読点の検知の出力を期待値と比べる。`tests/fixtures/transcripts/` の会話の記録で、`session-recall.sh` (ほかの案件の記録を読まないこと、配列形式のツールの結果、別ファイルに保存された結果、秘匿値の伏せ字) と `code-origin.sh` (出どころの区分、どこにも出ていない行) の出力を期待値と比べる。リポジトリの直下から `bash plugins/docs-tools/tests/run.sh` で実行する |
| `skills/work-log/SKILL.md` | 当日の作業ログ `work-log-YYYYMMDD.md` の作成・追記。書式と定型の記録 (判断や文面の根拠になった実行の、実行した人・日時・場所・対象と範囲・原文・結果の要点・元の結果を含む) |
| `skills/codex-review/SKILL.md` | 成果物のクロスレビューを Codex CLI へ依頼する手順。ハングを避ける実行形 |
| `skills/plan-visual-page/SKILL.md` | 計画書・手順書・方針の説明を、読み手がファイルを開かずに判断できる図のページ (claude.ai の Artifact) にする手順。共有用の PDF と投稿の本文をページに置く欄も作る |
| `skills/plan-visual-page/reference/*` | 例のページ (`example.html`)、保存とコピーの欄の部品 (`share-box.html`)、PDF の書き出し (`export_pdf.py`) |

`skills/codex-review` は Codex CLI (`codex`) を別途インストールした環境で使う。対象ファイルの内容を
OpenAI のサービスへ送るため、利用者が明示して呼んだときだけ使い、機密を含む成果物には使わない。
`skills/plan-visual-page` は、claude.ai の Artifact ツールが使える Claude Code で使う。共有用の PDF を書き出すときは、
Python の playwright と Google Chrome が要る。
`skills/session-recall` と、`skills/draft-precheck` のコードの出どころの表示は、python3 (標準ライブラリだけ) を使う。
ほかの Skill とエージェントは追加のコマンドを必要としない。

harness-ja プラグインは任意の併用先。併用すると、送付文面の禁止語と内部表現は hook が編集時にも
検査し、案件固有の禁止語は `.claude/harness.json` の `draftPrecheck.bannedTerms` に置ける。
単体でも全 Skill とエージェントは動く。

## ライセンス

MIT License。`LICENSE` を参照。
