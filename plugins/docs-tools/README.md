# docs-tools

日本語で文書を作る作業を分担するためのエージェント 2 本と Skill 4 本。
調査とレビューを読み取り専用のサブエージェントへ渡し、本体は判断と統合に専念する。送付文面は
型どおりに作り、送る前に grep、`docs-tools:doc-review` による主語と述語の確認、通し読みの
3つを組み合わせて検査する。

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
| `agents/doc-review.md` | ドキュメント・差分のレビュー。指摘を「対象箇所 / 問題 / 根拠 / 修正案」で返す読み取り専用エージェント |
| `agents/repo-survey.md` | リポジトリ内の調査・横断検索・資料要約。根拠をパスと行番号で返す読み取り専用エージェント |
| `skills/send-draft/SKILL.md` | 先方向け・内部向けの送付文面ドラフトの作り方。設計 5 点の確認、置き場と命名、長さの目安 |
| `skills/send-draft/templates/*.txt` | 依頼・相談・返信・共有案内・報告・内部連絡のひな形 6 本 |
| `skills/draft-precheck/SKILL.md` | 送付前チェック。同梱スクリプトの grep(内部パス、組版記号、外部 AI 言及、指示語、括弧注記、1 文 60 字、バイト数)、`docs-tools:doc-review` による文章確認、通し読み |
| `skills/draft-precheck/scripts/precheck.sh` | 上記 grep の本体。`precheck.sh <ファイル>` で単体でも実行できる |
| `skills/work-log/SKILL.md` | 当日の作業ログ `work-log-YYYYMMDD.md` の作成・追記。書式と定型の記録 |
| `skills/codex-review/SKILL.md` | 成果物のクロスレビューを Codex CLI へ依頼する手順。ハングを避ける実行形 |

`skills/codex-review` は Codex CLI (`codex`) を別途インストールした環境で使う。対象ファイルの内容を
OpenAI のサービスへ送るため、利用者が明示して呼んだときだけ使い、機密を含む成果物には使わない。
ほかの Skill とエージェントは追加のコマンドを必要としない。

harness-ja プラグインは任意の併用先。併用すると、送付文面の禁止語と内部表現は hook が編集時にも
検査し、案件固有の禁止語は `.claude/harness.json` の `draftPrecheck.bannedTerms` に置ける。
単体でも全 Skill とエージェントは動く。

## ライセンス

MIT License。`LICENSE` を参照。
