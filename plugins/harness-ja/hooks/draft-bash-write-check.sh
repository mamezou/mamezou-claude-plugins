#!/bin/bash
# 送付文面・原稿のファイルを Bash のコマンドで書き換える操作を止める hook (PreToolUse, matcher=Bash)
#
# draft-precheck.sh は Write / Edit / MultiEdit の内容を検査する。sed -i やスクリプトで書き換えると
# 検査を通らないため、対象のフォルダーのファイルの中身を Bash で書き換える操作を止め、Write か Edit へ戻す。
#
# 発火条件 (すべて満たすとき):
#   - draftPrecheck.checks.bashWrites が true (既定は false。書いていないプロジェクトでは何もしない)
#   - コマンドに draftPrecheck.bashWriteDirs[] のどれか (パスの一部の文字列) がある
#   - コマンドが次のどれかの形 (判定の形は harness-change-check.sh の Bash の判定を元にした。違いは下に書く):
#       - リダイレクト (> / >>) の先が対象のフォルダー
#       - sed -i / sed --in-place / perl -i / tee / truncate の引数に対象のフォルダー
#         (-i は、ほかの引数の後でも見る。tee と truncate は、入力のリダイレクト < の先を見ない)
#       - cp / mv / rsync / install / ln の最後の引数 (コピー先・移動先。後ろにオプションだけが続く形を含む) か、
#         -t / --target-directory の値が対象のフォルダー
#       - git apply / git mv の引数に対象のフォルダー (git mv は最後の引数)
#       - python / node / perl / ruby / php の実行の後ろに、書き込みの呼び出し
#         (open(…,'w' / 'a' / 'x') / write_text / writelines / .write( / writeFile / File.write) があり、
#         コマンドに対象のフォルダーがある
#     コマンドは、実行ファイルのパス付き (/bin/sed) でも見る
#
# harness-change-check.sh との違い:
#   - rm / rmdir / touch / chmod / chown は止めない (中身を書き込まない)
#   - mv は移動先だけを見る (対象のフォルダーから外へ出す移動は止めない)
#   - git の操作は、git apply と git mv のほかは止めない (checkout / restore / stash / reset / clean / merge など)。
#     git restore --source=<ほかのコミット> や git stash pop は、検査を通っていない中身を入れられるが、対象外とする
#   - スクリプトの実行は、書き込みの呼び出しがあるときだけ止める (読むだけの集計は通す)
#
# 限界 (コマンドを解析せず、文字列の形で判定する):
#   - 対象のフォルダーの文字列を書かずに触れる形 (cd の後の相対パス、変数の展開、スクリプトの
#     ファイルの中での書き込み、パッチの中にだけパスがある git apply) は止まらない
#   - ここに挙げていないコマンド (dd、patch、エディターの一括の置き換えなど) と、挙げていない書き込みの
#     呼び出しは止まらない
#   - heredoc やコミットメッセージの本文に、対象のフォルダーの文字列と sed -i などの文字が並ぶと、
#     書き換えでなくても止まる。スクリプトの実行と書き込みの呼び出しは、同じコマンドの中かを見ないため、
#     読むだけのスクリプトの後ろに書き込みの呼び出しの文字があると止まる
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

# 設定の型が誤っているときは、対象のフォルダーが空として通さずに止める
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/doc-text.sh"
cfg_errs=$(harness_doc_config_errors bashWrites)
if [[ -n "$cfg_errs" ]]; then
  printf '[送付文面の書き換えの停止: 設定の誤り]\nharness.json の draftPrecheck の設定を読めないため、判定できません:\n%s\n設定を直してから再試行してください。\n' "$cfg_errs" >&2
  exit 2
fi

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

# コマンドの前に置ける字と、実行ファイルのパス (/bin/sed など)
P="(^|[[:space:]|;&(])([^[:space:]|;&(]*/)?"
redirect_re=">>?[[:space:]]*[\"']?[^[:space:]\"'|;&]*$D"
# sed と perl の -i は、ほかの引数の後にあっても見る (sed -e … -i)。tee と truncate は、入力のリダイレクト (<) の先を見ない
anyarg_re="${P}(sed[[:space:]]+([^|;&]*[[:space:]])?(-[a-zA-Z]*i|--in-place)[^|;&]*|perl[[:space:]]+([^|;&]*[[:space:]])?-[a-zA-Z]*i[^|;&]*|(tee|truncate)[[:space:]][^|;&<]*|git[[:space:]]+apply[[:space:]][^|;&]*)$D"
# コピー先・移動先: 最後の引数 (後ろにオプションだけが続く形を含む) か、-t / --target-directory の値
dest_re="${P}((cp|mv|rsync|install|ln)|git[[:space:]]+mv)[[:space:]]([^|;&]*[^[:space:]|;&]*$D[^[:space:]|;&]*([[:space:]]+--?[a-zA-Z][^[:space:]|;&]*)*[[:space:]]*(\$|[|;&)])|([^|;&]*[[:space:]])?(-t[[:space:]]*|--target-directory[=[:space:]])[\"']?[^[:space:]|;&]*$D)"
interp_re="${P}(python[0-9.]*|node|perl|ruby|php)[[:space:]]"
# open は、第 2 引数のモードに w / a / x / + があるとき (open('work.md') のような読み取りは当てない)
write_call_re="open\([^)]*,[[:space:]]*['\"][rbt]*[wax+]|write_text|writelines|\.write\(|writeFile|File\.write"

why=""
if grep -qE -- "$redirect_re" <<< "$flat"; then why="リダイレクト"
elif grep -qE -- "$anyarg_re" <<< "$flat"; then why="sed -i・perl -i・tee・truncate・git apply"
elif grep -qE -- "$dest_re" <<< "$flat"; then why="cp・mv などのコピー先・移動先"
elif grep -qE -- "${interp_re}.*(${write_call_re})" <<< "$flat"; then why="スクリプトでの書き込み"
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
