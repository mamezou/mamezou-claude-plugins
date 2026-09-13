# draw.io の扱い

## 元データとPNG

- `.drawio` が正データ、PNGは派生物。同じ基底名で置き、元データを変えたらPNGを書き出し直す

## SVGアイコンの埋め込み

- URLエンコード方式を使う: `image=data:image/svg+xml,<URLエンコードしたSVG>`
- Base64方式(`data:image/svg+xml;base64,...`)はdraw.ioで表示されない
- Python: `urllib.parse.quote(svg_text)` でエンコードし、styleの `image=` に指定する
- AWSは `mxgraph.aws4.*` 図形、Azureは `image=img/lib/azure2/<カテゴリ>/<名前>.svg` の
  内蔵アイコンがあるので、通常は埋め込み不要

## フォント

- すべてのテキスト要素に同じ `fontFamily=<名前>` を指定する。1つの図でフォントを混在させない
- 未指定だと書き出し環境の代替フォントで描画され、字形・文字幅・改行位置が変わる(中国語フォントの字形が混入した例がある)
- 書き出し環境で使えるフォントは `fc-list :lang=ja family`、解決結果は `fc-match <名前>` で確認する
- Linuxの既定は `IPAPGothic`(IPA Pゴシック)

## PNG書き出し

```sh
scripts/export-png.sh <input.drawio> [output.png]
```

- 環境変数: `DIAGRAM_FONT`(既定 IPAPGothic)、`PAGE_WIDTH` / `PAGE_HEIGHT`(既定 1400 / 900)、
  `LEFT_MARGIN` / `TOP_MARGIN`(既定 40 / 18)
- 必要なもの: `drawio`(Draw.io Desktop、PATHに通す)、`ffmpeg`、`ffprobe`、`fontconfig`、指定フォント。
  画面のない環境では `xvfb-run`
- スクリプトは、フォント指定のないstyleがあれば止まり、出力をページサイズの白背景へ配置して寸法を検証する
- スクリプトが使えない場合、またはページに収まらない図は、Draw.io Desktopからページ単位・余白0・拡大率100%で
  書き出し、寸法を目視で確認する
