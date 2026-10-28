#!/bin/bash
# docs-tools の同梱スクリプトの検査。
# tests/fixtures/precheck-sample.md を precheck.sh に通し、節ごとの出力を期待値と比べる。
# tests/fixtures/transcripts/ の会話の記録を一時ディレクトリへ写し、session-recall.sh と
# code-origin.sh の出力を期待値と比べる。
# 末尾に PASS / FAIL 件数を出し、FAIL が 1 件でもあれば exit 1。
#
# 使い方: bash tests/run.sh   (リポジトリ内のどのディレクトリからでも実行できる)

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
PRECHECK="$ROOT/skills/draft-precheck/scripts/precheck.sh"
SAMPLE="$SCRIPT_DIR/fixtures/precheck-sample.md"

for f in "$PRECHECK" "$SAMPLE"; do
  if [[ ! -f "$f" ]]; then
    echo "ファイルが見つかりません: $f" >&2
    exit 1
  fi
done

pass=0
fail=0

if ! out=$(bash "$PRECHECK" "$SAMPLE"); then
  echo "precheck.sh が失敗しました: $SAMPLE" >&2
  exit 1
fi

# 見出し [名前] の次の行から、次の見出しの前までを返す
section_of() {
  awk -v name="[$1]" '$0 == name { on = 1; next } /^\[/ { on = 0 } on' <<< "$out"
}

# check <説明> <has|not> <節の名前> <固定文字列>
# 節の見出しが出力にないときは、has でも not でも FAIL にする
check() {
  local desc="$1" want="$2" body got=not
  if ! grep -qxF -- "[$3]" <<< "$out"; then
    fail=$((fail + 1))
    echo "FAIL $desc (節「$3」が出力にない)"
    return
  fi
  body=$(section_of "$3")
  if grep -qF -- "$4" <<< "$body"; then
    got=has
  fi
  if [[ "$got" == "$want" ]]; then
    pass=$((pass + 1))
    echo "PASS $desc"
  else
    fail=$((fail + 1))
    echo "FAIL $desc (節「$3」に「$4」が$([[ "$got" == has ]] && echo ある || echo ない))"
  fi
}

PAREN="同じ括弧の中身が3回以上 (回数 中身)"
COMMA="読点が2つ以上の文 (括弧の中の読点は数えない)"

check "PA-1 3回出る括弧を回数つきで出す (表のセルの1回を含む)" has "$PAREN" "3 受付窓口"
check "PA-2 2回の括弧は出さない" not "$PAREN" "施設担当"
check "PA-3 1回の括弧は出さない" not "$PAREN" "投影機"
check "PA-4 全角と半角の括弧を同じものとして数える" has "$PAREN" "3 支払担当"

check "CM-1 読点3つの文を出す" has "$COMMA" "5:読点3: 申請者は、利用日の3日前までに"
check "CM-2 括弧の中の読点を数えない (外が2つ)" has "$COMMA" "7:読点2: 会議室には、"
check "CM-3 括弧の外の読点が1つの文は出さない" not "$COMMA" "型番A"
check "CM-4 読点のない文は出さない" not "$COMMA" "前日までに予約を確定する"
check "CM-5 「。」で終わらない箇条書きの項目は出さない" not "$COMMA" "筆記用具"
check "CM-6 表の行は出さない" not "$COMMA" "応接室"
check "CM-7 コードブロックの中は出さない" not "$COMMA" "コードブロック"

# 空のファイルでも正常に終わる
empty=$(mktemp)
if bash "$PRECHECK" "$empty" > /dev/null; then
  pass=$((pass + 1))
  echo "PASS EX-1 空のファイルで正常に終わる"
else
  fail=$((fail + 1))
  echo "FAIL EX-1 空のファイルで正常に終わる"
fi
rm -f "$empty"

# ---- session-recall.sh と code-origin.sh ----
# 会話の記録の置き場を一時ディレクトリに作り、CLAUDE_CONFIG_DIR で指す。記録の中の @HOME@ は
# 置き場のパスに、@NOW@ は今の時刻に置き換える
RECALL="$ROOT/skills/session-recall/scripts/session-recall.sh"
ORIGIN="$ROOT/skills/draft-precheck/scripts/code-origin.sh"
FIX="$SCRIPT_DIR/fixtures/transcripts"
for f in "$RECALL" "$ORIGIN" "$FIX/projects/-work-proj-a/sess-a1.jsonl"; do
  if [[ ! -f "$f" ]]; then
    echo "ファイルが見つかりません: $f" >&2
    exit 1
  fi
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
home="$work/claude"
mkdir -p "$home"
cp -R "$FIX/projects" "$home/"
now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
find "$home" -name '*.jsonl' -exec sed -i -e "s|@HOME@|$home|g" -e "s|@NOW@|$now|g" {} +
transcript="$home/projects/-work-proj-a/sess-a1.jsonl"

# expect <説明> <has|not> <固定文字列> <出力>
expect() {
  local desc="$1" want="$2" got=not
  if grep -qF -- "$3" <<< "$4"; then
    got=has
  fi
  if [[ "$got" == "$want" ]]; then
    pass=$((pass + 1))
    echo "PASS $desc"
  else
    fail=$((fail + 1))
    echo "FAIL $desc (「$3」が$([[ "$got" == has ]] && echo ある || echo ない))"
  fi
}

# expect_rc <説明> <期待する終了コード> <実際の終了コード>
expect_rc() {
  if [[ "$2" == "$3" ]]; then
    pass=$((pass + 1))
    echo "PASS $1"
  else
    fail=$((fail + 1))
    echo "FAIL $1 (終了コード $3。期待は $2)"
  fi
}

recall() {
  CLAUDE_CONFIG_DIR="$home" bash "$RECALL" --project /work/proj-a "$@" 2>&1
}
NOHIT="一致する記録はありません"

out=$(recall MARKER-USER)
expect "RC-1 依頼者の入力を出す" has "依頼者の入力" "$out"
expect "RC-2 ほかの案件の置き場の記録を読まない" not "proj-b-ng" "$out"

out=$(recall MARKER-SHARED)
expect "RC-3 cwd が案件の下の行を出す" has "proj-a-ok" "$out"
expect "RC-4 cwd が案件のサブディレクトリの行を出す" has "proj-a-sub-ok" "$out"
expect "RC-5 cwd が名前の前方だけ同じディレクトリの行を出さない" not "proj-ab-ng" "$out"
expect "RC-6 cwd が案件の外の行を出さない" not "other-ng" "$out"
expect "RC-7 新しい順に出す" has "proj-a-sub-ok" "$(awk '/^\[1\]/ { on = 1 } /^\[2\]/ { on = 0 } on' <<< "$out")"

out=$(recall MARKER-ARRAY)
expect "RC-8 配列形式のツールの結果を読む" has "ツールの結果 (Read)" "$out"
expect "RC-9 配列形式のツールの結果の本文を出す" has "total_errors = 42" "$out"

out=$(recall MARKER-SAVED)
expect "RC-10 Full output saved to の別ファイルを読む" has "saved-body-line" "$out"
expect "RC-11 別ファイルの保存先を出す" has "全文の保存先:" "$out"
expect "RC-12 置き場の外を指す別ファイルを読まない" has "$NOHIT" "$(recall MARKER-OUTSIDE)"

out=$(recall MARKER-SECRET)
expect "RC-13 名前で分かる値を伏せ字にする" has "password=***" "$out"
for secret in Hunter2pass abcdefghijklmnop123 AKIAABCDEFGHIJKLMNOP S3cretPw 'abc123def==' MIIEpkeymaterial; do
  expect "RC-14 秘匿値を出さない ($secret)" not "$secret" "$out"
done

out=$(recall MARKER-SUB)
expect "RC-15 サブエージェントの記録を読む" has "のサブエージェント sub1" "$out"
expect "RC-16 サブエージェントへの依頼文を依頼者の入力にしない" has "$NOHIT" "$(recall MARKER-PROMPT)"

out=$(recall MARKER-FOLLOW)
expect "RC-17 Claude の応答の直後の依頼者の入力を出す" has "result-row-77" "$out"

expect "RC-18 --kind で種類を絞る" has "$NOHIT" "$(recall --kind assistant MARKER-USER)"
for word in MARKER-META MARKER-LOCAL MARKER-THINK MARKER-BLOB MARKER-REMINDER; do
  expect "RC-19 依頼者の入力・応答・ツールでない記録を出さない ($word)" has "$NOHIT" "$(recall "$word")"
done
expect "RC-20 origin のない古い形式の入力を依頼者の入力として出す" has "依頼者の入力" "$(recall MARKER-OLD)"
expect "RC-21 --days で日数を絞る" has "一致: 1 件" "$(recall --days 1 MARKER)"

CLAUDE_CONFIG_DIR="$home" bash "$RECALL" --project /work/proj-a > /dev/null 2>&1
expect_rc "RC-22 語がないときは 2 で終わる" 2 $?

draft="$work/slack-test-restart-20261020.txt"
cp "$FIX/slack-test-restart-20261020.txt" "$draft"
origin() {
  CLAUDE_CONFIG_DIR="$home" bash "$ORIGIN" "$@" 2>&1
}
out=$(origin "$draft" "$transcript")
# 文面の <行番号> の行の判定 (次の行番号の行・見出し・空行の前まで)
origin_of() {
  awk -v head="$1: " 'index($0, head) == 1 { on = 1; next } /^[0-9]+: |^\[|^$/ { on = 0 } on' <<< "$out"
}
expect "CO-1 依頼者の入力に出た行" has "依頼者の入力" "$(origin_of 6)"
expect "CO-2 成功したコマンドに出た行" has "成功したコマンド Bash" "$(origin_of 7)"
expect "CO-3 配列形式のツールの結果に出た行" has "ツールの結果 Read" "$(origin_of 8)"
expect "CO-4 失敗したコマンドにだけ出た行" has "失敗したコマンドかエラーの結果にはある" "$(origin_of 9)"
expect "CO-5 Claude の応答にだけ出た行" has "Claude の応答" "$(origin_of 10)"
expect "CO-6 どこにも出ていない行" has "どこにも出ていない" "$(origin_of 11)"
expect "CO-7 文面への書き込みは数えない" has "どこにも出ていない" "$(origin_of 12)"
expect "CO-8 文面を作り始めた後の記録に印を付ける" has "文面を作り始めた後" "$(origin_of 13)"
expect "CO-9 文面を作る前の記録には印を付けない" not "文面を作り始めた後" "$(origin_of 6)"
expect "CO-10 短い行は判定しない" has "短い行のため判定しない" "$(origin_of 14)"
expect "CO-11 どこにも出ていない行の一覧" has "どこにも出ていない行: 11, 12" "$out"
expect "CO-12 失敗したコマンドにだけ出ている行の一覧" has "失敗したコマンドかエラーの結果にだけ出ている行: 9" "$out"
expect "CO-13 Claude の応答にだけ出ている行の一覧" has "Claude の応答にだけ出ている行: 10" "$out"

origin "$work/missing.txt" > /dev/null
expect_rc "CO-14 下書きがなくても 0 で終わる" 0 $?
printf 'コードのない文面です。\n' > "$work/plain.txt"
expect "CO-15 コードブロックのない文面" has "コードブロックはありません" "$(origin "$work/plain.txt" "$transcript")"

# 会話の記録を省くと、今のディレクトリの置き場で最後に書かれた記録を使う
proj="$work/work/proj-c"
mkdir -p "$proj"
store="$home/projects/$(sed 's/[^A-Za-z0-9]/-/g' <<< "$proj")"
mkdir -p "$store"
cp "$transcript" "$store/sess-c1.jsonl"
expect "CO-16 記録を省くと今のディレクトリの最新の記録を使う" has "$store/sess-c1.jsonl" "$(cd "$proj" && origin "$draft")"

echo
echo "PASS ${pass} / FAIL ${fail}"
if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
exit 0
