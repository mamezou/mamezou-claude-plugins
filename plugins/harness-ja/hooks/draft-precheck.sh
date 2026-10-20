#!/bin/bash
# 送付文面の事前検査 hook (PreToolUse, matcher=Write|Edit|MultiEdit|mcp__.*)
# 先方・内部へ送る文面へ、内部パスやローカル拡張子・造語・組版記号・外部 AI 言及が混入するのを止める。
#
# 発火条件 (ファイルの編集):
#   - 編集対象のパスが draftPrecheck.targets[] のいずれか (bash の case パターン) に一致
#   - excludePatterns[] のいずれかをパスに含む場合は対象外
#   - cwd には依存しない (リポジトリルート起動のセッションでも発火する)
#
# 発火条件 (MCP ツールの呼び出し。メールやチャットの下書きのようにファイルを書かない文面):
#   - ツール名が draftPrecheck.toolRules[] の tool に一致する。tool は requireReading.toolRules と
#     同じ jq の test() の正規表現。配列順に照合し、最初に一致した要素を使う。excludePatterns[] は使わない
#   - 検査するのは、tool_input のうち fields[] に挙げた項目の文字列 (既定は subject と body)。
#     fields は文字列を1件以上含む配列に限る。htmlBody のような HTML の項目は、タグが検査に
#     混ざるため、既定に入れない
#   - requiredFields[] に挙げた引数が、tool_input にない、空白だけ、文字列でないときは止める
#     (既定は空で、何も求めない。下書きの ID だけで送る呼び出しを止めないため)。メールの
#     下書きを作るツールには ["body"] を書く。subject があっても、body がなく htmlBody だけで
#     本文を渡す呼び出しは、requiredFields を書かないと検査されずに通る
#   - 止めるのは終了コード 2 のとき。toolRules の形の誤り、tool の正規表現の誤り、tool_input が
#     配列や文字列の呼び出しは、検査できないため 2 で止める。toolRules の形は、tool_name が
#     mcp__ で始まる呼び出しのときに検証する
#   - toolRules に一致しない MCP ツールの呼び出しでは、何もしない
#
# 検査項目 (draftPrecheck.checks.<名前> を false にすると個別に止められる。既定はすべて true):
#   bannedTerms      設定の禁止語
#   internalPaths    内部リポジトリパス断片・絶対パス (URL を含む行は対象外)
#   extensions       ローカルファイル拡張子の素出し (.md / .ps1 / .drawio / .kql)
#   typography       組版記号 (§ ¶ ‡ †)
#   honorific        見出しでの敬称抜け
#   externalAi       外部 AI ツール名の言及
#   longIdentifiers  長い識別子のフル表記の繰り返し
#
# 検査範囲: Write は全文、Edit/MultiEdit は追加・置換後の文字列のみ。
#
# バイパス:
#   - 依頼者の最後のテキスト入力に [hook-bypass: draft-precheck] がそれだけの行としてある
#
# 設定 (.claude/harness.json):
#   draftPrecheck.enabled           false で無効化
#   draftPrecheck.targets[]         対象パスの case パターン (空なら、ファイルの編集では何もしない)
#   draftPrecheck.excludePatterns[] パスに含めば対象外にする文字列
#   draftPrecheck.toolRules[]       MCP ツールの規則 tool / fields / requiredFields
#   draftPrecheck.checks            検査項目ごとの on / off
#   draftPrecheck.bannedTerms[]     禁止語 (既定値は持たない)
#   draftPrecheck.honorific.name    敬称の検査対象名 (空なら検査しない)
#   draftPrecheck.honorific.suffix  付いているべき敬称 (既定「様」)

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/config.sh"

input=$(cat)
harness_load_config "$input"
harness_config_guard pre

if ! cfg_enabled '.draftPrecheck'; then
  exit 0
fi

target_count=$(cfg '.draftPrecheck.targets | length' '0')
tool_rule_count=$(cfg '.draftPrecheck.toolRules | length' '0')
if [[ "${target_count:-0}" -eq 0 && "${tool_rule_count:-0}" -eq 0 ]]; then
  exit 0
fi

check_on() { # check_on <検査名>
  cfg_flag ".draftPrecheck.checks.$1" 'true'
}

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')

tool_name=$(printf '%s' "$input" | jq -r '.tool_name // empty')
# tool_input が配列や文字列の入力でも、jq を異常終了させない (異常終了は 2 でないため、止まらない)
file_path=$(printf '%s' "$input" | jq -r '.tool_input | if type == "object" then (.file_path // .path // empty) else empty end')

# MCP ツールの呼び出し: toolRules に当たるものだけ、tool_input の文字列を検査する
mcp_mode=0
required_json='[]'
fields_json='["subject","body"]'
if [[ "$tool_name" == mcp__* ]]; then
  [[ "${tool_rule_count:-0}" -gt 0 ]] || exit 0
  # toolRules の形を先に検証する。形が壊れていると、jq が 2 以外で異常終了したり、規則なしとして
  # 通ったりして、検査できないため
  if ! printf '%s' "$HARNESS_CONFIG_JSON" | jq -e '
        (.draftPrecheck.toolRules | type == "array")
        and all(.draftPrecheck.toolRules[]?;
          type == "object"
          and ((.tool | type) == "string" and (.tool | length) > 0)
          and ((.fields // ["subject","body"]) | type == "array" and length > 0 and all(.[]; type == "string"))
          and ((.requiredFields // []) | type == "array" and all(.[]; type == "string")))' >/dev/null 2>&1; then
    printf '設定 draftPrecheck.toolRules の形が正しくありません。toolRules は配列で、各要素は、tool (空でない文字列)、fields (文字列を1件以上含む配列)、requiredFields (文字列の配列) を持つオブジェクトにしてください。\n' >&2
    exit 2
  fi
  while IFS= read -r rule; do
    [[ -z "$rule" ]] && continue
    tool_re=$(printf '%s' "$rule" | jq -r '.tool // empty')
    [[ -z "$tool_re" ]] && continue
    # 照合は requireReading.toolRules と同じ jq の test() にそろえる。
    # 終了コード 0 は一致、1 は不一致、それ以外は正規表現の誤り
    rc=0
    jq -en --arg n "$tool_name" --arg re "$tool_re" '$n | test($re)' >/dev/null 2>&1 || rc=$?
    if [[ "$rc" -gt 1 ]]; then
      printf '設定 draftPrecheck.toolRules の tool が正規表現として読めません: %s\n' "$tool_re" >&2
      exit 2
    fi
    if [[ "$rc" -eq 0 ]]; then
      fields_json=$(printf '%s' "$rule" | jq -c '.fields // ["subject","body"]')
      required_json=$(printf '%s' "$rule" | jq -c '.requiredFields // []')
      mcp_mode=1
      break
    fi
  done < <(cfg_list '.draftPrecheck.toolRules[]? | @json')
  [[ "$mcp_mode" -eq 1 ]] || exit 0
else
  [[ -z "$file_path" ]] && exit 0
fi

if [[ "$mcp_mode" -eq 0 ]]; then
  # 対象判定 (絶対/相対両対応)
  if [[ "$file_path" = /* ]]; then
    target_file_path="$file_path"
  else
    target_file_path="${cwd%/}/$file_path"
  fi

  is_target=0
  while IFS= read -r pat; do
    [[ -z "$pat" ]] && continue
    case "$target_file_path" in
      $pat) is_target=1; break ;;
    esac
  done < <(cfg_list '.draftPrecheck.targets[]?')
  [[ "$is_target" -eq 1 ]] || exit 0

  # 除外パターン (内部用・送信済み等) はここで抜ける
  while IFS= read -r ex; do
    [[ -z "$ex" ]] && continue
    if grep -qF -- "$ex" <<< "$file_path"; then
      exit 0
    fi
  done < <(cfg_list '.draftPrecheck.excludePatterns[]?')

  # tool_input から編集内容を取得
  case "$tool_name" in
    Write)
      content=$(printf '%s' "$input" | jq -r '.tool_input.content // empty')
      ;;
    Edit)
      content=$(printf '%s' "$input" | jq -r '.tool_input.new_string // empty')
      ;;
    MultiEdit)
      content=$(printf '%s' "$input" | jq -r '[.tool_input.edits[]? | .new_string] | join("\n")')
      ;;
    *) exit 0 ;;
  esac
else
  # tool_input がオブジェクトでない呼び出しは、中身を検査できないため止める (null は本文なしとして扱う)
  if ! printf '%s' "$input" | jq -e '.tool_input | type == "object" or type == "null"' >/dev/null 2>&1; then
    printf '%s の tool_input がオブジェクトではないため、本文を検査できません。\n' "$tool_name" >&2
    exit 2
  fi
  # fields[] に挙げた項目の文字列を、改行でつなぐ
  content=$(printf '%s' "$input" | jq -r --argjson f "$fields_json" \
    '(.tool_input // {}) as $t | [ $f[] | $t[.]? | strings ] | join("\n")')
  # requiredFields[] に挙げた引数が、ない・空白だけ・文字列でないときは止める
  missing=$(printf '%s' "$input" | jq -r --argjson r "$required_json" \
    '(.tool_input // {}) as $t
     | [ $r[] as $k | $t[$k]? as $v | select(($v | type) != "string" or (($v | gsub("\\s"; "")) | length) == 0) | $k ]
     | join(", ")')
  if [[ -n "$missing" ]]; then
    cat >&2 <<MSG
[送付文面の事前検査: 必須の項目なし]
${tool_name} の入力に、必須の項目 ${missing} がないか、空です。
本文は body (プレーンテキスト) で渡してください。htmlBody だけでは検査できません。
引数名が違うツールは、draftPrecheck.toolRules の requiredFields を、そのツールの引数名に合わせてください。
MSG
    exit 2
  fi
  file_path="$tool_name"
fi
[[ -z "$content" ]] && exit 0

# バイパス判定 (それだけの行にある場合のみ有効)
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
if [[ -n "$transcript" && -f "$transcript" ]]; then
  last_user_msg=$(harness_last_user_message "$transcript")
  if harness_has_token "$last_user_msg" '[hook-bypass: draft-precheck]'; then
    exit 0
  fi
fi

# ----- 検査 -----
hits=""
url_re='https?://'

# 1) 禁止語 (設定の bannedTerms[] のみ。誤検知の多い語は rules で人が判断する)
if check_on bannedTerms; then
  while IFS= read -r term; do
    [[ -z "$term" ]] && continue
    if grep -qF -- "$term" <<< "$content"; then
      matched=$(printf '%s' "$content" | grep -nF -- "$term" | head -3)
      hits="${hits}  - 禁止語「${term}」検出:"$'\n'"${matched}"$'\n'
    fi
  done < <(cfg_list '.draftPrecheck.bannedTerms[]?')
fi

# 2) 内部リポジトリパス断片 / 絶対パス
#    URL を含む行は対象外 (https://example.com/docs/setup を内部パスと読まない)
if check_on internalPaths; then
  internal_paths='(^|[^A-Za-z0-9])(docs|src|scripts|exports)/'
  abs_paths='(/home/|/tmp/|/var/)'
  matched=$(printf '%s' "$content" | grep -nE "$internal_paths" | grep -vE "$url_re" | head -3 || true)
  if [[ -n "$matched" ]]; then
    hits="${hits}  - 内部リポジトリパス検出:"$'\n'"${matched}"$'\n'
  fi
  matched=$(printf '%s' "$content" | grep -nE "$abs_paths" | grep -vE "$url_re" | head -3 || true)
  if [[ -n "$matched" ]]; then
    hits="${hits}  - 絶対パス検出:"$'\n'"${matched}"$'\n'
  fi
fi

# 3) ローカルファイル拡張子の素出し (.md / .ps1 / .drawio / .kql)
if check_on extensions; then
  local_ext='\.(md|ps1|drawio|kql)([[:space:]]|$|[、。)）」])'
  if grep -qE "$local_ext" <<< "$content"; then
    matched=$(printf '%s' "$content" | grep -nE "$local_ext" | head -3)
    hits="${hits}  - ローカルファイル拡張子検出:"$'\n'"${matched}"$'\n'
  fi
fi

# 4) 組版記号 § ¶ ‡ †
if check_on typography; then
  typo_marks='(§|¶|‡|†)'
  if grep -qE "$typo_marks" <<< "$content"; then
    matched=$(printf '%s' "$content" | grep -nE "$typo_marks" | head -3)
    hits="${hits}  - 組版記号検出:"$'\n'"${matched}"$'\n'
  fi
fi

# 5) 見出しでの敬称抜け - 見出し行のみ対象 (本文中の引用等は誤検知が多い)
if check_on honorific; then
  hon_name=$(cfg '.draftPrecheck.honorific.name' '')
  hon_suffix=$(cfg '.draftPrecheck.honorific.suffix' '様')
  if [[ -n "$hon_name" && -n "$hon_suffix" ]]; then
    hon_re="^#.*${hon_name}([^${hon_suffix}]|$)"
    if grep -qE -- "$hon_re" <<< "$content"; then
      matched=$(printf '%s' "$content" | grep -nE -- "$hon_re" | head -3)
      hits="${hits}  - 見出しに「${hon_name}${hon_suffix}」未付与の可能性:"$'\n'"${matched}"$'\n'
    fi
  fi
fi

# 6) 外部 AI ツール言及
if check_on externalAi; then
  external_ai='(Codex|ChatGPT|Gemini|Copilot)'
  if grep -qE "$external_ai" <<< "$content"; then
    matched=$(printf '%s' "$content" | grep -nE "$external_ai" | head -3)
    hits="${hits}  - 外部 AI ツール言及検出:"$'\n'"${matched}"$'\n'
  fi
fi

# 7) 長い識別子のフル表記の繰り返し (読み手の目が滑る文面の機械的緩和)
#    Write は content が保存後の全文になるため、同一識別子 3 回以上でブロックする。
#    Edit/MultiEdit は追加分のみが対象。
#    バッククォート内は数えない。
if check_on longIdentifiers; then
  ident_text=$(printf '%s' "$content" | sed 's/`[^`]*`//g')
  top_ident=$(printf '%s\n' "$ident_text" \
    | grep -oE '[A-Za-z][A-Za-z0-9_./-]{19,}' | sort | uniq -c | sort -rn | head -1 || true)
  top_count=$(printf '%s' "$top_ident" | awk '{print $1}')
  top_name=$(printf '%s' "$top_ident" | awk '{print $2}')
  if [[ -n "${top_count:-}" && ${top_count:-0} -ge 3 ]]; then
    hits="${hits}  - 長い識別子のフル表記の繰り返し: ${top_name} が ${top_count} 回 (初出のみフル表記し、以後は呼び名で書くか添付へ移す)"$'\n'
  fi
fi

if [[ -z "$hits" ]]; then
  exit 0
fi

cat >&2 <<MSG
[送付文面の事前検査違反]
${file_path} に以下を検出しました:
${hits}
修正してから再試行してください。
緊急時は [hook-bypass: draft-precheck] だけの行で回避できます。
詳細: rules「writing-style」
MSG
exit 2
