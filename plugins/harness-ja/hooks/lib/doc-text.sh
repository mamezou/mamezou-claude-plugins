#!/bin/bash
# harness-ja 共通: 文面の語と日付の検査。draft-precheck.sh と draft-bash-write-check.sh が取り込む。
#
#   harness_doc_config_errors <colloquial|dates|bashWrites>  設定の型と正規表現の誤りを 1 行ずつ出す (無ければ何も出さない)
#   harness_strip_quoted                     標準入力の文から、コードブロック・バッククォートの中・「」『』の中・URL を除く
#   harness_colloquial_hits                  話し言葉の語を探す (語の表は hooks/data/colloquial-terms.tsv)
#   harness_date_hits <asof|strict> [見出し] 本文の日付を探す (表・コードブロック・URL・ファイル名・記録の節は除く)
#   harness_apply_edit <前の全文のファイル>  Edit / MultiEdit の後の全文を作る
#   harness_new_lines <前の文のファイル>     標準入力の行のうち、前の文に無い行の番号を出す (同じ行は回数で数える)
#
# 語の表の書式は、tsv の先頭の説明のとおり (語 / 正規表現 / 使う語 / 除く言い回し)。
#   HARNESS_EXTRA_TERMS    プロジェクトで追加する行 (同じ書式)。draft-precheck.sh が colloquial.extraTerms[] から作る
#   HARNESS_EXCLUDE_TERMS  外す行の語 (1 行に 1 語。tsv の 1 列目と同じ文字列)
#   HARNESS_HITS_MAX       出す件数の上限 (既定 8。件数を数える道具が大きい値を渡す)
# 正規表現は、照合 (2 列目) も除く言い回し (4 列目) も Perl 互換 (照合は grep -P、置き換えは perl)。
# 日本語の文字を1文字として照合するため、関数の中だけ UTF-8 のロケールにする
# (取り込んだ hook のほかの検査のロケールは変えない)。
# 件数を絞るところは head を使わない (pipefail の下で、前のコマンドが SIGPIPE で 141 を返し、hook が
# 止める前に終わるため)。入力を最後まで読む awk で絞る。

HARNESS_TERMS_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/data/colloquial-terms.tsv"
# URL に使う字 (日本語の句読点と括弧は URL の終わりとして扱う)
HARNESS_URL_RE='https?://[A-Za-z0-9._~:/?#@!$&*+,;=%-]+'

# 正規表現が Perl 互換として読めれば 0
harness_pcre_ok() {
  local -x LC_ALL=C.UTF-8
  local rc=0
  printf '\n' | grep -qP -- "$1" 2>/dev/null || rc=$?
  [[ "$rc" -le 1 ]]
}

# harness_doc_config_errors <colloquial|dates|bashWrites>
# HARNESS_CONFIG_JSON の、指定した検査の設定を確かめる。誤りを 1 行ずつ出す。
# 設定の誤りを「当たりなし」として通さないため、hook はこの出力があれば止める。
harness_doc_config_errors() {
  local -x LC_ALL=C.UTF-8
  local kind="$1" out rc=0 row field re
  out=$(printf '%s' "${HARNESS_CONFIG_JSON:-}" | jq -r --arg k "$kind" '
    def strs($n): if . == null then empty
      elif (type == "array" and all(.[]; type == "string")) then empty
      else "\($n) は文字列の配列で書く" end;
    def str1($n): if . == null or (type == "string" and (test("[\t\n]") | not)) then empty
      else "\($n) は、タブと改行を含まない文字列で書く" end;
    (.draftPrecheck // {}) as $d
    | if $k == "colloquial" then
        ($d.colloquial) as $c
        | if $c == null then empty
          elif ($c | type) != "object" then "draftPrecheck.colloquial はオブジェクトで書く"
          else
            ($c.excludeTerms | strs("draftPrecheck.colloquial.excludeTerms")),
            (if $c.extraTerms == null then empty
             elif ($c.extraTerms | type) != "array" then "draftPrecheck.colloquial.extraTerms は配列で書く"
             else ($c.extraTerms | to_entries[] | "draftPrecheck.colloquial.extraTerms[\(.key)]" as $n | .value
               | if type != "object" then "\($n) はオブジェクトで書く"
                 else
                   (if (.pattern | type) == "string" and (.pattern | length) > 0 then (.pattern | str1("\($n).pattern"))
                    else "\($n).pattern は空でない文字列で書く" end),
                   (.use | str1("\($n).use")), (.term | str1("\($n).term")), (.except | str1("\($n).except")),
                   (.targets | strs("\($n).targets"))
                 end)
             end)
          end
      elif $k == "dates" then
        ($d.dates) as $c
        | if $c == null then empty
          elif ($c | type) != "object" then "draftPrecheck.dates はオブジェクトで書く"
          else
            ($c.targets | strs("draftPrecheck.dates.targets")),
            ($c.strictTargets | strs("draftPrecheck.dates.strictTargets")),
            ($c.recordHeadings | str1("draftPrecheck.dates.recordHeadings"))
          end
      else ($d.bashWriteDirs | strs("draftPrecheck.bashWriteDirs")) end' 2>&1) || rc=$?
  if [[ "$rc" -ne 0 ]]; then printf '設定を読めません (jq の終了コード %s)\n' "$rc"; return 0; fi
  [[ -z "$out" ]] || { printf '%s\n' "$out"; return 0; }
  case "$kind" in
    colloquial)
      if ! printf 'あ\n' | grep -qP -- 'あ' 2>/dev/null; then echo "grep -P (Perl 互換の正規表現) が、この環境で動きません"; return 0; fi
      if ! command -v perl >/dev/null 2>&1; then echo "perl が、この環境にありません"; return 0; fi
      while IFS=$'\t' read -r field re; do
        [[ -n "$re" ]] || continue
        harness_pcre_ok "$re" || printf '%s の正規表現を読めません: %s\n' "$field" "$re"
      done < <(printf '%s' "$HARNESS_CONFIG_JSON" | jq -r '.draftPrecheck.colloquial.extraTerms // [] | to_entries[]
          | ("draftPrecheck.colloquial.extraTerms[\(.key)]" as $n | .value
             | [$n + ".pattern", .pattern], (select((.except // "") != "") | [$n + ".except", .except])) | @tsv' 2>/dev/null)
      ;;
    dates)
      if ! printf 'あ\n' | grep -qP -- 'あ' 2>/dev/null; then echo "grep -P (Perl 互換の正規表現) が、この環境で動きません"; return 0; fi
      re=$(printf '%s' "$HARNESS_CONFIG_JSON" | jq -r '.draftPrecheck.dates.recordHeadings // empty' 2>/dev/null)
      if [[ -n "$re" ]] && ! awk -v rec="$re" 'BEGIN { if ("" ~ rec) x = 1 }' </dev/null >/dev/null 2>&1; then
        printf 'draftPrecheck.dates.recordHeadings の正規表現を読めません: %s\n' "$re"
      fi
      ;;
  esac
  return 0
}

harness_strip_quoted() {
  local -x LC_ALL=C.UTF-8
  awk '/^[ \t]*(```|~~~)/{c=!c; print ""; next} c{print ""; next} {print}' \
    | sed -E "s/\`[^\`]*\`//g; s/「[^」]*」//g; s/『[^』]*』//g; s|${HARNESS_URL_RE}||g"
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
        if [[ -n "$except" ]]; then
          t=$(printf '%s\n' "$t" | HARNESS_EXCEPT="$except" perl -CSD -Mutf8 -pe \
            'BEGIN { $e = $ENV{HARNESS_EXCEPT}; utf8::decode($e); $re = qr/$e/ } s/$re/□/g' 2>/dev/null || printf '%s\n' "$t")
        fi
        printf '%s\n' "$t" | grep -noP -- "$re" 2>/dev/null \
          | awk -v s="$sub" -v k="$term" '{n=$0; sub(/:.*/,"",n); w=$0; sub(/^[0-9]+:/,"",w); print n "行: " w " → " s " [表の行: " k "]"}' || true
      done | sort -t: -k1,1n -s | awk -v max="${HARNESS_HITS_MAX:-8}" '!seen[$0]++ && ++n <= max'
}

# 本文の日付を探す。次の場所の日付は見ない:
#   表の行 (| で始まる行、区切りの行 |---|---| の前後の行、<table> <tr> <td> などの行)、コードブロック
#   (``` と ~~~)、バッククォートの中、URL、ファイル名やパスの中 (前後が英数字・_・/・-・. でつながる日付)、
#   記録の節 (見出しが第 2 引数の正規表現に一致する節。次の同じ深さ以上の見出しまで。中の深い見出しでは
#   終わらない)、「約1/3」の形の分数
# 記録の節でない見出しの文は見る。
# asof のときは、いつの値かを示す日付 (直後が 時点・現在・から・まで・以降・以前・〜。間の空白は許す) も見ない。
# 出力: 当たった行の本文を 1 行ずつ (行番号は付けない。Edit の前後を行の本文で比べるため)
harness_date_hits() {
  local -x LC_ALL=C.UTF-8
  local mode="${1:-asof}" rec="${2:-記録|履歴|経緯|改訂|変更ログ|作業ログ|[Cc]hangelog|[Hh]istory}"
  local d4='[0-9]{4}[-/](1[0-2]|0?[1-9])[-/](3[01]|[12][0-9]|0?[1-9])|[0-9]{4}年(1[0-2]|0?[1-9])月((3[01]|[12][0-9]|0?[1-9])日)?'
  local d2='(1[0-2]|0?[1-9])月(3[01]|[12][0-9]|0?[1-9])日|(1[0-2]|0?[1-9])/(3[01]|[12][0-9]|0?[1-9])'
  local pre='(?<![A-Za-z0-9_./-])' post='(?![0-9]|[-_/][A-Za-z0-9]|\.[A-Za-z0-9])' asof=''
  [[ "$mode" == asof ]] && asof='(?![ 　]*(日)?[ 　]*(の)?[ 　]*(時点|現在|から|まで|以降|以前|〜|～))'
  awk -v rec="$rec" '
    { L[NR] = $0 }
    END {
      n = NR
      for (i = 1; i <= n; i++) {
        if (L[i] ~ /^[ \t]*\|/) T[i] = 1
        if (L[i] ~ /^[ \t]*<\/?(table|thead|tbody|tfoot|tr|th|td|caption|colgroup|col)([ \t>\/]|$)/) T[i] = 1
        if (i < n && L[i] ~ /\|/ && L[i+1] ~ /^[ \t]*\|?[ \t]*:?-+:?[ \t]*(\|[ \t]*:?-+:?[ \t]*)+\|?[ \t]*$/) {
          for (j = i; j <= n && L[j] ~ /\|/; j++) T[j] = 1
        }
      }
      for (i = 1; i <= n; i++) {
        s = L[i]
        if (s ~ /^[ \t]*(```|~~~)/) { c = !c; continue }
        if (c) continue
        if (s ~ /^#{1,6}[ \t]/) {
          lv = match(s, /[^#]/) - 1
          if (inrec && lv <= reclv) inrec = 0
          if (!inrec && s ~ rec) { inrec = 1; reclv = lv; continue }
          if (inrec) continue
          print s
          continue
        }
        if (inrec || T[i]) continue
        print s
      }
    }' \
    | sed -E "s/\`[^\`]*\`//g; s|${HARNESS_URL_RE}||g; s#約[0-9]+/[0-9]+##g" \
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

# harness_new_lines <前の文のファイル>
# 標準入力の行のうち、前の文に無い行の番号を出す。同じ本文の行は回数で数える
# (前に 1 行あり、後に 2 行あれば、2 行目を新しい行として出す)。
harness_new_lines() {
  awk -v bf="$1" 'BEGIN { while ((getline l < bf) > 0) c[l]++ } { if (c[$0] > 0) c[$0]--; else print NR }'
}
