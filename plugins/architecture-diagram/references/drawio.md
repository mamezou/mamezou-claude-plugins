# draw.io の扱い

## 元データとPNG

- `.drawio` が編集元(正本)、PNGは派生物。同じ基底名で置き、編集元を変えたらPNGを書き出し直す

## XMLの書き方

- 線のセルは自己終了タグにせず、子に `<mxGeometry relative="1" as="geometry" />` を持たせる。ないと線が正しく描かれない
- XMLのコメント(`<!-- -->`)は書かない
- 属性値の `&` `<` `>` `"` は `&amp;` `&lt;` `&gt;` `&quot;` と書く。ラベルの改行は `&#xa;`
- idは `vpc` `edge-alb-to-ecs` のように中身が分かる名前にし、重複させない。線の `source` と `target` は実在するidを指す
- 凡例の見本の線は、線のセルではなく `line` 図形で描く(`fontFamily=IPAPGothic;line;html=1;strokeWidth=<太さ>;strokeColor=<色>;`。
  破線は `dashed=1;dashPattern=<値>;` を足す)。太さ、色、破線の指定は、図の中の線と同じにする
- テンプレートの `page-background`(ページ全体の白い四角)は写す。ないと、書き出しスクリプトが図を左40・上18の位置へ置き直すため、
  図の位置がずれる
- 要素が多い図は、先に閉じタグまで含む骨組み(`id="0"` と `id="1"` のセル、`page-background`)を書き、`</root>` の前へ枠、アイコン、線の順に書き足す。
  長いXMLを1回で書くと途中で切れることがある

## 線の接続点

- 線の出口と入口は `exitX` `exitY` `entryX` `entryY` で指定する。基本は辺の中央(上 0.5,0 / 下 0.5,1 / 左 0,0.5 / 右 1,0.5)。
  指定しないとdraw.ioが経路を決め、線がラベルの文字を貫くことがある
- アイコンの下にラベルがあるとき、下の辺につなぐ線はラベルの下で止める。入る側は
  `entryX=0.5;entryY=1;entryDy=<距離>;entryPerimeter=0`、出る側は `exitX=0.5;exitY=1;exitDy=<距離>;exitPerimeter=0` と書く
- ラベルの下から出す線の行き先が真下にないときは、出口の真下に経由点を置く(書き方は「線の経路とラベル」)。
  置かないと、線がラベルのすぐ下で横へ曲がる
- 距離は、アイコンの下端からラベルの下端までの長さに数ピクセル足した値にする(`template-aws.drawio` の `phase0` は 55 に 3 を足した 58)。
  `entryPerimeter=0` や `exitPerimeter=0` を書かないと `entryDy` や `exitDy` が効かず、線がラベルを貫く
- 同じ辺に2本以上つなぐときだけ中央から外し、2本なら 0.25 と 0.75、3本なら 0.25、0.5、0.75 に振り分ける

## 線の経路とラベル

- 線を通す位置を決めるときは、`mxGeometry` の中に経由点を書く。
  `<mxGeometry relative="1" as="geometry"><Array as="points"><mxPoint x="520" y="300" /></Array></mxGeometry>`
- 線のラベルが枠線やほかの線に重なるときは、`<mxGeometry x="-0.3" relative="1" as="geometry" />` のように `x` でラベルを線に沿ってずらす。
  `x` は -1(始点)から 1(終点)の間で指定し、0 が線の中央
- ラベルを線の上からどけるときは、同じ `mxGeometry` に `y` を足す(`<mxGeometry x="0.3" y="18" relative="1" as="geometry" />`)。
  `y` は線と直交する向きへずらす距離で、左から右へ進む線では正の値で上へ動く

## SVGアイコンの埋め込み

- URLエンコード方式を使う: `image=data:image/svg+xml,<URLエンコードしたSVG>`
- Base64方式(`data:image/svg+xml;base64,...`)はdraw.ioで表示されない
- Python: `urllib.parse.quote(svg_text)` でエンコードし、styleの `image=` に指定する
- AWSは `mxgraph.aws4.*` 図形、Azureは `image=img/lib/azure2/<カテゴリ>/<名前>.svg` の
  内蔵アイコンがあるので、通常は埋め込み不要
- オンプレミスの機器は、内蔵の `mxgraph.cisco19.*` 図形と `mxgraph.vvd.*` 図形を使う

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
- 必要なもの: `drawio`(Draw.io Desktop、PATHに通す)、`ffmpeg`、`ffprobe`、`fontconfig`、`python3`、指定フォント。
  画面のない環境では `xvfb-run`
- スクリプトは、XMLが壊れているとき、圧縮保存された図のとき、フォント指定のないstyleがあるときに止まる。
  スクリプトは、出力をページサイズの白背景へ配置し、寸法を検証する
- スクリプトが使えない場合、またはページに収まらない図は、Draw.io Desktopからページ単位・余白0・拡大率100%で
  書き出し、寸法を目視で確認する

## アイコン名の検索

```sh
scripts/find-icon.sh <aws|azure> <語>
```

- 手元のDraw.io Desktopに入っているアイコンから、名前に語を含むものを出す。語は小文字にし、空白を `_` に置き換えて照合する。
  見つからなければ `no match` と出る
- AWSは `resIcon=mxgraph.aws4.<名前>`(サービスアイコン)か `shape=mxgraph.aws4.<名前>`(リソースアイコン)に続けて、
  パレットでの表示名とカテゴリを出す。Azureは、styleの `image=img/lib/azure2/` に続けて書くパスを出す
- 必要なもの: `drawio`、`python3`。Draw.io本体の `resources/app.asar` を読む。見つからないときは、環境変数 `DRAWIO_ASAR` に
  そのファイルのパスを指定する

## 既存の図を直す

1. `<diagram>` の中身が英数字の塊なら圧縮保存された図。`drawio -x -f xml -o <展開後.drawio> <元.drawio>` で展開してから読む
2. `<mxfile>` と `<diagram>` の外枠は残し、`<mxGraphModel>` の中だけを直す。`<diagram>` が複数あれば依頼されたページだけを直す。
   どのページか分からなければページ名を挙げて聞く
3. 依頼された箇所だけを変える。既存のid・座標・styleは残し、足す要素はこのSkillのルールに従って描く。
   元の図がこのSkillのルールと違っていても、依頼になければ直さず、気づいた点を伝える
4. 足す要素が収まらず周りを動かしたときは、動かしたものを伝える
5. 保存先の指定がなければ、直した内容を元のファイルのパスへ上書きする。圧縮保存だった図は展開した形のまま保存し、そのことを伝える
6. 作るときと同じくPNGを書き出して確認する。元の図にフォント指定や `page-background` がなく、スクリプトが止まるか図の位置がずれるときは、
   図を直さず `drawio -x -f png -o <出力.png> <図>` で書き出す(画面のない環境では `xvfb-run -a drawio --no-sandbox -x -f png -o <出力.png> <図>`)
