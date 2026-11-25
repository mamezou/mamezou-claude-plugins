# 資料の構成の原則

資料の構成を検査する12の観点と、種類ごとの章の単位、採らなかった手法、出典。種類ごとの確認は、種類ごとのチェックリストを使う。

## 12の観点

### 骨子の前に決めること

| 番号 | 観点 | 検査の問い | 当たったときの直し方 | 出典 |
|---|---|---|---|---|
| 1 | 資料の種類 | 判断を求める資料、設計の記録、手順書、説明の資料のどれか1つに決めたか。1つの章に別の種類の中身が入っていないか | 種類を1つ選び、「資料の種類ごとの章の単位」の表の単位で章を切る。別の種類の中身は別の資料か末尾へ分ける | Diátaxis、Information Mapping、公用文作成の考え方 III-4 |
| 2 | 読み手と、決めることの一覧 | 読み手は誰で、読む前に何を知っていて、読んだ後に何を決めるか、何をするか。決めることを番号を付けて全部並べたか | 一覧を作ってから章を切る。各項目に、案、判断の材料、期限、なぜ今決めるかを付ける | Google の技術文書の講座 第1部、判断を求める文書の手引き |
| 3 | 範囲と範囲外 | 資料が扱うことと、読み手が載っていると期待するが扱わないことを書いたか | 前提の章に、扱わないことと行わないことの一覧を置く。範囲に入らない章は消す | Google の技術文書の講座 第1部、Google の設計書 |

### 章の切り方

| 番号 | 観点 | 検査の問い | 当たったときの直し方 | 出典 |
|---|---|---|---|---|
| 4 | 全体と部分の対応 | 冒頭に答えと決めることの一覧があるか。章は一覧と同じ順、同じ呼び名か。題と見出しが対応しているか | 冒頭に一覧を置き、章の題を一覧の呼び名にそろえる。冒頭の背景は、読み手が同意する事実に限る | ピラミッド原則、BLUF、公用文作成の考え方 III-2 |
| 5 | 1つの判断に1つの章と、章の中の型 | 1つの判断の材料が1つの章に集まっているか。章の中に、選択肢、比較の基準、比較、推奨、選んだ結果として起きることがあるか。選択肢に現状のままの案があるか | 材料を判断の章へ集める。基準を比較の表の前に書き、比較の表の列を基準にそろえる | MADR、SOCCR、判断を求める文書の手引き |
| 6 | 重なりが無い | 同じ話題と同じ数値は、何か所に出るか | 正とする場所を1つ決め、ほかの場所からは消す。冒頭の一覧は例外とする | MECE、Information Mapping |
| 7 | 抜けが無い | 一覧と表に母集団を決めたか。母集団の各項目は、対象、対象外、行わない、のどれかで資料に出るか | 母集団を正本から取る。構成要素なら構成の正本、議題なら議事録と定例のメモ | MECE |
| 8 | 分類の軸と呼び名 | 同じ階層の章、節、表の行は、1つの切り口で分かれた同じ種類のものか。同じものを同じ呼び名で書いているか | 切り口を1つ選び、混ざった中身を章に分ける。呼び名を初出にそろえる | ピラミッド原則、Information Mapping |

### 読む順と量

| 番号 | 観点 | 検査の問い | 当たったときの直し方 | 出典 |
|---|---|---|---|---|
| 9 | 結論と根拠の上下 | 判断を求める資料と説明の資料で、章の1文目は、下の中身をまとめた結論か。表を読んで何が言えるかを1文で書けるか | 1文で書けない表は、末尾へ移すか消す | ピラミッド原則 |
| 10 | 並びの順 | 章の順と、章の中の項目の順は、時間、構造、重要度のどれか1つで、何の順かを言えるか。読み手が前後に行き来しないか | 順を1つ選んで並べ直す。一般の話を先に、例外と条件を後にする | ピラミッド原則、米国政府の平易な文書の手引き |
| 11 | 詳細の置き場所と分量 | 本文は、読み手の判断か作業を変える中身に限っているか。判断も作業も変えない計算の内訳、例外、背景は末尾か別の資料にあるか。作業の条件を変える例外は、当たる手順の直前にあるか。骨子で章ごとの分量の目安を決めたか | 詳細を参考情報か別の資料へ移し、本文からリンクする。目安を超えた章は、移す中身を決める | Information Mapping、公用文作成の考え方 III-4、Google の技術文書の講座 第2部 |
| 12 | 見出しだけで読める | 題、見出し、各章の1文目だけを読んで、読み手が何をする資料かを言えるか。判断を求める資料は推奨、手順書は作業の順、設計の記録は対象の範囲、説明の資料は問いへの答え。見出しの最初の語で中身が分かるか | 見出しに判断か対象の名前を入れる。「背景」「参考情報」「その他」の章に、判断に使う中身を置かない | 公用文作成の考え方 III-2、Nielsen Norman Group、ピラミッド原則 |

## 資料の種類ごとの章の単位

| 種類 | 読み手がすること | 章を切る単位 | 並びの順 | 出典 |
|---|---|---|---|---|
| 判断を求める資料 | 決める | 決めること1つに章1つ | 後の判断の前提になる判断を先に | MADR、SOCCR |
| 設計の記録 | 調べる | 構成要素など、対象の構造 | 対象の構造の順 | Diátaxis の reference |
| 手順書 | 作業する | 作業1つに章1つ | 作業を行う順 | Diátaxis の how-to、米国政府の平易な文書の手引き |
| 説明の資料 | 理解する | 読み手の問い1つに章1つ | 一般の話を先に、例外を後に | Diátaxis の explanation |


## 採らなかった手法

| 手法 | 採らなかった理由 |
|---|---|
| SOCCR の、意見が割れる判断では推奨を最後に置く並び | 結論を先に書く今の決まりと逆になる |
| Information Mapping の、1つのまとまりを7前後の項目に限る決まり | 出典のページ自体が、根拠の研究に疑いがあると書いている |
| MECE を全部の一覧に当てること | 出典のページが、MECE は余計な項目を除かないことと、重なりが要る場合があることを限界に挙げている。3番と11番で余計な項目を除き、冒頭の一覧を重なりの例外にした |
| Diátaxis の tutorial | 学習用の教材で、案件の資料に当たるものが無い |
| IMRAD、逆ピラミッド、Amazon の6ページの文書 | 論文、記事、社内の企画書の型で、4番と9番に同じ中身がある。Amazon は、読んだページに章ごとの中身が書かれていなかった |
| Nielsen Norman Group の、太字と枠で目立たせる決まり | 体裁の話で、構成の検査の対象外 |

## 出典

- ピラミッド原則の要約: https://lethain.com/pyramid-principle/
- ピラミッド原則の要約: https://strategyu.co/pyramid-principle-partone/
- MECE: https://en.wikipedia.org/wiki/MECE_principle
- MECE: https://ja.wikipedia.org/wiki/MECE
- BLUF: https://en.wikipedia.org/wiki/BLUF_(communication)
- 逆ピラミッド: https://en.wikipedia.org/wiki/Inverted_pyramid_(journalism)
- IMRAD: https://en.wikipedia.org/wiki/IMRAD
- Google の技術文書の講座 第1部: https://developers.google.com/tech-writing/one/documents
- Google の技術文書の講座 第2部: https://developers.google.com/tech-writing/two/large-docs
- Google の設計書: https://www.industrialempathy.com/posts/design-docs-at-google/
- MADR: https://adr.github.io/madr
- SOCCR: https://jacobian.org/2021/jan/30/soccr
- 判断を求める文書の手引き: https://www.boardintelligence.com/the-definitive-guide-to-decision-papers
- Diátaxis: https://diataxis.fr/start-here/
- Information Mapping: https://en.everybodywiki.com/Information_mapping
- 公用文作成の考え方: https://www.bunka.go.jp/seisaku/bunkashingikai/kokugo/hokoku/pdf/93731901_01.pdf
- 米国政府の平易な文書の手引き: https://digital.gov/guides/plain-language/principles/organize
- Nielsen Norman Group の読み方の調査: https://www.nngroup.com/articles/f-shaped-pattern-reading-web-content/
- Amazon の6ページの文書: https://www.anecdote.com/2018/05/amazons-six-page-narrative-structure/
- ISO 24495-1 の概要: https://www.iso.org/standard/78907.html
