#!/bin/bash
# 送付前 grep チェック。/docs-tools:draft-precheck から呼ばれる。
# 使い方: precheck.sh <チェック対象ファイル>
# 各項目の出現行を印字する。判定(残す / 直す)は Skill 本文の基準で行う。

set -uo pipefail
export LC_ALL=C.UTF-8

f="${1:-}"
if [[ -z "$f" || ! -f "$f" ]]; then
  echo "対象ファイルが見つかりません: ${f:-(未指定)}" >&2
  exit 1
fi

section() { printf '\n[%s]\n' "$1"; }
none() { echo "  なし"; }

section "内部パス断片"
grep -nE '(^|[^A-Za-z0-9])(docs|src|scripts|exports)/' "$f" || none
section "絶対パス"
grep -nE '(/home/|/tmp/|/var/)' "$f" || none
section "ローカル拡張子の素出し"
grep -nE '\.(md|ps1|drawio|kql)([[:space:]]|$|[、。)）」])' "$f" || none
section "文脈依存度の高い英単語 (要文脈確認)"
grep -nE '(レイヤー|パイプライン|フェーズ|ターゲット)' "$f" || none
section "組版記号 § ¶ ‡ †"
grep -nE '(§|¶|‡|†)' "$f" || none
section "外部 AI 言及"
grep -nE '(Codex|ChatGPT|Gemini|Copilot)' "$f" || none
section "指示語の出現行"
grep -nE '(これ|それ|その|この|こうした)' "$f" || none
section "括弧の中身"
grep -noE '[（(][^（()）]{2,}[）)]' "$f" || none
section "3回以上の長い識別子"
grep -oE '[A-Za-z][A-Za-z0-9_./-]{19,}' "$f" | sort | uniq -c | sort -rn | grep -E '^ *([3-9]|[1-9][0-9]+) ' || none
section "60字超の文"
sed 's/。/。\n/g' "$f" | grep -nE '^.{61,}' || none
section "未確認の印"
grep -nE '(未確認|要確認|TBD|未定|要判断)' "$f" || none
section "バイト数"
wc -c < "$f"
