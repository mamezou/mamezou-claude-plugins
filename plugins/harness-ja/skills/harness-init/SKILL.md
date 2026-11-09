---
name: harness-init
description: harness-ja を利用側プロジェクトへ初期設定する。.claude/harness.json の作成、rules テンプレートの複製、.gitignore の追記を行う。「harness-ja を初期化」「/harness-ja:harness-init」で呼び出す。
---

# harness-ja の初期設定

利用側プロジェクトに、hook が読む設定ファイルと、常に読み込む rules を配置する。
プラグインは rules を自動ロードできないため、テンプレートを複製して使う。
`.claude/harness.json` が無い間、hook は何もしない。初期設定で最初に作るのはこのファイル。

## 手順

1. 現在地がプロジェクトルート(git のトップレベル)であることを `git rev-parse --show-toplevel` で確認する。
2. 設定ファイルを置く。既にあれば上書きしない。

```bash
mkdir -p .claude/rules
[ -f .claude/harness.json ] || cp "${CLAUDE_PLUGIN_ROOT}/examples/harness.json" .claude/harness.json
```

3. rules テンプレートを複製する。`~/.claude/rules/`(Claude Code がすべての案件で読み込む、
   ユーザー単位の規則の置き場)に同じ名前のファイルがあるテンプレートは写さない。案件にも写すと
   同じ名前の規則が二重に読み込まれ、食い違ったときにどちらに従うかが決まらないため。
   案件の `.claude/rules/` にすでにあるファイルは上書きしない。

```bash
for f in "${CLAUDE_PLUGIN_ROOT}"/rules-templates/*.md; do
  n=$(basename "$f")
  if [ -e "$HOME/.claude/rules/$n" ]; then
    echo "写さない: $n (~/.claude/rules/$n がある)"
    [ -e ".claude/rules/$n" ] && echo "二重: $n (.claude/rules/$n もある)"
    continue
  fi
  if [ -e ".claude/rules/$n" ]; then
    echo "上書きしない: $n (.claude/rules/$n がある)"
    continue
  fi
  cp -n "${CLAUDE_PLUGIN_ROOT}/rules-templates/$n" .claude/rules/
done
```

   出力の行は次のとおり扱う。
   - `写さない:` の行: 名前と理由(`~/.claude/rules/` に同じ名前のファイルがあり、案件に写すと
     同じ名前の規則が二重に読み込まれる)を手順8の報告に書く。テンプレートとの差分は示さない
   - `二重:` の行: 案件の `.claude/rules/` と `~/.claude/rules/` の両方に同じ名前のファイルがあり、
     二重に読み込まれていることを手順8の報告に書く。テンプレートとの差分は示さない
   - `上書きしない:` の行: テンプレートとの差分を提示して、反映するかの判断を仰ぐ

   複製は初回だけで、プラグインを更新しても既存の `.claude/rules/` は変わらない。0.4.7 以前に
   複製した `writing-style.md` は、先頭に `paths:` があり、メールやチャットの下書きでは読み込まれず、
   「実例の確認」の節もない。`diff "${CLAUDE_PLUGIN_ROOT}/rules-templates/writing-style.md" .claude/rules/writing-style.md`
   で差分を示し、`paths:` の削除と「実例の確認」の節の追加を、利用者の判断で反映してもらう。
   `orchestration.md` は 0.4.16 で足した。`cp -n` は無いファイルだけを写すため、0.4.15 以前に
   初期設定した案件で再実行すると、`orchestration.md` が新しく写される。すでに
   `.claude/rules/orchestration.md` がある案件では上書きされないため、
   `diff "${CLAUDE_PLUGIN_ROOT}/rules-templates/orchestration.md" .claude/rules/orchestration.md`
   で差分を示し、反映するかを利用者に判断してもらう。

4. `.gitignore` に次の1行を追記する(既にあれば追記しない)。

```
.claude/harness-detections.log
```

5. `.claude/harness.json` を開き、利用者に次の項目を案件に合わせて書き換えてもらう。項目ごとに用途を1行で説明する。
   - `principal`: 通知文で使う利用者の呼称
   - `cloudChange.projects[]`: クラウド変更コマンドの停止の対象。`clis`、`cwdMatch`、`runbookPattern`、`runbookHint`、`guideRef`
   - `responseQuality.patterns`: 応答の文体検査で実行するパターン番号(既定 `[3, 4, 8, 19]`)
   - `draftPrecheck.targets[]`: 送付文面の置き場(bash の case パターン)。`bannedTerms[]` に案件の禁止語
   - `draftPrecheck.toolRules[]`: メールやチャットの下書きを渡す MCP のツールの本文を、送付文面の事前検査に通す対応表(既定は空)
   - `requireReading.rules[]`: 編集前に必読とする資料の対応表
   - `requireReading.toolRules[]`: 外部へ書き込む MCP のツールの前に呼んでおく、読み取りのツールの対応表(既定は空)
   - `toolResultCheck.rules[]`: MCP のツールの結果にあるはずの成立の印の対応表(既定は空)
   - 使わない機能は `"enabled": false` で止める
6. Output Style を使う場合は `/config` から「Concise JA」を選ぶよう案内する。
7. 週次のレビューは `/harness-ja:harness-review` で行うことを案内する。
8. 設定内容を要約して報告する。書き換えた・作成したファイルのパスを列挙する。手順3で `写さない:`
   と `二重:` の行が出たテンプレートがあれば、その名前と理由も書く。
9. サンプル値(`project-a` 等)を残していないか、利用者に `.claude/harness.json` を開いて確認してもらう。

## 完了条件

- `.claude/harness.json` が存在し `jq . .claude/harness.json` が通る
- テンプレート3本のそれぞれと同じ名前のファイルが、`.claude/rules/` か `~/.claude/rules/` にある。
  両方にあるものは、手順8の報告に書いた
- `.gitignore` に1行がある
- `examples/harness.json` のサンプル値(`project-a` 等)をプロジェクト固有の値に置き換えたか、
  使わない機能を `enabled: false` にした
