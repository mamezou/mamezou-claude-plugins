#!/bin/bash
# 送付文面・原稿のファイルを Bash のコマンドで書き換える操作を止める hook (PreToolUse, matcher=Bash)
#
# draft-precheck.sh は Write / Edit / MultiEdit の内容を検査する。sed -i やスクリプトで書き換えると
# 検査を通らないため、対象のフォルダーのファイルの中身を Bash で書き換える操作を止め、Write か Edit へ戻す。
#
# 発火条件 (すべて満たすとき):
#   - draftPrecheck.checks.bashWrites が true (既定は false。書いていないプロジェクトでは何もしない)
#   - コマンドに draftPrecheck.bashWriteDirs[] のどれか (パスの一部の文字列) がある
#   - コマンドが次のどれかの形 (判定の形は harness-change-check.sh の Bash の判定と同じ。違いは下に書く):
#       - リダイレクト (> / >>) の先が対象のフォルダー
#       - sed -i / sed --in-place / perl -i / tee / truncate の引数に対象のフォルダー
#       - cp / mv / rsync / install / ln の最後の引数 (コピー先・移動先) が対象のフォルダー
#       - git apply / git mv の引数に対象のフォルダー (git mv は最後の引数)
#       - python / node / perl / ruby / php の実行と、対象のフォルダーと、書き込みの呼び出し
#         (open(…,'w') / write_text / writelines / .write( / writeFile / File.write) の同居
#
# harness-change-check.sh との違い (止めるのは、検査を通っていない中身が入る操作に限る):
#   - rm / rmdir / touch / chmod / chown は止めない (中身を書き込まない)
#   - mv は移動先だけを見る (対象のフォルダーから外へ出す移動は止めない)
#   - git checkout / restore / stash / reset / clean は止めない (コミット済みの中身へ戻す操作)
#   - スクリプトの実行は、書き込みの呼び出しがあるときだけ止める (読むだけの集計は通す)
#
# 限界 (文字列の形で判定する):
#   - 対象のフォルダーの文字列を書かずに触れる形 (cd の後の相対パス、変数の展開、スクリプトの
#     ファイルの中での書き込み) は止まらない
#   - heredoc やコミットメッセージの本文に、対象のフォルダーの文字列と sed -i などの文字が並ぶと、
#     書き換えでなくても止まる
#
# バイパス: 依頼者の最後のテキスト入力に [hook-bypass: draft-precheck] がそれだけの行としてある
#   (ファイルの移動・名前の変更・一括の置き換えが要るときに使う)
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
command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
[[ -n "$command" ]] || exit 0

# 対象のフォルダーを、正規表現の選択肢にまとめる (記号はエスケープする)
dirs=""
while IFS= read -r d; do
  [[ -z "$d" ]] && continue
  esc=$(printf '%s' "$d" | sed -E 's/[][\.^$*+?(){}|]/\\&/g')
  dirs="${dirs:+$dirs|}$esc"
done < <(cfg_list '.draftPrecheck.bashWriteDirs[]? | strings')
[[ -n "$dirs" ]] || exit 0
D="($dirs)"

# heredoc 内も含めて全行を見る
flat=$(printf '%s' "$command" | tr '\n' ' ')
grep -qE -- "$D" <<< "$flat" || exit 0

redirect_re=">>?[[:space:]]*[\"']?[^[:space:]\"'|;&]*$D"
anyarg_re="(^|[[:space:]|;&(])(sed[[:space:]]+(-[a-zA-Z]*i|--in-place)[^|;&]*|perl[[:space:]]+-[a-zA-Z]*i[^|;&]*|(tee|truncate)[[:space:]][^|;&]*|git[[:space:]]+apply[[:space:]][^|;&]*)$D"
dest_re="(^|[[:space:]|;&(])((cp|mv|rsync|install|ln)|git[[:space:]]+mv)[[:space:]][^|;&]*[^[:space:]|;&]*$D[^[:space:]|;&]*[[:space:]]*(\$|[|;&)])"
interp_re="(^|[[:space:]|;&(])(python[0-9.]*|node|perl|ruby|php)[[:space:]]"
write_call_re="open\([^)]*['\"][wa]|write_text|writelines|\.write\(|writeFile|File\.write"

why=""
if grep -qE -- "$redirect_re" <<< "$flat"; then why="リダイレクト"
elif grep -qE -- "$anyarg_re" <<< "$flat"; then why="sed -i・perl -i・tee・truncate・git apply"
elif grep -qE -- "$dest_re" <<< "$flat"; then why="cp・mv などのコピー先・移動先"
elif grep -qE -- "$interp_re" <<< "$flat" && grep -qE -- "$write_call_re" <<< "$flat"; then why="スクリプトでの書き込み"
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
中身の変更は Write か Edit で行ってください。Write と Edit は、送付文面の事前検査 (draft-precheck) を通ります。
ファイルの移動・名前の変更・一括の置き換えが要るときは、依頼者の [hook-bypass: draft-precheck] だけの行で通ります。
MSG
exit 2
