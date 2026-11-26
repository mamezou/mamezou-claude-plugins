#!/bin/bash
# 人に届く送信のツールを、プロジェクトの設定に従って止める hook
# (PreToolUse, matcher=mcp__.*)
#
# 送信してよいかはプロジェクトごとに違う (下書きまでにして本人が送るプロジェクトと、
# Claude が送ってよいプロジェクトがある)。設定に書き忘れたときに送ってしまわないよう、
# 設定ファイルがあるプロジェクトでは、既定を「止める」にする。
#
# 発火条件:
#   - ツール名が、送信のツールの正規表現のどれかに一致する
#     既定の正規表現 (チャットの送信・予約送信、メールの送信・返信・転送):
#       __slack_send_message$ / __slack_schedule_message$ / Gmail__(send_message|reply|forward)$
#     sendGate.extraTools[] に書いた正規表現を、既定に足して照合する
#   - sendGate.mode が "allow" でない
#
# 通過条件:
#   - sendGate.mode が "allow" (このプロジェクトでは送信してよい)
#   - sendGate.enabled が false (mode の "allow" と同じ扱い)
#
# バイパス: なし。送ってよいプロジェクトは、設定の mode を "allow" にする
# (.claude/ 配下の書き換えなので、harness-change-check.sh の承認の文字列が要る)
#
# 設定 (.claude/harness.json):
#   sendGate.mode          "block" (既定) / "allow"。ほかの値と書き忘れは "block" として扱う
#   sendGate.extraTools[]  既定に足す、送信のツールの正規表現 (jq の test())
#   sendGate.draftHint     止めたときに示す、代わりの手段の文
#   設定ファイルが無ければ何もしない。設定ファイルが JSON として読めなければ止める

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/config.sh"

input=$(cat)
harness_load_config "$input"
harness_config_guard pre

[[ -n "$HARNESS_CONFIG_PATH" ]] || exit 0

tool_name=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)
[[ "$tool_name" == mcp__* ]] || exit 0

# 送信のツールか (既定の正規表現 + extraTools)。正規表現として読めないものは飛ばす
is_send=$(printf '%s' "$HARNESS_CONFIG_JSON" | jq -r --arg t "$tool_name" '
  ["__slack_send_message$", "__slack_schedule_message$", "Gmail__(send_message|reply|forward)$"]
  + [(.sendGate.extraTools // [])[] | select(type == "string" and . != "")]
  | any(.[]; . as $re | try ($t | test($re)) catch false)' 2>/dev/null || echo false)
[[ "$is_send" == "true" ]] || exit 0

if ! cfg_enabled '.sendGate'; then
  exit 0
fi
mode=$(cfg '.sendGate.mode' 'block')
if [[ "$mode" == "allow" ]]; then
  exit 0
fi

principal=$(harness_principal)
hint=$(cfg '.sendGate.draftHint' '文面は下書きを作るツールで下書きに入れ、その場所を伝えるところまでにしてください。')
{
  printf '[送信の停止] %s は、このプロジェクトでは使いません。送信は%s本人が行います。\n' "$tool_name" "$principal"
  printf '%s\n' "$hint"
  if [[ "$mode" != "block" ]]; then
    printf '設定 sendGate.mode の値「%s」は読めないため、"block" として扱いました (使える値は "block" と "allow")。\n' "$mode"
  fi
  printf '送信してよいプロジェクトにするには、%sの承認を得て、%s の sendGate.mode を "allow" にします。\n' "$principal" "$HARNESS_CONFIG_PATH"
} >&2
exit 2
