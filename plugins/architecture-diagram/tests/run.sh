#!/bin/bash
# architecture-diagram の同梱スクリプト export-png.sh の検査。
# uname・drawio・xvfb-run・fc-match・ffprobe・ffmpeg を一時ディレクトリのスタブで置き換え、
# OS と DISPLAY の組み合わせごとに、drawio を直接呼ぶか xvfb-run 経由で呼ぶかを確かめる。
# Draw.io Desktop・フォント・ffmpeg がない環境でも動く。python3 は本物が必要 (export-png.sh が XML の検査に使う)。
# 末尾に PASS / FAIL 件数を出し、FAIL が 1 件でもあれば exit 1。
#
# 使い方: bash tests/run.sh   (リポジトリ内のどのディレクトリからでも実行できる)

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
EXPORT="$ROOT/scripts/export-png.sh"
SAMPLE="$ROOT/assets/template-aws.drawio"

for f in "$EXPORT" "$SAMPLE"; do
  if [[ ! -f "$f" ]]; then
    echo "ファイルが見つかりません: $f" >&2
    exit 1
  fi
done

# スタブは export-png.sh の既定値 (IPAPGothic、1400x900) に合わせてある。利用者が設定した値で結果が変わらないようにする
unset DIAGRAM_FONT PAGE_WIDTH PAGE_HEIGHT LEFT_MARGIN TOP_MARGIN

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin"

# drawio と xvfb-run: 呼ばれた形を記録し、--output の次の引数のファイルを作る
for name in drawio xvfb-run; do
  cat > "$W/bin/$name" <<'STUB'
#!/bin/bash
echo "$(basename "$0") $*" >> "$STUB_LOG"
while [ "$#" -gt 0 ]; do
  if [ "$1" = --output ]; then : > "$2"; fi
  shift
done
STUB
done
cat > "$W/bin/uname" <<'STUB'
#!/bin/bash
echo "$FAKE_UNAME"
STUB
cat > "$W/bin/fc-match" <<'STUB'
#!/bin/bash
echo IPAPGothic
STUB
# 書き出し結果がページ寸法ちょうどなら ffmpeg は呼ばれない
cat > "$W/bin/ffprobe" <<'STUB'
#!/bin/bash
echo 1400x900
STUB
cat > "$W/bin/ffmpeg" <<'STUB'
#!/bin/bash
exit 1
STUB
chmod +x "$W/bin/"*

pass=0
fail=0

# check <説明> <uname の出力> <DISPLAY の値> <呼ばれるはずのコマンド名>
check() {
  local desc="$1" log="$W/log" first
  : > "$log"
  if ! PATH="$W/bin:$PATH" STUB_LOG="$log" FAKE_UNAME="$2" DISPLAY="$3" \
      bash "$EXPORT" "$SAMPLE" "$W/out.png" > /dev/null 2>"$W/err"; then
    fail=$((fail + 1))
    echo "FAIL $desc (export-png.sh が失敗: $(head -1 "$W/err"))"
    return
  fi
  first=$(head -1 "$log" | cut -d' ' -f1)
  if [[ "$first" == "$4" ]]; then
    pass=$((pass + 1))
    echo "PASS $desc"
  else
    fail=$((fail + 1))
    echo "FAIL $desc (呼ばれたのは ${first:-なし}、期待は $4)"
  fi
}

check "EX-1 macOS は DISPLAY がなくても drawio を直接呼ぶ" Darwin "" drawio
check "EX-2 Linux で DISPLAY がなければ xvfb-run 経由で呼ぶ" Linux "" xvfb-run
check "EX-3 Linux で DISPLAY があれば drawio を直接呼ぶ" Linux ":0" drawio
check "EX-4 Windows (Git Bash) は DISPLAY がなくても drawio を直接呼ぶ" MINGW64_NT-10.0-19045 "" drawio

echo
echo "PASS ${pass} / FAIL ${fail}"
if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
exit 0
