#!/bin/bash
# 送付文面・原稿のファイルを Bash のコマンドで書き換える操作を止める hook (PreToolUse, matcher=Bash)
#
# draft-precheck.sh は Write / Edit / MultiEdit の内容を検査する。sed -i やスクリプトで書き換えると
# 検査を通らないため、対象のフォルダーへの書き込みを Bash で行う操作を止め、Write か Edit へ戻す。
#
# 発火条件 (すべて満たすとき):
#   - draftPrecheck.checks.bashWrites が true (既定は false。書いていないプロジェクトでは何もしない)
#   - コマンドに draftPrecheck.bashWriteDirs[] のどれか (パスの一部の文字列) がある
#   - コマンドが次のどれかの形: sed / perl / ruby の -i で対象のパスを上書きする、対象のパスへの
#     リダイレクト・tee、対象のパスを含むスクリプト (python / node / ruby / perl) での書き込み、
#     対象のパスを写し先にする cp / mv / install
#
# 通過するもの: 読み取り (grep / cat / git diff など)、git の操作 (add / mv / commit / checkout / restore)
#
# バイパス: 依頼者の最後のテキスト入力に [hook-bypass: draft-precheck] がそれだけの行としてある
#
# 設定 (.claude/harness.json):
#   draftPrecheck.enabled            false で無効化
#   draftPrecheck.checks.bashWrites  true で有効化 (既定 false)
#   draftPrecheck.bashWriteDirs[]    対象のフォルダー (パスの一部の文字列。空なら何もしない)
#   設定ファイルが無ければ何もしない。設定ファイルが JSON として読めなければ止める

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/config.sh"

input=$(cat)
harness_load_config "$input"
harness_config_guard pre

cfg_enabled '.draftPrecheck' || exit 0
cfg_flag '.draftPrecheck.checks.bashWrites' 'false' || exit 0

[[ "$(printf '%s' "$input" | jq -r '.tool_name // empty')" == "Bash" ]] || exit 0
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
[[ -n "$cmd" ]] || exit 0

# 対象のフォルダーを、正規表現の選択肢にまとめる (記号はエスケープする)
dirs=""
while IFS= read -r d; do
  [[ -z "$d" ]] && continue
  esc=$(printf '%s' "$d" | sed -E 's/[][\.^$*+?(){}|/]/\\&/g')
  dirs="${dirs:+$dirs|}$esc"
done < <(cfg_list '.draftPrecheck.bashWriteDirs[]?')
[[ -n "$dirs" ]] || exit 0
dirs="($dirs)"

printf '%s' "$cmd" | grep -qE -- "$dirs" || exit 0

why=""
if printf '%s' "$cmd" | grep -qE -- "(^|[^a-zA-Z])(sed|perl|ruby)[[:space:]][^|;&]*-[a-zA-Z]*i[^|;&]*$dirs"; then
  why="sed・perl の -i"
fi
if printf '%s' "$cmd" | grep -qE -- "(>>?|tee( -a)?)[[:space:]]*[\"']?[^[:space:]|;&]*$dirs"; then
  why="リダイレクト・tee"
fi
if printf '%s' "$cmd" | grep -qE -- '(python3?|node|ruby|perl)' \
   && printf '%s' "$cmd" | grep -qE -- "open\([^)]*['\"][wa]|write_text|writelines|\.write\(|writeFile|File\.write"; then
  why="スクリプトでの書き込み"
fi
if printf '%s' "$cmd" | grep -qE -- "(^|[;&|][[:space:]]*)(cp|mv|install)[[:space:]][^;&|]*$dirs[^;&|[:space:]]*[\"']?[[:space:]]*($|[;&|])"; then
  why="cp・mv での上書き"
fi
[[ -n "$why" ]] || exit 0

transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
if [[ -n "$transcript" && -f "$transcript" ]]; then
  last_user_msg=$(harness_last_user_message "$transcript")
  if harness_has_token "$last_user_msg" '[hook-bypass: draft-precheck]'; then
    exit 0
  fi
fi

cat >&2 <<MSG
[送付文面の書き換えの停止]
送付文面・原稿のファイルを Bash のコマンド (${why}) で書き換えようとしています。
Write か Edit で編集してください。Write と Edit は、送付文面の事前検査 (draft-precheck) を通ります。
緊急時は [hook-bypass: draft-precheck] だけの行で回避できます。
MSG
exit 2
