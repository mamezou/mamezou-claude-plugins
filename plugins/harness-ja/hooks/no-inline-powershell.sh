#!/bin/bash
# PowerShell スクリプトをテキストでインライン提示するのを Stop 時に検知してブロックする
# (ファイル化して渡す運用の機械的強制)
#
# 既定は無効。使う場合は .claude/harness.json で明示的に有効化する
# ("noInlinePowershell": { "enabled": true })。
#
# 検知条件:
#   - 直近の assistant ターン text に ```powershell または ```ps1 の 5 行以上の block がある
#   - かつ、直近 100 行の assistant tool_use 内に Write(*.ps1) が無い
# 上記を満たしたら exit 2 + メッセージ → 応答を作り直させる
#
# 貼り付けて実行する形の検査 (noInlinePowershell.pasteRun。既定は無効):
#   ファイルを置けない環境 (AVD 等) で、スクリプトの中身を PowerShell の画面に貼り付けて
#   実行する運用の機械的強制。cwdMatch によらず行う。
#   - 応答の本文: 「-ExecutionPolicy <値> -File」を書いていたら止める。行頭が「>」の引用行と、
#     バッククォートで囲んだ箇所 (変更前の文の引用など) は見ない
#   - リポジトリの中で HEAD から変わったファイルと、追跡していないファイルのうち、
#     依頼者の最後の入力より後に更新したもの (入力の時刻が取れなければ全部):
#       scriptGlobs に当たる .ps1: コメントと空行を除いた最初の行が「& {」、最後の行が「}」で
#         あること。「param(」、「-ExecutionPolicy <値> -File」、ブロックの中の空行がないこと
#       docGlobs に当たる文書: 「-ExecutionPolicy <値> -File」がないこと
#   - ファイルの検査は、差し戻し後の再生成 (stop_hook_active=true) では行わない
#     (依頼者が直すファイルで止まり続けないため)
#
# transcript の行は jq で読む。grep の文字列一致 ('"type":"assistant"') では、空白入りの
# JSON ('"type": "assistant"') を認識できず検査が空振りする。
#
# 設定 (.claude/harness.json):
#   noInlinePowershell.enabled              true で有効化 (既定は無効)
#   noInlinePowershell.cwdMatch             指定すると、cwd がそのディレクトリ名をパス区切り単位で
#                                           含むときだけインライン提示を検査する (空なら常に検査)
#   noInlinePowershell.scriptDirHint        ファイル化先の案内 (既定 scripts/*.ps1)
#   noInlinePowershell.pasteRun.enabled     true で貼り付けて実行する形の検査を有効化 (既定は無効)
#   noInlinePowershell.pasteRun.scriptGlobs 検査する .ps1 (リポジトリ直下からの bash のパターン)
#   noInlinePowershell.pasteRun.docGlobs    検査する文書 (同上)
#   noInlinePowershell.pasteRun.hint        止めたときに出す案内

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/config.sh"

input=$(cat)
harness_load_config "$input"
harness_config_guard stop

if ! cfg_enabled_optin '.noInlinePowershell'; then
  exit 0
fi

script_dir_hint=$(cfg '.noInlinePowershell.scriptDirHint' 'scripts/*.ps1')
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
hook_cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
stop_hook_active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false')

# 最後の assistant message の text を結合して取得
last_text=""
if [[ -n "$transcript" && -f "$transcript" ]]; then
  last_text=$(tail -n 2000 "$transcript" | jq -rR -n '
    [inputs | fromjson? // empty | select(.type=="assistant")]
    | last // empty
    | .message.content[]? | select(.type=="text") | .text' 2>/dev/null || true)
fi

# A) 貼り付けて実行する形の検査 (pasteRun)
if cfg_enabled_optin '.noInlinePowershell.pasteRun'; then
  pr_hint=$(cfg '.noInlinePowershell.pasteRun.hint' 'ファイルを置けない環境では、スクリプトの中身を貼り付けて実行する。全体を & { } で包み、param と -File を使わず、ブロックの中に空行を入れない')
  pr_violations=()
  file_run_re='-executionpolicy[[:space:]]+[^[:space:]]+[[:space:]]+-file([[:space:]]|$)'

  # A-1) 応答の本文。引用行とバッククォートの中は見ない
  if [[ -n "$last_text" ]]; then
    hits=$(printf '%s\n' "$last_text" | grep -vE '^[[:space:]]*>' | sed 's/`[^`]*`//g' \
      | grep -iE -- "$file_run_re" | head -2 || true)
    while IFS= read -r h; do
      [[ -n "$h" ]] && pr_violations+=("応答の本文に -File での実行: ${h:0:120}")
    done <<< "$hits"
  fi

  # A-2) 変更したファイル (差し戻し後の再生成では行わない)
  root=""
  if [[ "$stop_hook_active" != "true" && -n "$hook_cwd" && -d "$hook_cwd" ]]; then
    root=$(git -C "$hook_cwd" rev-parse --show-toplevel 2>/dev/null || true)
  fi
  if [[ -n "$root" ]]; then
    script_globs=$(cfg_list '.noInlinePowershell.pasteRun.scriptGlobs[]?')
    doc_globs=$(cfg_list '.noInlinePowershell.pasteRun.docGlobs[]?')

    # 依頼者の最後の入力の時刻。これより後に更新したファイルだけを見る (取れなければ 0 = 全部)
    since=0
    if [[ -n "$transcript" && -f "$transcript" ]]; then
      ts=$(tail -n 2000 "$transcript" | jq -rR -n "$HARNESS_JQ_USER_INPUT"'
        [inputs | fromjson? // empty | select(is_user_input) | (.timestamp // "")] | last // ""' 2>/dev/null || true)
      if [[ -n "$ts" ]]; then
        since=$(date -d "$ts" +%s 2>/dev/null || echo 0)
      fi
    fi

    match_any() { # match_any <相対パス> <改行区切りのパターン>
      local rel="$1" g
      while IFS= read -r g; do
        [[ -n "$g" ]] || continue
        # shellcheck disable=SC2053
        [[ "$rel" == $g ]] && return 0
      done <<< "$2"
      return 1
    }
    mtime_of() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }

    changed=$( { git -C "$root" diff --name-only -z HEAD 2>/dev/null || true
                 git -C "$root" ls-files --others --exclude-standard -z 2>/dev/null || true; } \
      | tr '\0' '\n' | awk 'NF && !seen[$0]++')

    while IFS= read -r rel; do
      [[ -n "$rel" ]] || continue
      f="$root/$rel"
      [[ -f "$f" ]] || continue
      if (( since > 0 )) && (( $(mtime_of "$f") < since )); then
        continue
      fi
      if [[ -n "$script_globs" ]] && match_any "$rel" "$script_globs"; then
        res=$(sed '1s/^\xEF\xBB\xBF//' "$f" | tr -d '\r' | awk -v rel="$rel" '
          { line[NR] = $0 }
          END {
            first = 0; last = 0
            for (i = 1; i <= NR; i++) {
              t = line[i]; gsub(/^[ \t]+|[ \t]+$/, "", t)
              if (t == "" || t ~ /^#/) continue
              if (!first) first = i
              last = i
            }
            if (!first) exit
            t = line[first]; gsub(/[ \t]/, "", t)
            if (t != "&{") printf "%s:%d: 全体が & { } で包まれていない\n", rel, first
            t = line[last]; gsub(/[ \t]/, "", t)
            if (t != "}") printf "%s:%d: 最後の行が } でない\n", rel, last
            for (i = 1; i <= NR; i++) {
              s = tolower(line[i])
              if (s ~ /^[ \t]*param[ \t]*\(/) printf "%s:%d: param( がある\n", rel, i
              if (s ~ /-executionpolicy[ \t]+[^ \t]+[ \t]+-file([ \t]|$)/) printf "%s:%d: -File での実行が書いてある\n", rel, i
              if (i > first && i < last) {
                t = line[i]; gsub(/[ \t]/, "", t)
                if (t == "") printf "%s:%d: ブロックの中に空行がある\n", rel, i
              }
            }
          }' | head -5 || true)
        while IFS= read -r r; do
          [[ -n "$r" ]] && pr_violations+=("$r")
        done <<< "$res"
      elif [[ -n "$doc_globs" ]] && match_any "$rel" "$doc_globs"; then
        res=$(grep -niE -- "$file_run_re" "$f" | head -3 | cut -d: -f1 \
          | awk -v rel="$rel" '{printf "%s:%d: -File での実行が書いてある\n", rel, $1}' || true)
        while IFS= read -r r; do
          [[ -n "$r" ]] && pr_violations+=("$r")
        done <<< "$res"
      fi
    done <<< "$changed"
  fi

  if (( ${#pr_violations[@]} > 0 )); then
    {
      echo "[貼り付けて実行する形の違反]"
      echo "$pr_hint"
      for v in "${pr_violations[@]:0:10}"; do
        echo "  - $v"
      done
      echo "直してから、応答を作り直してください。"
    } >&2
    exit 2
  fi
fi

# B) インライン提示の検査
# B-0) cwdMatch が設定されていれば、cwd がパス区切り単位で一致するときだけ検査する
cwd_match=$(cfg '.noInlinePowershell.cwdMatch' '')
if [[ -n "$cwd_match" ]]; then
  cwd_norm=$(printf '%s' "$hook_cwd" | sed -E 's#/+#/#g; s#/$##')
  if [[ "$cwd_norm" != */"$cwd_match" && "$cwd_norm" != */"$cwd_match"/* ]]; then
    exit 0
  fi
fi

if [[ -z "$transcript" || ! -f "$transcript" || -z "$last_text" ]]; then
  exit 0
fi

# B-1) ```powershell / ```ps1 で始まる fenced code block で 5 行以上のものを検出
has_block=$(printf '%s\n' "$last_text" | awk '
  BEGIN { in_block=0; lines=0; found=0 }
  /^```(powershell|ps1)([[:space:]]|$)/ { in_block=1; lines=0; next }
  in_block && /^```/ { if (lines>=5) found=1; in_block=0; next }
  in_block { lines++ }
  END { print (found ? "yes" : "no") }
')

if [[ "$has_block" != "yes" ]]; then
  exit 0
fi

# B-2) 直近 100 行の transcript で Write(*.ps1) が呼ばれていれば許容
ps1_write=$(tail -100 "$transcript" \
  | jq -rR -n '[inputs | fromjson? // empty] | .[]
      | select(.type=="assistant") | .message.content[]?
      | select(.type=="tool_use" and .name=="Write")
      | .input.file_path // empty' 2>/dev/null \
  | grep -E '\.ps1$' || true)

if [[ -n "$ps1_write" ]]; then
  exit 0
fi

# B-3) ブロック
cat >&2 <<MSG
[インライン PowerShell 提示の禁止]
PowerShell スクリプトをインラインのコードブロックでユーザーに提示しています。
ルール: ${script_dir_hint} に Write してパスを示すこと (チャットにスクリプトの中身を書かない)。
スクリプトをファイル化して再提示してください。
MSG
exit 2
