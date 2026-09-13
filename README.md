# mamezou-plugins

mamezou の Claude Code プラグイン集です。1つの marketplace として登録し、要るものだけ入れます。

| プラグイン | 種類 | 働き |
|---|---|---|
| [harness-ja](plugins/harness-ja/) | hook | クラウド変更コマンド(az / aws / cdk)と `.claude/` 配下の書き換えを、手順書と承認の文字列なしには実行させない。送付文面の内部表現も止める。応答の文体検査は任意 |
| [architecture-diagram](plugins/architecture-diagram/) | Skill | クラウド構成図を draw.io で描くときの手順・原則・チェックリスト・テンプレート(AWS / Azure) |

hook は操作と応答を検査して止める道具、Skill は作業のときに読み込まれる知識です。

## インストール

```
/plugin marketplace add mamezou/mamezou-plugins
/plugin install harness-ja@mamezou-plugins
/plugin install architecture-diagram@mamezou-plugins
```

harness-ja は導入後に利用側プロジェクトで `/harness-ja:harness-init` を実行し、`.claude/harness.json` に
案件の値(手順書の場所、必読資料、送付文面の置き場)を書きます。設定ファイルがなければ hook は
何もしません。詳細は各プラグインの README を参照してください。

## 動作環境

- Linux(bash、GNU coreutils、`jq`)。macOS は未検証
- architecture-diagram の PNG 書き出しには Draw.io Desktop が必要(プラグインの README 参照)

## ライセンス

MIT
