#!/bin/bash
# harness-ja 共通: 文面の語と日付の検査。draft-precheck.sh が取り込む。
#
#   harness_strip_quoted                 標準入力の文から、コードブロック・バッククォートの中・「」『』の中・URL を除く
#   harness_colloquial_hits <all|doc>    話し言葉の語を探す。doc は all の語も見る
#   harness_date_hits <asof|strict>      表の外の日付を探す
#
# 語の表は hooks/data/colloquial-terms.tsv (範囲 <TAB> grep -P の正規表現 <TAB> 使う語)。
# プロジェクトで追加する語は、環境変数 HARNESS_EXTRA_TERMS に同じ書式の行で渡す
# (draft-precheck.sh が draftPrecheck.colloquial.extraTerms[] から作る)。
# 日本語の文字を1文字として照合するため、関数の中だけ UTF-8 のロケールにする
# (取り込んだ hook のほかの検査のロケールは変えない)。

HARNESS_TERMS_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/data/colloquial-terms.tsv"

harness_strip_quoted() {
  local -x LC_ALL=C.UTF-8
  awk '/^[ \t]*```/{c=!c; print ""; next} c{print ""; next} {print}' \
    | sed -E 's/`[^`]*`//g; s/「[^」]*」//g; s/『[^』]*』//g; s#https?://[^ )>]*##g'
}

# 出力: 「<行番号>行: <当たった語> → <使う語>」を 8 件まで
harness_colloquial_hits() {
  local -x LC_ALL=C.UTF-8
  local scope="${1:-all}" text tier re sub
  text=$(harness_strip_quoted)
  { [[ -f "$HARNESS_TERMS_FILE" ]] && cat "$HARNESS_TERMS_FILE"; printf '%s\n' "${HARNESS_EXTRA_TERMS:-}"; } \
    | while IFS=$'\t' read -r tier re sub; do
        case "$tier" in ''|'#'*) continue ;; esac
        [[ -n "$re" ]] || continue
        [[ "$tier" == all || "$scope" == doc ]] || continue
        printf '%s\n' "$text" | grep -noP -- "$re" 2>/dev/null \
          | awk -v s="$sub" '{n=$0; sub(/:.*/,"",n); w=$0; sub(/^[0-9]+:/,"",w); print n "行: " w " → " s}' || true
      done | sort -t: -k1,1n -s | awk '!seen[$0]++' | head -8
}

# 表の行 (| か <t で始まる行)、コードブロック、URL の行は見ない。「約1/3」の形の分数は日付として数えない。
# asof のときは、いつの値かを示す日付 (直後が 時点・現在・から・まで・以降・以前・〜) を除いてから探す。
# 出力: 「<行番号>:<行>」を 5 件まで
harness_date_hits() {
  local -x LC_ALL=C.UTF-8
  local mode="${1:-asof}"
  local d4='[0-9]{4}[-/][0-9]{1,2}[-/][0-9]{1,2}|[0-9]{4}年[0-9]{1,2}月([0-9]{1,2}日)?'
  local d2='[0-9]{1,2}月[0-9]{1,2}日|[0-9]{1,2}/[0-9]{1,2}'
  awk '/^[ \t]*```/{c=!c; print ""; next} c || /^[ \t]*(\||<t)/ || /https?:\/\// {print ""; next} {print}' \
    | sed -E 's#約[0-9]/[0-9]+##g' \
    | if [[ "$mode" == asof ]]; then sed -E "s#($d4|$d2)(の)?(時点|現在|から|まで|以降|以前|〜|～)#\\3#g"; else cat; fi \
    | grep -nE "(^|[^0-9.])[0-9]{1,2}/[0-9]{1,2}([^0-9]|\$)|[0-9]{1,2}月[0-9]{1,2}日|$d4" | head -5 || true
}
