# mamezou-claude-plugins

mamezou が公開している Claude Code のプラグイン集です。利用者はこのリポジトリを marketplace として Claude Code に登録し、必要なプラグインだけをインストールします。

| プラグイン | 種類 | 働き |
|---|---|---|
| [harness-ja](plugins/harness-ja/) | hook | クラウド変更コマンド(az / aws / cdk)は、手順書の Read と `[change-go: <案件>]` だけの行がなければ実行させない。`.claude/` 配下の書き換えは、`[harness-go]` だけの行がなければ実行させない。送付文面の内部パスやローカル拡張子も止める。応答の文体検査は任意 |
| [architecture-diagram](plugins/architecture-diagram/) | Skill | 構成図を draw.io で描くときの手順・原則・チェックリスト・テンプレート(AWS / Azure / オンプレミス) |
| [docs-tools](plugins/docs-tools/) | エージェント + Skill | 文書作業の分担。差分レビュー・リポジトリ調査の読み取り専用エージェント、送付文面の型と送付前チェック、作業ログ、Codex CLI へのクロスレビュー依頼 |

hook は操作と応答を検査して止める道具、Skill は作業のときに読み込まれる知識、エージェントは調査やレビューを引き受ける読み取り専用の分担先です。

## インストール

Claude Code を起動し、次のコマンドを実行します。install は必要なプラグインの分だけ実行します。

```
/plugin marketplace add mamezou/mamezou-claude-plugins
/plugin install harness-ja@mamezou-claude-plugins
/plugin install architecture-diagram@mamezou-claude-plugins
/plugin install docs-tools@mamezou-claude-plugins
```

harness-ja の導入後、利用者は利用側プロジェクトで `/harness-ja:harness-init` を実行します。
`/harness-ja:harness-init` はサンプル設定を複製するので、利用者はプロジェクト固有の設定
(手順書の場所、必読資料、送付文面の置き場)に書き換えて使います。設定ファイルがなければ hook は何もしません。
詳細は各プラグインの README を参照してください。

## 動作環境

- Linux(bash、GNU coreutils、`jq`)。macOS は未検証
- architecture-diagram の PNG 書き出しには Draw.io Desktop が必要(プラグインの README 参照)
- docs-tools の `/docs-tools:codex-review` には Codex CLI が必要。利用者が明示して呼んだときだけ使い、成果物を外部サービスへ送る点を承知のうえで使う(プラグインの README 参照)

## ライセンス

MIT
