#!/bin/bash
# 送付前 grep チェック。/docs-tools:draft-precheck から呼ばれる。
# 使い方: precheck.sh <チェック対象ファイル>
# 各項目の出現行を印字する。判定(残す / 直す)は Skill 本文の基準で行う。

set -uo pipefail
export LC_ALL=C.UTF-8

# 空白を含むパスが引用符なしで渡ると複数の引数に分かれるため、全引数を1つのパスとして扱う。
# 引用符が文字のまま渡ったときは、両端が同じ種類の引用符で対になっている場合だけ外す
f="$*"
if [[ ! -f "$f" ]]; then
  case "$f" in
    \"?*\" | \'?*\') f="${f:1:${#f}-2}" ;;
  esac
fi
if [[ -z "$f" || ! -f "$f" ]]; then
  echo "対象ファイルが見つかりません: ${f:-(未指定)}" >&2
  exit 1
fi

section() { printf '\n[%s]\n' "$1"; }
none() { echo "  なし"; }

# 地の文を「。」で分け、「元の行番号:文」で印字する。コードブロックと、行頭が | の表の行は外す。
# コードブロックは、開いたフェンスと同じ記号で、開始時以上の長さのフェンスだけで閉じる
sentences() {
  local n=0 fence="" mark line
  local fence_re='^[[:space:]]*(`{3,}|~{3,})' table_re='^[[:space:]]*\|'
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1))
    line="${line%$'\r'}"
    if [[ "$line" =~ $fence_re ]]; then
      mark="${BASH_REMATCH[1]}"
      if [[ -z "$fence" ]]; then
        fence="$mark"
        continue
      fi
      if [[ "${mark:0:1}" == "${fence:0:1}" ]] && (( ${#mark} >= ${#fence} )); then
        fence=""
        continue
      fi
    fi
    if [[ -n "$fence" || "$line" =~ $table_re ]]; then
      continue
    fi
    while [[ "$line" == *。* ]]; do
      printf '%d:%s。\n' "$n" "${line%%。*}"
      line="${line#*。}"
    done
    if [[ "$line" == *[![:space:]]* ]]; then
      printf '%d:%s\n' "$n" "$line"
    fi
  done < "$f"
  return 0
}

# 同じ形の文が3文以上続く箇所を「開始行:形と文数: 原文」で印字する。形は、end なら文末
# (「。」の前の2字)、head なら書き出し(主題の直後に読点を打つ「〜は、」)で比べる。
# 空行・見出し・箇条書きの項目・表・コードブロックをまたぐと数え直す
same_form() {
  local mode="$1" s n t k key="" buf="" cnt=0 start=0 prev=0 found=1
  local item_re='^[[:space:]]*(#|■|・|[-*+][[:space:]]|[0-9]+[.)][[:space:]])'
  local topic_re='^[[:space:]]*[^、。]{1,40}は、'
  while IFS= read -r s; do
    n="${s%%:*}"
    t="${s#*:}"
    k=""
    if [[ "$t" == *。 && ! "$t" =~ $item_re ]]; then
      if [[ "$mode" == head ]]; then
        if [[ "$t" =~ $topic_re ]]; then
          k="「〜は、」で始まる文"
        fi
      else
        k="${t%。}"
        k="${k: -2}"
        if [[ -n "$k" ]]; then
          k="「${k}。」で終わる文"
        fi
      fi
    fi
    if [[ -n "$k" && "$k" == "$key" ]] && (( n - prev <= 1 )); then
      cnt=$((cnt + 1))
      buf+="$t"
    else
      if (( cnt >= 3 )); then
        printf '%d:%sが%d文: %s\n' "$start" "$key" "$cnt" "$buf"
        found=0
      fi
      key="$k"
      buf="$t"
      start="$n"
      cnt=1
    fi
    prev="$n"
  done <<< "$sents"$'\n0:' # 末尾に空の文を足し、最後の並びも印字させる
  return "$found"
}

# 読点が2つ以上ある文を「元の行番号:読点の数: 文」で印字する。括弧の中の読点は数えない。
# 「。」で終わる文だけを見る (名詞を並べた箇条書きの項目を外すため)
many_commas() {
  local s t rest only found=1
  local paren_re='[（(][^（()）]*[）)]'
  while IFS= read -r s; do
    t="${s#*:}"
    if [[ "$t" != *。 ]]; then
      continue
    fi
    rest="$t"
    while [[ "$rest" =~ $paren_re ]]; do
      rest="${rest/"${BASH_REMATCH[0]}"/}"
    done
    only="${rest//[^、]/}"
    if (( ${#only} >= 2 )); then
      printf '%s:読点%d: %s\n' "${s%%:*}" "${#only}" "$t"
      found=0
    fi
  done <<< "$sents"
  return "$found"
}

sents="$(sentences)"

section "内部パス断片"
grep -nE '(^|[^A-Za-z0-9])(docs|src|scripts|exports)/' -- "$f" || none
section "絶対パス"
grep -nE '(/home/|/tmp/|/var/)' -- "$f" || none
section "ローカル拡張子の素出し"
grep -nE '\.(md|ps1|drawio|kql)([[:space:]]|$|[、。)）」])' -- "$f" || none
section "文脈依存度の高い英単語 (要文脈確認)"
grep -nE '(レイヤー|パイプライン|フェーズ|ターゲット)' -- "$f" || none
section "組版記号 § ¶ ‡ †"
grep -nE '(§|¶|‡|†)' -- "$f" || none
section "外部 AI 言及"
grep -nE '(Codex|ChatGPT|Gemini|Copilot)' -- "$f" || none
section "指示語の出現行"
grep -nE '(これ|それ|その|この|こうした)' -- "$f" || none
section "括弧の中身"
grep -noE '[（(][^（()）]{2,}[）)]' -- "$f" || none
section "同じ括弧の中身が3回以上 (回数 中身)"
# 括弧を外した中身で数える (全角と半角の括弧を同じものとして数えるため)。表の行も数える
grep -oE '[（(][^（()）]{2,}[）)]' -- "$f" | sed -E 's/^(（|\()//; s/(）|\))$//' | sort | uniq -c | sort -rn | grep -E '^ *([3-9]|[1-9][0-9]+) ' || none
section "3回以上の長い識別子"
grep -oE '[A-Za-z][A-Za-z0-9_./-]{19,}' -- "$f" | sort | uniq -c | sort -rn | grep -E '^ *([3-9]|[1-9][0-9]+) ' || none
section "60字超の文"
grep -E '^[0-9]+:.{61,}' <<< "$sents" || none
section "読点が2つ以上の文 (括弧の中の読点は数えない)"
many_commas || none
section "予告の文 (次のとおり / 次の〜がある / 以下に示す)"
grep -E '((次|以下|下記)の((とおり|通り)(です|である|とする)?|[^、。]*が(ある|あります))[。:：]|(次|以下|下記)に示す。)$' <<< "$sents" || none
section "同じ文末が3文以上続く箇所"
same_form end || none
section "「〜は、」で始まる文が3文以上続く箇所"
same_form head || none
section "物や事柄を主語にしがちな文末 (発生する / 決まる / 変わる)"
grep -E '(発生(する|しない|します|しません)|決ま(る|らない|ります|りません)|変わ(る|らない|ります|りません))。$' <<< "$sents" || none
section "未確認の印"
grep -nE '(未確認|要確認|TBD|未定|要判断)' -- "$f" || none
section "バイト数"
wc -c < "$f"
