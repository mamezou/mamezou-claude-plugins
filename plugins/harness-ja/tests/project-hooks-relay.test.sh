#!/usr/bin/env bash
# project-hooks-relay.sh の合成入力テスト。使い方: bash tests/project-hooks-relay.test.sh
# 一時フォルダーに「起動フォルダー/repo」の形を作り、期待する終了コードと出力を照らす。
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
relay="$here/hooks/project-hooks-relay.sh"
ng=0
tmp=$(mktemp -d)
top="$tmp/top"; repo="$top/repo"; off="$tmp/off/repo2"
mkdir -p "$repo/.claude" "$off/.claude"
cat > "$repo/.claude/settings.json" <<'JSON'
{"hooks":{
 "SessionStart":[{"matcher":"startup|resume","hooks":[{"type":"command","command":"echo start-from-$(basename \"$CLAUDE_PROJECT_DIR\")"}]}],
 "PreToolUse":[
  {"matcher":"Bash","hooks":[{"type":"command","command":"grep -q forbidden && { echo blocked-by-repo >&2; exit 2; } || exit 0"}]},
  {"matcher":"mcp__x__(a|b)","hooks":[{"type":"command","command":"echo ab-hit >&2; exit 2"}]},
  {"matcher":"Write","hooks":[{"type":"command","command":"exit 1"}]}],
 "UserPromptSubmit":[{"hooks":[{"type":"command","command":"echo prompt-ctx"}]}]
}}
JSON
echo '{"projectHooksRelay":{"enabled":true}}' > "$repo/.claude/harness.json"
cp "$repo/.claude/settings.json" "$off/.claude/settings.json"
echo '{}' > "$off/.claude/harness.json"
ln -s "$repo/.claude" "$top/.claude"   # 起動フォルダーのリンク (同じ実体は1回だけ)

t() { # 名前 期待コード 期待する出力の一部(空なら見ない) 環境(remote/local) イベント 入力
  local out code
  if [[ "$4" == remote ]]; then out=$(printf '%s' "$6" | TMPDIR="$tmp" CLAUDE_CODE_REMOTE=true bash "$relay" "$5" 2>&1); code=$?
  else out=$(printf '%s' "$6" | TMPDIR="$tmp" env -u CLAUDE_CODE_REMOTE bash "$relay" "$5" 2>&1); code=$?; fi
  if [[ "$code" != "$2" ]]; then echo "NG $1 期待 $2 実際 $code ($out)"; ng=$((ng+1)); return; fi
  if [[ -n "$3" && "$out" != *"$3"* ]]; then echo "NG $1 出力に $3 が無い ($out)"; ng=$((ng+1)); return; fi
  echo "OK $1"
}
t local_noop        0 ""               local  PreToolUse "{\"cwd\":\"$top\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"forbidden\"}}"
t bash_block        2 blocked-by-repo  remote PreToolUse "{\"cwd\":\"$top\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"forbidden\"}}"
t bash_pass         0 ""               remote PreToolUse "{\"cwd\":\"$top\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}"
t regex_full        2 ab-hit           remote PreToolUse "{\"cwd\":\"$top\",\"tool_name\":\"mcp__x__a\"}"
t regex_not_partial 0 ""               remote PreToolUse "{\"cwd\":\"$top\",\"tool_name\":\"mcp__x__abc\"}"
t other_fail_passes 0 ""               remote PreToolUse "{\"cwd\":\"$top\",\"tool_name\":\"Write\"}"
t from_repo_cwd     2 blocked-by-repo  remote PreToolUse "{\"cwd\":\"$repo\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"forbidden\"}}"
t not_enabled       0 ""               remote PreToolUse "{\"cwd\":\"$tmp/off\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"forbidden\"}}"
t first_prompt      0 start-from-repo  remote UserPromptSubmit "{\"cwd\":\"$top\",\"session_id\":\"s1\",\"prompt\":\"x\"}"
t prompt_ctx        0 prompt-ctx       remote UserPromptSubmit "{\"cwd\":\"$top\",\"session_id\":\"s1\",\"prompt\":\"x\"}"
out=$(printf '%s' "{\"cwd\":\"$top\",\"session_id\":\"s1\"}" | TMPDIR="$tmp" CLAUDE_CODE_REMOTE=true bash "$relay" UserPromptSubmit 2>&1)
if [[ "$out" == *start-from* ]]; then echo "NG second_prompt_no_start ($out)"; ng=$((ng+1)); else echo "OK second_prompt_no_start"; fi
n=$(printf '%s' "{\"cwd\":\"$top\",\"session_id\":\"s2\"}" | TMPDIR="$tmp" CLAUDE_CODE_REMOTE=true bash "$relay" UserPromptSubmit 2>&1 | grep -c prompt-ctx)
if [[ "$n" == 1 ]]; then echo "OK same_settings_once"; else echo "NG same_settings_once ($n 回)"; ng=$((ng+1)); fi
rm -rf "$tmp"
echo "NG の数: $ng"
exit $ng
