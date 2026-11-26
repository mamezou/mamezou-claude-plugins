#!/bin/bash
# harness-ja 共通: 文面の語と日付の検査。draft-precheck.sh が取り込む。
#
#   harness_strip_quoted                     標準入力の文から、コードブロック・バッククォートの中・「」『』の中・URL を除く
#   harness_colloquial_hits                  話し言葉の語を探す (語の表は hooks/data/colloquial-terms.tsv)
#   harness_date_hits <asof|strict> [見出し] 本文の日付を探す (表・コードブロック・URL・ファイル名・記録の節は除く)
#   harness_apply_edit <前の全文のファイル>  Edit / MultiEdit の後の全文を作る
#
# 語の表の書式は、tsv の先頭の説明のとおり (語 / 正規表現 / 使う語 / 除く言い回し)。
#   HARNESS_EXTRA_TERMS    プロジェクトで追加する行 (同じ書式)。draft-precheck.sh が colloquial.extraTerms[] から作る
#   HARNESS_EXCLUDE_TERMS  外す行の語 (1 行に 1 語。tsv の 1 列目と同じ文字列)
#   HARNESS_HITS_MAX       出す件数の上限 (既定 8。件数を数える道具が大きい値を渡す)
# 日本語の文字を1文字として照合するため、関数の中だけ UTF-8 のロケールにする
# (取り込んだ hook のほかの検査のロケールは変えない)。

HARNESS_TERMS_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/data/colloquial-terms.tsv"

harness_strip_quoted() {
  local -x LC_ALL=C.UTF-8
  awk '/^[ \t]*```/{c=!c; print ""; next} c{print ""; next} {print}' \
    | sed -E 's/`[^`]*`//g; s/「[^」]*」//g; s/『[^』]*』//g; s#https?://[^ )>]*##g'
}

# 出力: 「<行番号>行: <当たった語> → <使う語> [表の行: <語>]」を 8 件まで
harness_colloquial_hits() {
  local -x LC_ALL=C.UTF-8
  local text term re sub except t
  text=$(harness_strip_quoted)
  { [[ -f "$HARNESS_TERMS_FILE" ]] && cat "$HARNESS_TERMS_FILE"; printf '%s\n' "${HARNESS_EXTRA_TERMS:-}"; } \
    | while IFS=$'\t' read -r term re sub except; do
        case "$term" in ''|'#'*) continue ;; esac
        [[ -n "$re" && "$re" != "-" ]] || continue
        if [[ -n "${HARNESS_EXCLUDE_TERMS:-}" ]] && grep -qxF -- "$term" <<< "$HARNESS_EXCLUDE_TERMS"; then continue; fi
        t="$text"
        # 除く言い回しは、「□」に置き換えてから照合する (行番号は変わらない)
        if [[ -n "$except" ]]; then t=$(printf '%s\n' "$t" | sed -E "s/($except)/□/g" 2>/dev/null || printf '%s\n' "$t"); fi
        printf '%s\n' "$t" | grep -noP -- "$re" 2>/dev/null \
          | awk -v s="$sub" -v k="$term" '{n=$0; sub(/:.*/,"",n); w=$0; sub(/^[0-9]+:/,"",w); print n "行: " w " → " s " [表の行: " k "]"}' || true
      done | sort -t: -k1,1n -s | awk '!seen[$0]++' | head -"${HARNESS_HITS_MAX:-8}"
}

# 本文の日付を探す。次の場所の日付は見ない:
#   表の行 (| か <t で始まる行)、コードブロック、バッククォートの中、URL、ファイル名やパスの中
#   (前後が英数字・_・/・-・. でつながる日付)、記録の節 (見出しが第 2 引数の正規表現に一致する節。
#   次の同じ深さ以上の見出しまで)、「約1/3」の形の分数
# asof のときは、いつの値かを示す日付 (直後が 時点・現在・から・まで・以降・以前・〜) も見ない。
# 出力: 当たった行の本文を 1 行ずつ (行番号は付けない。Edit の前後を行の本文で比べるため)
harness_date_hits() {
  local -x LC_ALL=C.UTF-8
  local mode="${1:-asof}" rec="${2:-記録|履歴|経緯|改訂|変更ログ|作業ログ|[Cc]hangelog|[Hh]istory}"
  local d4='[0-9]{4}[-/](1[0-2]|0?[1-9])[-/](3[01]|[12][0-9]|0?[1-9])|[0-9]{4}年(1[0-2]|0?[1-9])月((3[01]|[12][0-9]|0?[1-9])日)?'
  local d2='(1[0-2]|0?[1-9])月(3[01]|[12][0-9]|0?[1-9])日|(1[0-2]|0?[1-9])/(3[01]|[12][0-9]|0?[1-9])'
  local pre='(?<![A-Za-z0-9_./-])' post='(?![0-9]|[-_/][A-Za-z0-9]|\.[A-Za-z0-9])' asof=''
  [[ "$mode" == asof ]] && asof='(?!(日)?(の)?(時点|現在|から|まで|以降|以前|〜|～))'
  awk -v rec="$rec" '
    /^[ \t]*```/ { c = !c; next }
    c { next }
    /^#{1,6}[ \t]/ {
      lv = match($0, /[^#]/) - 1
      if ($0 ~ rec) { inrec = 1; reclv = lv; next }
      if (inrec && lv <= reclv) inrec = 0
      next
    }
    inrec { next }
    /^[ \t]*(\||<t)/ { next }
    { print }' \
    | sed -E 's/`[^`]*`//g; s#https?://[^ )>]*##g; s#約[0-9]+/[0-9]+##g' \
    | grep -P -- "${pre}(${d4}|${d2})${post}${asof}" || true
}

# harness_apply_edit <前の全文のファイル>
# 標準入力の hook 入力 (Edit / MultiEdit) の置き換えを、前の全文に当てた後の全文を出す。
# old_string が見つからない置き換えは飛ばす。前の全文のファイルが無ければ何も出さず 1 を返す。
harness_apply_edit() {
  local before="$1"
  [[ -f "$before" ]] || return 1
  jq -r --rawfile s "$before" '
    def rep($o; $n; $all):
      if ($o | length) == 0 then .
      else (split($o)) as $p
        | if ($p | length) < 2 then .
          elif $all then ($p | join($n))
          else $p[0] + $n + ($p[1:] | join($o)) end
      end;
    (.tool_input // {}) as $t
    | (if ($t.edits | type) == "array" then $t.edits else [$t] end) as $e
    | reduce $e[] as $x ($s; rep(($x.old_string // ""); ($x.new_string // ""); ($x.replace_all // false)))'
}
