# architecture-diagram

判断に使えるクラウド構成図を draw.io で描くための Agent Skill。
誰が何を判断する図かを先に決め、実在する境界と公式アイコンで描き、AI 生成にありがちな装飾
(パステル背景、角丸カードの反復、色帯付き注記、造語ラベル、区別のない矢印、公式アイコンの着色)を排する。

ガイド・チェックリスト・テンプレートは AWS と Azure に対応。どちらも draw.io 内蔵のアイコン
(`mxgraph.aws4`、`azure2`)で描けるため、アイコンセットの別途ダウンロードは不要。

## 使い方

Claude Code では、marketplace から導入する。次の2行は Claude Code を起動して実行する。

```
/plugin marketplace add mamezou/mamezou-claude-plugins
/plugin install architecture-diagram@mamezou-claude-plugins
```

「構成図」「draw.io」「図をレビュー」を含む依頼で読み込まれる。手動で呼ぶときの名前は
`/architecture-diagram:architecture-diagram`。

SKILL.md 形式に対応する他のエージェントで使う場合は、リポジトリを clone し
`plugins/architecture-diagram/` を skills ディレクトリへ置く。

```sh
git clone https://github.com/mamezou/mamezou-claude-plugins
cp -r mamezou-claude-plugins/plugins/architecture-diagram ~/.claude/skills/architecture-diagram
```

## 中身

| パス | 内容 |
|---|---|
| `SKILL.md` | 手順、原則、AI っぽい図の癖と直し方、AI に描かせる指示の型、確認項目 |
| `references/principles.md` | 図全般の原則、デザイン、フォント、SVG 埋め込み、公開前チェック |
| `references/aws-guide.md` | AWS 公式の色、グループ、アイコン、レイアウト |
| `references/aws-checklist.md` | AWS 図の確認チェックリスト |
| `references/azure-guide.md` | Azure の境界、色、内蔵アイコン、レイアウト |
| `references/azure-checklist.md` | Azure 図の確認チェックリスト |
| `references/drawio.md` | フォント、PNG 書き出し |
| `scripts/export-png.sh` | draw.io → PNG。フォント指定の漏れと出力寸法を検証する |
| `assets/template-aws.drawio` | AWS 図のテンプレート。style 文字列を写す元 |
| `assets/template-azure.drawio` | Azure 図のテンプレート。style 文字列を写す元 |

## PNG 書き出しに必要なもの

`drawio`(Draw.io Desktop)、`ffmpeg`、`ffprobe`、`fontconfig`、図で指定したフォント
(既定 `IPAPGothic`。環境変数 `DIAGRAM_FONT` で変更)。画面のない環境では `xvfb-run`。

Claude Code から使うときは Skill が `${CLAUDE_SKILL_DIR}` で場所を解決します。手で実行するときは
clone したリポジトリのパスで実行します。

```sh
bash plugins/architecture-diagram/scripts/export-png.sh <図の .drawio>
```

## ライセンス

MIT License。`LICENSE` を参照。
