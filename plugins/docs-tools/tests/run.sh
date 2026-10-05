#!/bin/bash
# docs-tools の同梱スクリプト precheck.sh の検査。
# tests/fixtures/precheck-sample.md を precheck.sh に通し、節ごとの出力を期待値と比べる。
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

echo
echo "PASS ${pass} / FAIL ${fail}"
if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
exit 0
