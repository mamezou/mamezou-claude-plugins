#!/usr/bin/env bash
# harness-ja: プロジェクトの hook の中継 (クラウドのセッションに限る)
#
# 使い方 (hooks.json から): bash project-hooks-relay.sh <PreToolUse|PostToolUse|UserPromptSubmit|Stop>
#
# 背景:
#   Claude Code は hook の設定をセッションの起動時に読む。クラウドのセッションのうち、
#   起動フォルダーが repo の親で、repo の取得が起動の後になる場合、repo の
#   .claude/settings.json の hook は読み込まれない。プラグインの hook は起動時に読まれるため、
#   ここで repo の hook を呼ばれた時点で探して流す。
#
# 動く条件 (すべて満たすとき):
#   1. 環境変数 CLAUDE_CODE_REMOTE が空でない (ローカルでは何もしない。ローカルでは
#      プロジェクトの設定が起動時に読まれるため、二重に流さない)
#   2. hook 入力の cwd、またはその1つ下の階層に .claude/settings.json があり、同じ
#      .claude/harness.json の projectHooksRelay.enabled が true (利用側が明示したときだけ)
#
# 流し方:
#   - settings.json の hooks.<イベント> のうち、matcher が tool_name に合うもの
#     (空・"*"・省略はすべてに合う。それ以外は正規表現として全体一致) の command を、
#     CLAUDE_PROJECT_DIR をその repo にして、hook 入力を標準入力に渡して流す
#   - UserPromptSubmit では、そのセッションで最初の1回に限り、hooks.SessionStart
#     (matcher が startup に合うもの) も流す。起動時には repo が無く、SessionStart が
#     流れていないため
#   - どれかが終了コード2を返したら、その stderr を出して終了コード2で終わる。
#     2以外の失敗は stderr を出して続ける (Claude Code の hook と同じ扱い)
#   - 標準出力は順につなげて出す (UserPromptSubmit と SessionStart では Claude への文脈になる)
#   - 同じ実体の settings.json (シンボリックリンクを含む) は1回だけ流す
set -uo pipefail

event="${1:-}"
[[ -n "${CLAUDE_CODE_REMOTE:-}" ]] || exit 0
[[ -n "$event" ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

input=$(cat)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)
cwd="${cwd:-$PWD}"
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)
sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)

roots=()
seen=" "
for d in "$cwd" "$cwd"/*/; do
  d="${d%/}"
  s="$d/.claude/settings.json"
  [[ -f "$s" ]] || continue
  jq -e '.projectHooksRelay.enabled == true' "$d/.claude/harness.json" >/dev/null 2>&1 || continue
  real=$(readlink -f "$s" 2>/dev/null || printf '%s' "$s")
  case "$seen" in *" $real "*) continue ;; esac
  seen+="$real "
  roots+=("$(dirname "$(dirname "$real")")")
done
[[ ${#roots[@]} -gt 0 ]] || exit 0

out=""
rc=0
# run_event <repo> <イベント> <matcher と照らす値>
run_event() {
  local root="$1" ev="$2" key="$3" cmd err status
  while IFS= read -r cmd; do
    [[ -n "$cmd" ]] || continue
    err=$(mktemp)
    out+=$(printf '%s' "$input" | CLAUDE_PROJECT_DIR="$root" bash -c "$cmd" 2>"$err")
    status=$?
    if [[ $status -eq 2 ]]; then
      cat "$err" >&2
      rc=2
    elif [[ $status -ne 0 ]]; then
      cat "$err" >&2
    fi
    rm -f "$err"
  done < <(jq -r --arg ev "$ev" --arg key "$key" '
      (.hooks[$ev] // [])[]
      | select((.matcher // "") as $m | $m == "" or $m == "*" or ($key | test("^(" + $m + ")$")))
      | .hooks[]? | select(.type == "command") | .command' "$root/.claude/settings.json" 2>/dev/null)
}

for root in "${roots[@]}"; do
  if [[ "$event" == "UserPromptSubmit" ]]; then
    marker="${TMPDIR:-/tmp}/harness-ja-relay-${sid:-nosession}-$(printf '%s' "$root" | md5sum | cut -c1-12)"
    if [[ ! -e "$marker" ]]; then
      run_event "$root" SessionStart startup
      : > "$marker" 2>/dev/null || true
    fi
  fi
  run_event "$root" "$event" "$tool"
done

[[ -n "$out" ]] && printf '%s\n' "$out"
exit $rc
