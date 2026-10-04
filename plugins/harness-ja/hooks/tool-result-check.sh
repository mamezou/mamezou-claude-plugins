#!/bin/bash
# ツールの結果に、作成・更新が成立した印があるかを確かめる hook
# (PostToolUse, matcher=mcp__.*)
#
# ツールが成功の文言を返しても、作成・更新が成立していない場合がある (例: 同じ宛先に
# 下書きが既にあり、新しい下書きが作られない)。成立の印 (採番された ID 等) が結果に
# 無いときに、成立していないことを Claude へ知らせる。ツールは実行済みのため、実行は
# 止めない (exit 2 の stderr が、ツールの結果と並んで Claude へ渡る)。
#
# 発火条件:
#   - ツール名が toolResultCheck.rules[] の tool (正規表現) に一致
#     配列順に照合し、最初に一致した要素を使う (successPattern の無い要素は飛ばす)
#   - ツールの結果 (tool_response) が successPattern (正規表現) に一致しない
#     照合の対象は、結果全体を JSON の文字列にしたものと、結果の中の文字列の値。
#     結果が、JSON を本文に持つテキストでも、オブジェクトでも、同じ式で照合できる
#
# 設定 (.claude/harness.json):
#   toolResultCheck.enabled  false で無効化
#   toolResultCheck.rules[]  tool / successPattern / hint
#   設定ファイルが無い、または rules が空なら何もしない

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/config.sh"

input=$(cat)
harness_load_config "$input"
harness_config_guard stop

if ! cfg_enabled '.toolResultCheck'; then
  exit 0
fi

tool_name=$(printf '%s' "$input" | jq -r '.tool_name // empty')
if [[ -z "$tool_name" ]]; then
  exit 0
fi

success_re=""
hint=""
while IFS= read -r rule; do
  [[ -z "$rule" ]] && continue
  pat=$(printf '%s' "$rule" | jq -r '.tool // empty')
  [[ -z "$pat" ]] && continue
  jq -en --arg n "$tool_name" --arg re "$pat" '$n | test($re)' >/dev/null 2>&1 || continue
  # successPattern の無い規則は使わず、次の規則を見る
  success_re=$(printf '%s' "$rule" | jq -r '.successPattern // empty')
  [[ -z "$success_re" ]] && continue
  hint=$(printf '%s' "$rule" | jq -r '.hint // empty')
  break
done < <(cfg_list '.toolResultCheck.rules[]? | @json')

if [[ -z "$success_re" ]]; then
  exit 0
fi
[[ -n "$hint" ]] || hint="成立の印"

# 終了コード 0: 一致した / 1: 一致しない / その他: 式の誤り等 (知らせずに通す)
rc=0
printf '%s' "$input" | jq -e --arg re "$success_re" '
  (.tool_response // null) as $r
  | ([$r | tojson] + [$r | .. | strings]) | any(.[]; test($re))' >/dev/null 2>&1 || rc=$?
if [[ "$rc" -ne 1 ]]; then
  exit 0
fi

cat >&2 <<MSG
[ツールの結果に成立の印がない]
${tool_name} の結果に ${hint} がありません (照合した式: ${success_re})。

作成・更新は成立していないものとして扱ってください。
- 応答に、作成した・更新したと書かない
- 成立していないことと、結果の原文を応答に書く
MSG
exit 2
