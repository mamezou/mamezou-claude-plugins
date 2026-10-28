#!/bin/bash
# harness-ja の hook 合成テスト。
# 一時ディレクトリへ合成の会話履歴 JSONL / hook 入力 / 設定ファイルを作り、7 本の hook を
# 期待値つきで実行する。過去の記録で hook を流す skills/harness-review/replay.sh も、合成の
# 記録で確かめる。末尾に PASS / FAIL 件数を出し、FAIL が 1 件でもあれば exit 1。
#
# 使い方: bash tests/run.sh   (リポジトリ内のどのディレクトリからでも実行できる)
# 必要なコマンド:
#   jq      必須 (hook 本体が使う)
#   python3 任意 (検知ログの UTF-8 確認のみ。無ければその 1 件を SKIP)

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
H="$ROOT/hooks"
EX="$ROOT/examples/harness.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq が見つかりません。jq を入れてから再実行してください。" >&2
  exit 1
fi
for f in cloud-change-check.sh draft-precheck.sh harness-change-check.sh no-inline-powershell.sh \
         require-reading.sh response-quality.sh tool-result-check.sh; do
  if [[ ! -f "$H/$f" ]]; then
    echo "hook が見つかりません: $H/$f" >&2
    exit 1
  fi
done
if [[ ! -f "$EX" ]]; then
  echo "サンプル設定が見つかりません: $EX" >&2
  exit 1
fi
RP="$ROOT/skills/harness-review/replay.sh"
if [[ ! -f "$RP" ]]; then
  echo "再生の道具が見つかりません: $RP" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 作業領域 (終了時に削除)
# ---------------------------------------------------------------------------
W=$(mktemp -d)
if [[ -z "$W" || ! -d "$W" ]]; then
  echo "一時ディレクトリを作れません (mktemp -d が失敗しました)。" >&2
  exit 1
fi
trap 'rm -rf "$W"' EXIT

PROJ="$W/proj"
NOCONF="$W/noconf"
REGEN="$W/regen"
CPD="$W/cpd"
TR="$W/tr"
IN="$W/in"
ALT="$W/alt"
mkdir -p "$PROJ/.claude" "$PROJ/docs/drafts" "$PROJ/docs/logs" "$PROJ/docs/runbooks" \
         "$NOCONF" "$REGEN/.claude" "$CPD" "$TR" "$IN" "$ALT/docs/logs"

CFG="$PROJ/.claude/harness.json"
NOCFG="$NOCONF/none.json"                       # 存在しないパス
BROKEN="$W/broken.json"
LOG="$PROJ/.claude/harness-detections.log"
CPD_LOG="$CPD/.claude/harness-detections.log"
REGEN_LOG="$REGEN/.claude/harness-detections.log"
WORKLOG="$PROJ/docs/logs/work-log-YYYYMMDD.md"
ALT_WORKLOG="$ALT/docs/logs/work-log-YYYYMMDD.md"
RUNBOOK="$PROJ/docs/runbooks/rg.md"

# ---------------------------------------------------------------------------
# 設定ファイル
# ---------------------------------------------------------------------------
# responseQuality.patterns は書かない (既定の [3, 4, 8, 19] を検査するため)
cat > "$CFG" <<'JSON'
{
  "version": 1,
  "principal": "依頼者",
  "responseQuality": {
    "enabled": true,
    "logPath": ".claude/harness-detections.log",
    "uiTerms": [],
    "fluffTerms": [],
    "bannedLeads": [],
    "regenLimitPerInput": 3
  },
  "harnessChange": {
    "enabled": true,
    "token": "[harness-go]",
    "excludePatterns": [".claude/projects/"]
  },
  "cloudChange": {
    "enabled": true,
    "projects": [
      {
        "name": "project-a",
        "clis": ["az"],
        "runbookPattern": "(docs/runbooks/.*\\.md|runbook.*\\.md)",
        "runbookHint": "docs/runbooks/*.md",
        "guideRef": "手順書の運用"
      },
      {
        "name": "project-b",
        "clis": ["aws", "cdk"],
        "cwdMatch": "project-b",
        "runbookPattern": "(docs/runbooks/.*\\.md|runbook.*\\.md)",
        "runbookHint": "docs/runbooks/ 配下の .md",
        "guideRef": "手順書の運用"
      }
    ]
  },
  "draftPrecheck": {
    "enabled": true,
    "targets": ["*/docs/drafts/*-draft.md", "*/docs/drafts/*-draft.txt"],
    "excludePatterns": ["-internal-", "_internal", "/archive/"],
    "bannedTerms": ["横串"],
    "honorific": { "name": "取引先", "suffix": "様" },
    "toolRules": [
      { "tool": "__create_draft$", "hint": "下書きの本文" },
      { "tool": "__send_message$", "fields": ["subject", "body"], "requiredFields": ["body"] }
    ]
  },
  "requireReading": {
    "enabled": true,
    "rules": [
      {
        "target": "*/proj/TODO.md",
        "requiredReadPattern": "(^|/)proj/TODO\\.md$",
        "hint": "TODO.md"
      },
      {
        "target": "*/docs/logs/*.md",
        "mode": "logs",
        "requiredReadPattern": "(^|/)docs/logs/.*\\.md$",
        "hint": "docs/logs/"
      }
    ],
    "toolRules": [
      {
        "tool": "__create_draft$",
        "requiredTool": "__read_thread$",
        "sameInput": { "room_id": "room_id", "reply_to": "thread_id" },
        "hint": "送付先のスレッド"
      }
    ]
  },
  "toolResultCheck": {
    "enabled": true,
    "rules": [
      {
        "tool": "__create_draft$",
        "successPattern": "\"created_id\":\\s*\"X[0-9A-Z]+\"",
        "hint": "下書きの ID"
      }
    ]
  },
  "noInlinePowershell": {
    "enabled": true,
    "scriptDirHint": "scripts/{category}/*.ps1"
  }
}
JSON

printf '{ "responseQuality": \n' > "$BROKEN"      # JSON として読めない設定

cp "$CFG" "$REGEN/.claude/harness.json"
jq '.responseQuality.enabled=false'    "$CFG" > "$PROJ/.claude/harness-off.json"
jq '.noInlinePowershell.enabled=false' "$CFG" > "$PROJ/.claude/harness-psoff.json"
jq '.noInlinePowershell.cwdMatch="project-a"' "$CFG" > "$PROJ/.claude/harness-pscwd.json"
jq '.harnessChange.enabled=false'      "$CFG" > "$PROJ/.claude/harness-hgoff.json"
jq '.responseQuality.patterns=[5,18]'  "$CFG" > "$PROJ/.claude/harness-p518.json"
jq '.draftPrecheck.checks={"internalPaths":false}' "$CFG" > "$PROJ/.claude/harness-dpoff.json"
jq '.toolResultCheck.enabled=false'    "$CFG" > "$PROJ/.claude/harness-tcoff.json"
jq '.requireReading.enabled=false'     "$CFG" > "$PROJ/.claude/harness-rroff.json"
# 2 つ目の規則: スレッドの指定が無い下書きには、部屋の読み取りを求める
jq '.requireReading.toolRules += [{"tool":"__create_draft$","requiredTool":"__read_room$","sameInput":{"room_id":"room_id"},"hint":"送付先の部屋"}]' \
  "$CFG" > "$PROJ/.claude/harness-tl2.json"
# 先頭に、requiredTool / successPattern の無い規則を置く (飛ばして次の規則を使う)
jq '.requireReading.toolRules = [{"tool":"__create_draft$","hint":"書きかけの規則"}] + .requireReading.toolRules
    | .toolResultCheck.rules = [{"tool":"__create_draft$","hint":"書きかけの規則"}] + .toolResultCheck.rules' \
  "$CFG" > "$PROJ/.claude/harness-tlskip.json"
jq '.requireReading.toolRules[0].requiredTool="("' "$CFG" > "$PROJ/.claude/harness-tlbadre.json"
RROFF="$PROJ/.claude/harness-rroff.json"
TL2="$PROJ/.claude/harness-tl2.json"
TLSKIP="$PROJ/.claude/harness-tlskip.json"
TLBADRE="$PROJ/.claude/harness-tlbadre.json"
P518="$PROJ/.claude/harness-p518.json"
DPOFF="$PROJ/.claude/harness-dpoff.json"
touch "$PROJ/TODO.md" "$RUNBOOK"

# ---------------------------------------------------------------------------
# 合成の会話履歴 (JSONL)
# ---------------------------------------------------------------------------
mk_user()    { jq -cn --arg t "$1" '{type:"user",message:{role:"user",content:$t}}'; }
mk_user_id() { jq -cn --arg t "$1" --arg u "$2" '{type:"user",uuid:$u,message:{role:"user",content:$t}}'; }
mk_asst()    { jq -cn --arg t "$1" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}'; }
mk_read()    { jq -cn --arg p "$1" '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",name:"Read",input:{file_path:$p}}]}}'; }
mk_write()   { jq -cn --arg p "$1" '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",name:"Write",input:{file_path:$p}}]}}'; }
mk_toolres() { jq -cn '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"t1",content:"ok"}]}}'; }
# ツール呼び出しと、呼び出しの ID に対応する結果 (第 2 引数 true でエラーの結果)
mk_tool()    { jq -cn --arg id "$1" --arg n "$2" --argjson in "$3" '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:$id,name:$n,input:$in}]}}'; }
mk_toolres_id() { jq -cn --arg id "$1" --argjson err "${2:-false}" '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:$id,is_error:$err,content:"ok"}]}}'; }
# hook のフィードバック等、依頼者が書いていない user 行
mk_user_meta() { jq -cn --arg t "$1" '{type:"user",isMeta:true,message:{role:"user",content:$t}}'; }
# キーの後ろに空白のある JSON (jq -c では作れないため直接組み立てる)
mk_user_spaced() { printf '{"type": "user", "uuid": "%s", "message": {"role": "user", "content": "%s"}}\n' "$2" "$1"; }
mk_asst_spaced() {
  local t
  t=$(printf '%s' "$1" | jq -Rs .)
  printf '{"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": %s}]}}\n' "$t"
}

# response-quality: 既定で有効な 4 パターン (3 / 4 / 8 / 19)
{ mk_user "状況を教えて"; mk_asst "ひな形を作成し、報告しました。"; }              > "$TR/rq-p3.jsonl"
{ mk_user "状況を教えて"; mk_asst "ひな形を作成しました。報告書は未着手です。"; } > "$TR/rq-p3ok.jsonl"
{ mk_user "状況を教えて"; mk_asst "詳細は § 3 を参照。"; }                        > "$TR/rq-p4.jsonl"
{ mk_user "状況を教えて"; mk_asst "詳細は 3 節を参照。"; }                        > "$TR/rq-p4ok.jsonl"
{ mk_user "状況を教えて"; mk_asst "以後注意します。"; }                           > "$TR/rq-p8.jsonl"
{ mk_user "状況を教えて"; mk_asst "検知を追加し、テストを実行した。"; }           > "$TR/rq-p8ok.jsonl"
{ mk_user "この設計書、あってる?"; mk_asst "ご指摘の設計書はありません。TODO の1行に記載がありました。"; } \
  > "$TR/rq-p19-doc.jsonl"
{ mk_user "この設計書、あってる?"; mk_asst "ご指摘の設計書はありません。目次を開いて確かめました。"; } \
  > "$TR/rq-p19-docok.jsonl"
{ mk_user "認識はあってる?"; mk_asst "認識にズレがあります。"; }                        > "$TR/rq-p19-dis.jsonl"
{ mk_user "認識はあってる?"; mk_asst "認識にズレがあります。出典は設計書の3章です。"; } > "$TR/rq-p19-disok.jsonl"

# response-quality: パターン 5 (文末) と 18 (文頭・行頭) の境界
{ mk_user "状況を教えて"; mk_asst "設定は効きます。"; }                                > "$TR/rq-p5.jsonl"
{ mk_user "状況を教えて"; mk_asst "レプリカが落ちる条件を確認した。"; }                > "$TR/rq-p5ok.jsonl"
{ mk_user "状況を教えて"; mk_asst "以下のように整理しました。"; }                      > "$TR/rq-p18.jsonl"
{ mk_user "状況を教えて"; mk_asst "手順は次のとおり。作業は以下のように進めた記録がある。"; } \
  > "$TR/rq-p18ok.jsonl"

# response-quality: バイパスの文字列 (それだけの行 / 質問文の中)
{ mk_user "$(printf '状況を教えて\n[hook-bypass: response-quality]')"; mk_asst "以後注意します。"; } \
  > "$TR/rq-bypass.jsonl"

# response-quality: 差し戻し回数の集計用 (uuid つき)
{ mk_user_id "状況を教えて" "u-1"; mk_asst "以後注意します。"; } > "$TR/rq-uuid1.jsonl"

# response-quality: 空白入り JSON の user 行を区切りとして認識できるか
# 区切りより前の応答に検知語を置き、区切りより後ろの応答は検知語なしにする
{ mk_asst "以後注意します。"
  mk_user_spaced "状況を教えて" "u-sp"
  mk_asst "アラート設定を更新した。件数は12件。"; } > "$TR/rq-spaced.jsonl"

# harness-change-check 用 (ツール結果行を挟む)
{ mk_user "hook を直して"; mk_toolres; } > "$TR/hg-nogo.jsonl"
{ mk_user "$(printf 'hook を直して\n[harness-go]')"; mk_toolres; } > "$TR/hg-go.jsonl"
{ mk_user "[harness-go] とは何ですか"; mk_toolres; } > "$TR/hg-inline.jsonl"

# cloud-change-check 用
{ mk_user "リソースグループを作って"; mk_toolres; } > "$TR/cg-nogo.jsonl"
{ mk_user "$(printf 'リソースグループを作って\n[change-go: project-a]')"; mk_read "$RUNBOOK"; } \
  > "$TR/cg-go.jsonl"
{ mk_user "$(printf 'リソースグループを作って\n[change-go: project-a]')"; mk_write "$RUNBOOK"; } \
  > "$TR/cg-writeonly.jsonl"
{ mk_user "[change-go: project-a] とは何ですか"; mk_read "$RUNBOOK"; } > "$TR/cg-inline.jsonl"

# require-reading 用
{ mk_user "TODO を更新して"; mk_toolres; }              > "$TR/rr-noread.jsonl"
{ mk_user "TODO を更新して"; mk_read "$PROJ/TODO.md"; } > "$TR/rr-read.jsonl"
{ mk_user "ログを追記して";  mk_read "$WORKLOG"; }      > "$TR/rr-logread.jsonl"
{ mk_user "ログを追記して";  mk_read "$ALT_WORKLOG"; }  > "$TR/rr-logalt.jsonl"

# require-reading のツールの規則用 (下書きのツールの前に、同じスレッドの読み取りを求める)
TL_READ='{"room_id":"R1","thread_id":"111.222"}'
TL_OTHER='{"room_id":"R1","thread_id":"999.000"}'
{ mk_user "下書きを作って"; mk_toolres; } > "$TR/tl-noread.jsonl"
{ mk_user "下書きを作って"; mk_tool r1 mcp__chat__read_thread "$TL_READ";  mk_toolres_id r1; }      > "$TR/tl-read.jsonl"
{ mk_user "下書きを作って"; mk_tool r1 mcp__chat__read_thread "$TL_OTHER"; mk_toolres_id r1; }      > "$TR/tl-other.jsonl"
{ mk_user "下書きを作って"; mk_tool r1 mcp__chat__read_thread "$TL_READ"; }                         > "$TR/tl-noresult.jsonl"
{ mk_user "下書きを作って"; mk_tool r1 mcp__chat__read_thread "$TL_READ";  mk_toolres_id r1 true; } > "$TR/tl-error.jsonl"
{ mk_user "スレッドを読んで"; mk_tool r1 mcp__chat__read_thread "$TL_READ"; mk_toolres_id r1
  mk_asst "スレッドを読んだ。"; mk_user "下書きを作って"; } > "$TR/tl-stale.jsonl"
{ mk_user "$(printf '下書きを作って\n[hook-bypass: resource-reading]')"; mk_toolres; } > "$TR/tl-bypass.jsonl"
# 読み取りの後に hook のフィードバック行 (isMeta) が入っても、読み取りは数える
{ mk_user "下書きを作って"; mk_tool r1 mcp__chat__read_thread "$TL_READ"; mk_toolres_id r1
  mk_user_meta "Stop hook feedback: 応答を作り直してください"; } > "$TR/tl-meta.jsonl"

# no-inline-powershell 用 (6 行の powershell ブロック)
ps_text=$(printf '確認スクリプトです。\n```powershell\n$a = 1\n$b = 2\n$c = 3\n$d = 4\n$e = 5\n$f = 6\n```\n')
{ mk_user "確認方法を教えて"; mk_asst "$ps_text"; } > "$TR/ps-block.jsonl"
{ mk_user_spaced "確認方法を教えて" "u-ps"; mk_asst_spaced "$ps_text"; } > "$TR/ps-spaced.jsonl"

# replay.sh 用 (セッション ID・時刻・cwd つきの記録。判定に行番号を使うため並びを変えない)
#   1 依頼者の入力 / 2 TODO.md を読まずに Edit (止まる) / 3 結果 / 4 Read / 5 結果 /
#   6 Read の後の Edit (通る) / 7 結果 / 8 空約束の応答 (Stop で止まる) /
#   9 Stop hook の差し戻し (isMeta) / 10 作り直した応答 (stop_hook_active=true で通る) /
#   11 依頼者の入力 / 12 az の変更系 (止まる) / 13 結果 / 14 応答 (通る)
rp_user() { jq -cn --arg t "$1" --arg u "$2" --arg ts "$3" --arg cwd "$PROJ" \
  '{type:"user",uuid:$u,timestamp:$ts,sessionId:"s-rp",cwd:$cwd,message:{role:"user",content:$t}}'; }
rp_asst() { jq -cn --arg t "$1" --arg ts "$2" --arg cwd "$PROJ" \
  '{type:"assistant",timestamp:$ts,sessionId:"s-rp",cwd:$cwd,message:{role:"assistant",content:[{type:"text",text:$t}]}}'; }
rp_tool() { jq -cn --arg id "$1" --arg n "$2" --argjson in "$3" --arg ts "$4" --arg cwd "$PROJ" \
  '{type:"assistant",timestamp:$ts,sessionId:"s-rp",cwd:$cwd,message:{role:"assistant",content:[{type:"tool_use",id:$id,name:$n,input:$in}]}}'; }
rp_res() { jq -cn --arg id "$1" \
  '{type:"user",sessionId:"s-rp",message:{role:"user",content:[{type:"tool_result",tool_use_id:$id,content:"ok"}]}}'; }
rp_edit=$(jq -cn --arg p "$PROJ/TODO.md" '{file_path:$p,old_string:"a",new_string:"b"}')
rp_read=$(jq -cn --arg p "$PROJ/TODO.md" '{file_path:$p}')
{ rp_user "TODO を更新して" u-rp1 2026-01-01T00:00:01Z
  rp_tool e1 Edit "$rp_edit" 2026-01-01T00:00:02Z
  rp_res e1
  rp_tool r1 Read "$rp_read" 2026-01-01T00:00:04Z
  rp_res r1
  rp_tool e2 Edit "$rp_edit" 2026-01-01T00:00:06Z
  rp_res e2
  rp_asst "以後注意します。" 2026-01-01T00:00:08Z
  jq -cn '{type:"user",isMeta:true,sessionId:"s-rp",message:{role:"user",content:"Stop hook feedback:\n[応答の文体違反]"}}'
  rp_asst "検知を追加し、テストを実行した。" 2026-01-01T00:00:10Z
  rp_user "リソースグループを作って" u-rp2 2026-01-01T00:00:11Z
  rp_tool b1 Bash '{"command":"az group create --name rg-test --location japaneast"}' 2026-01-01T00:00:12Z
  rp_res b1
  rp_asst "変更系のコマンドは止まった。" 2026-01-01T00:00:14Z
} > "$TR/s-rp.jsonl"
# サブエージェントの記録 (isSidechain:true)。TODO.md を読まずに 2 行目で Edit し、空約束で終わる
{ jq -cn '{type:"user",isSidechain:true,sessionId:"s-rp",message:{role:"user",content:"TODO を直して"}}'
  jq -cn --argjson in "$rp_edit" --arg cwd "$PROJ" \
    '{type:"assistant",isSidechain:true,timestamp:"2026-01-01T00:01:02Z",sessionId:"s-rp",cwd:$cwd,message:{role:"assistant",content:[{type:"tool_use",id:"x1",name:"Edit",input:$in}]}}'
  jq -cn '{type:"user",isSidechain:true,sessionId:"s-rp",message:{role:"user",content:[{type:"tool_result",tool_use_id:"x1",content:"ok"}]}}'
  jq -cn --arg cwd "$PROJ" \
    '{type:"assistant",isSidechain:true,timestamp:"2026-01-01T00:01:04Z",sessionId:"s-rp",cwd:$cwd,message:{role:"assistant",content:[{type:"text",text:"以後注意します。"}]}}'
} > "$TR/agent-rp1.jsonl"
# Stop の hook の実行の記録 (stop_hook_summary) がある記録。この行の直前だけを Stop の点にする
#   1 入力 / 2 応答 / 3 実行の記録 / 4 他のセッションからのメッセージ (isMeta) /
#   5 空約束の応答 (止まる) / 6 実行の記録 / 7 他のセッションからのメッセージ / 8 応答 /
#   9 実行の記録 / 10 入力 / 11 空約束の応答 (実行の記録が無いため流さない) / 12 入力 /
#   13 応答 / 14 実行の記録
rp2_user() { jq -cn --arg t "$1" --arg u "$2" \
  '{type:"user",uuid:$u,sessionId:"s-rp2",message:{role:"user",content:$t}}'; }
rp2_meta() { jq -cn '{type:"user",isMeta:true,sessionId:"s-rp2",message:{role:"user",content:"Another Claude session sent a message: 引き継ぎ"}}'; }
rp2_asst() { jq -cn --arg t "$1" --arg ts "$2" --arg cwd "$PROJ" \
  '{type:"assistant",timestamp:$ts,sessionId:"s-rp2",cwd:$cwd,message:{role:"assistant",content:[{type:"text",text:$t}]}}'; }
rp2_sum() { jq -cn '{type:"system",subtype:"stop_hook_summary",sessionId:"s-rp2"}'; }
{ rp2_user "状況を教えて" u-s1; rp2_asst "確認した。" 2026-01-02T00:00:02Z; rp2_sum
  rp2_meta; rp2_asst "以後注意します。" 2026-01-02T00:00:05Z; rp2_sum
  rp2_meta; rp2_asst "確認した。" 2026-01-02T00:00:08Z; rp2_sum
  rp2_user "続けて" u-s2; rp2_asst "以後注意します。" 2026-01-02T00:00:11Z
  rp2_user "どうぞ" u-s3; rp2_asst "検知を追加した。" 2026-01-02T00:00:13Z; rp2_sum
} > "$TR/s-rp2.jsonl"
# 人が付けた正誤のラベル (session_id / 時刻か行 / expected / メモ)
printf '%s\n' \
  $'# session_id\t時刻か行\texpected\tメモ' \
  $'s-rp\t2\tblock\t読まずに編集' \
  $'s-rp\t6\tblock\t読んだ後の編集' \
  $'s-rp\t2026-01-01T00:00:08Z\tpass\t空約束の応答' \
  $'s-rp\t10\tpass\t作り直した応答' \
  $'agent-rp1\t2\tblock\tサブエージェントの編集' \
  $'s-rp\t99\tpass\t記録に無い行' > "$W/rp-labels.tsv"
# 本物の検知ログを絶対パスで指す設定 (再生で書き込まれないことを確かめる)
mkdir -p "$W/abs"
printf '既存の行\n' > "$W/abs/real.log"
jq --arg p "$W/abs/real.log" '.responseQuality.logPath=$p' "$CFG" > "$W/abs-harness.json"

# ---------------------------------------------------------------------------
# hook 入力 JSON
# ---------------------------------------------------------------------------
stop_input() { # stop_input <transcript> <cwd> <stop_hook_active> [session_id]
  jq -cn --arg tr "$1" --arg cwd "$2" --argjson active "$3" --arg sid "${4:-}" \
    '{stop_hook_active:$active,transcript_path:$tr,cwd:$cwd}
     + (if $sid == "" then {} else {session_id:$sid} end)'
}
bash_input() { # bash_input <transcript> <cwd> <command>
  jq -cn --arg tr "$1" --arg cwd "$2" --arg c "$3" \
    '{tool_name:"Bash",tool_input:{command:$c},transcript_path:$tr,cwd:$cwd}'
}
write_input() { # write_input <transcript> <cwd> <file_path> <content>
  jq -cn --arg tr "$1" --arg cwd "$2" --arg p "$3" --arg c "$4" \
    '{tool_name:"Write",tool_input:{file_path:$p,content:$c},transcript_path:$tr,cwd:$cwd}'
}
edit_input() { # edit_input <transcript> <cwd> <file_path> <new_string>
  jq -cn --arg tr "$1" --arg cwd "$2" --arg p "$3" --arg n "$4" \
    '{tool_name:"Edit",tool_input:{file_path:$p,old_string:"a",new_string:$n},transcript_path:$tr,cwd:$cwd}'
}

mcp_input() { # mcp_input <transcript> <cwd> <tool_name> <tool_input の JSON>
  jq -cn --arg tr "$1" --arg cwd "$2" --arg n "$3" --argjson in "$4" \
    '{tool_name:$n,tool_input:$in,transcript_path:$tr,cwd:$cwd}'
}
post_input() { # post_input <cwd> <tool_name> <tool_response の JSON>
  jq -cn --arg cwd "$1" --arg n "$2" --argjson res "$3" \
    '{hook_event_name:"PostToolUse",tool_name:$n,tool_input:{},tool_response:$res,cwd:$cwd}'
}

# response-quality
for n in p3 p3ok p4 p4ok p8 p8ok p19-doc p19-docok p19-dis p19-disok p5 p5ok p18 p18ok bypass spaced; do
  stop_input "$TR/rq-$n.jsonl" "$PROJ" false > "$IN/rq-$n.json"
done
stop_input "$TR/rq-p8.jsonl" "$PROJ"   true  > "$IN/rq-active.json"
stop_input "$TR/rq-p8.jsonl" "$NOCONF" false > "$IN/rq-noconf.json"

# 差し戻し回数の集計 (session_id と user 行の uuid でまとめる)
stop_input "$TR/rq-uuid1.jsonl" "$REGEN" false "s-regen" > "$IN/rq-regen1.json"
stop_input "$TR/rq-uuid1.jsonl" "$REGEN" true  "s-regen" > "$IN/rq-regen2.json"

# harness-change-check
write_input "$TR/hg-nogo.jsonl"   "$PROJ"   "$PROJ/.claude/rules/x.md"            "本文" > "$IN/hg-write.json"
write_input "$TR/hg-go.jsonl"     "$PROJ"   "$PROJ/.claude/rules/x.md"            "本文" > "$IN/hg-go.json"
write_input "$TR/hg-inline.jsonl" "$PROJ"   "$PROJ/.claude/rules/x.md"            "本文" > "$IN/hg-inline.json"
write_input "$TR/hg-nogo.jsonl"   "$PROJ"   "$PROJ/.claude/projects/p/state.json" "{}"   > "$IN/hg-proj.json"
write_input "$TR/hg-nogo.jsonl"   "$PROJ"   "$NOCONF/.claude/harness.json"        "{}"   > "$IN/hg-initcfg.json"
write_input "$TR/hg-nogo.jsonl"   "$PROJ"   "$CFG"                                "{}"   > "$IN/hg-existcfg.json"
write_input "$TR/hg-nogo.jsonl"   "$NOCONF" "$NOCONF/.claude/rules/x.md"          "本文" > "$IN/hg-noconf.json"
bash_input  "$TR/hg-nogo.jsonl" "$PROJ" "echo x > $PROJ/.claude/settings.json"  > "$IN/hg-bash.json"
bash_input  "$TR/hg-nogo.jsonl" "$PROJ" "cp $PROJ/.claude/hooks/x.sh /tmp/"     > "$IN/hg-read.json"
bash_input  "$TR/hg-nogo.jsonl" "$PROJ" 'mkdir -p .claude/rules'                > "$IN/hg-mkdir.json"
bash_input  "$TR/hg-nogo.jsonl" "$PROJ" \
  'cp -n "${CLAUDE_PLUGIN_ROOT}"/rules-templates/*.md .claude/rules/'           > "$IN/hg-initcp.json"

# cloud-change-check
cg_change="az group create --name rg-test --location japaneast"
bash_input "$TR/cg-nogo.jsonl"      "$PROJ"        "$cg_change"                            > "$IN/cg-create.json"
bash_input "$TR/cg-nogo.jsonl"      "$PROJ"        "az group list"                         > "$IN/cg-list.json"
bash_input "$TR/cg-go.jsonl"        "$PROJ"        "$cg_change"                            > "$IN/cg-go.json"
bash_input "$TR/cg-writeonly.jsonl" "$PROJ"        "$cg_change"                            > "$IN/cg-writeonly.json"
bash_input "$TR/cg-inline.jsonl"    "$PROJ"        "$cg_change"                            > "$IN/cg-inline.json"
bash_input "$TR/cg-nogo.jsonl"      "$NOCONF"      "$cg_change"                            > "$IN/cg-noconf.json"
bash_input "$TR/cg-nogo.jsonl"      "/w/project-a" "$cg_change"                            > "$IN/cg-example.json"
bash_input "$TR/cg-nogo.jsonl"      "/w/project-b" "npx cdk deploy MyStack"                > "$IN/cg-cdk.json"
bash_input "$TR/cg-nogo.jsonl"      "/w/project-b" "cdk watch MyStack"                     > "$IN/cg-cdkwatch.json"
bash_input "$TR/cg-nogo.jsonl"      "/w/project-b" "aws s3 sync ./site s3://bucket --delete" > "$IN/cg-s3sync.json"
bash_input "$TR/cg-nogo.jsonl"      "/w/project-b" "aws cloudformation deploy --template-file t.yml --stack-name s" \
  > "$IN/cg-cfndeploy.json"
bash_input "$TR/cg-nogo.jsonl"      "/w/project-b" "aws lambda invoke --function-name f out.json" > "$IN/cg-invoke.json"
bash_input "$TR/cg-nogo.jsonl"      "/w/other"     "aws s3api delete-bucket --bucket b"     > "$IN/cg-nomatch.json"
bash_input "$TR/cg-nogo.jsonl"      "/w/project-a-old" "$cg_change"                        > "$IN/cg-suffix.json"
bash_input "$TR/cg-nogo.jsonl"      "$PROJ"        "az account set --subscription foo"     > "$IN/cg-acct.json"
bash_input "$TR/cg-nogo.jsonl"      "$PROJ"        "az group show --name rg --query set"   > "$IN/cg-query.json"
bash_input "$TR/cg-nogo.jsonl"      "$PROJ"        "echo az group create --name demo"      > "$IN/cg-echo.json"

# draft-precheck
DRAFT="$PROJ/docs/drafts/report-draft.md"
DRAFT_EXCL="$PROJ/docs/drafts/report-internal-draft.md"
DRAFT_OUT="$PROJ/docs/other/report-draft.md"
dp_abs_body=$(printf 'ご確認ください。\n資料は /var/data/report にあります。\n')
dp_clean_body=$(printf 'ご確認ください。\n本日の打ち合わせの件、承知しました。\n')
dp_hon_body=$(printf '# 取引先 ご報告\n横串で確認します。\n')
dp_url_body=$(printf 'ご確認ください。\n手順は https://example.com/docs/setup をご覧ください。\n')
write_input "$TR/rr-noread.jsonl" "$PROJ"   "$DRAFT"      "$dp_abs_body"                  > "$IN/dp-abs.json"
write_input "$TR/rr-noread.jsonl" "$PROJ"   "$DRAFT_EXCL" "$dp_abs_body"                  > "$IN/dp-excl.json"
write_input "$TR/rr-noread.jsonl" "$PROJ"   "$DRAFT"      "$dp_clean_body"                > "$IN/dp-clean.json"
write_input "$TR/rr-noread.jsonl" "$PROJ"   "$DRAFT"      "$dp_url_body"                  > "$IN/dp-url.json"
edit_input  "$TR/rr-noread.jsonl" "$PROJ"   "$DRAFT"      "$dp_hon_body"                  > "$IN/dp-hon.json"
write_input "$TR/rr-noread.jsonl" "$PROJ"   "$DRAFT_OUT"  "資料は /var/data にあります。" > "$IN/dp-nontarget.json"
write_input "$TR/rr-noread.jsonl" "$NOCONF" "$DRAFT"      "資料は /var/data にあります。" > "$IN/dp-noconf.json"

# draft-precheck (MCP ツールの本文)
{ mk_user "$(printf '下書きを作って\n[hook-bypass: draft-precheck]')"; mk_toolres; } > "$TR/dp-bypass.jsonl"
jq '.draftPrecheck.targets=[]' "$CFG" > "$PROJ/.claude/harness-dptoolonly.json"
jq '.draftPrecheck.toolRules[0].tool="("' "$CFG" > "$PROJ/.claude/harness-dpbadre.json"
DPTOOLONLY="$PROJ/.claude/harness-dptoolonly.json"
DPBADRE="$PROJ/.claude/harness-dpbadre.json"
mcp_input "$TR/rr-noread.jsonl" "$PROJ" mcp__chat__create_draft \
  '{"subject":"ご連絡","body":"資料は /var/data/report にあります。"}'    > "$IN/dm-abs.json"
mcp_input "$TR/rr-noread.jsonl" "$PROJ" mcp__chat__create_draft \
  '{"subject":"横串の件","body":"ご確認ください。"}'                      > "$IN/dm-term.json"
mcp_input "$TR/rr-noread.jsonl" "$PROJ" mcp__chat__create_draft \
  '{"subject":"ご連絡","body":"本日の打ち合わせの件、承知しました。"}'    > "$IN/dm-clean.json"
mcp_input "$TR/rr-noread.jsonl" "$PROJ" mcp__chat__create_draft \
  '{"subject":"ご連絡","body":"ご確認ください。","htmlBody":"<p>/var/data/report</p>"}' > "$IN/dm-html.json"
mcp_input "$TR/rr-noread.jsonl" "$PROJ" mcp__chat__read_thread \
  '{"subject":"ご連絡","body":"資料は /var/data/report にあります。"}'    > "$IN/dm-nontarget.json"
mcp_input "$TR/rr-noread.jsonl" "$PROJ" mcp__chat__create_draft \
  '{"draftId":"D1"}'                                                       > "$IN/dm-nocontent-opt.json"
mcp_input "$TR/rr-noread.jsonl" "$PROJ" mcp__chat__send_message \
  '{"draftId":"D1"}'                                                       > "$IN/dm-nocontent-req.json"
mcp_input "$TR/dp-bypass.jsonl" "$PROJ" mcp__chat__create_draft \
  '{"subject":"ご連絡","body":"資料は /var/data/report にあります。"}'    > "$IN/dm-bypass.json"
mcp_input "$TR/rr-noread.jsonl" "$NOCONF" mcp__chat__create_draft \
  '{"subject":"ご連絡","body":"資料は /var/data/report にあります。"}'    > "$IN/dm-noconf.json"
# 異常な入力と設定 (どれも、検査を保証できない形なので 2 で止める)
mcp_input "$TR/rr-noread.jsonl" "$PROJ" mcp__chat__create_draft '["a"]'   > "$IN/dm-arr.json"
mcp_input "$TR/rr-noread.jsonl" "$PROJ" mcp__chat__create_draft '"a"'     > "$IN/dm-str.json"
mcp_input "$TR/rr-noread.jsonl" "$PROJ" mcp__chat__create_draft 'null'    > "$IN/dm-null.json"
mcp_input "$TR/rr-noread.jsonl" "$PROJ" mcp__chat__create_draft \
  '{"to":["a@example.com"],"htmlBody":"<p>資料は /var/data にあります。</p>"}' > "$IN/dm-htmlonly.json"
mcp_input "$TR/rr-noread.jsonl" "$PROJ" mcp__chat__post_message \
  '{"subject":"ご連絡","message":"資料は /var/data/report にあります。"}'  > "$IN/dm-custom-hit.json"
mcp_input "$TR/rr-noread.jsonl" "$PROJ" mcp__chat__post_message \
  '{"subject":"/var/data/report の件"}'                                    > "$IN/dm-custom-miss.json"
mcp_input "$TR/rr-noread.jsonl" "$PROJ" mcp__chat__create_draft_1 \
  '{"subject":"ご連絡","body":"資料は /var/data/report にあります。"}'    > "$IN/dm-digit.json"
jq '.draftPrecheck.toolRules[0].fields="body"'        "$CFG" > "$PROJ/.claude/harness-dpfstr.json"
jq '.draftPrecheck.toolRules[0].fields=[]'            "$CFG" > "$PROJ/.claude/harness-dpfempty.json"
jq '.draftPrecheck.toolRules[0].fields=["body",1]'    "$CFG" > "$PROJ/.claude/harness-dpfnum.json"
jq '.draftPrecheck.toolRules=[{"tool":"__post_message$","fields":["message"]}]' \
  "$CFG" > "$PROJ/.claude/harness-dpcustom.json"
jq '.draftPrecheck.toolRules[0].tool="create_draft_\\d$"' "$CFG" > "$PROJ/.claude/harness-dpdigit.json"
jq 'del(.draftPrecheck.toolRules)'                    "$CFG" > "$PROJ/.claude/harness-dpnokey.json"
jq '.draftPrecheck.toolRules[0].requiredFields=["body"]' "$CFG" > "$PROJ/.claude/harness-dpreq.json"
jq '.draftPrecheck.toolRules="oops"'                  "$CFG" > "$PROJ/.claude/harness-dpshape1.json"
jq '.draftPrecheck.toolRules=[1]'                     "$CFG" > "$PROJ/.claude/harness-dpshape2.json"
jq '.draftPrecheck.toolRules=[{"fields":["body"]}]'   "$CFG" > "$PROJ/.claude/harness-dpshape3.json"
jq '.draftPrecheck.toolRules[0].requiredFields="body"' "$CFG" > "$PROJ/.claude/harness-dpshape4.json"
DPSHAPE1="$PROJ/.claude/harness-dpshape1.json"
DPSHAPE2="$PROJ/.claude/harness-dpshape2.json"
DPSHAPE3="$PROJ/.claude/harness-dpshape3.json"
DPSHAPE4="$PROJ/.claude/harness-dpshape4.json"
mcp_input "$TR/rr-noread.jsonl" "$PROJ" mcp__chat__create_draft \
  '{"subject":"ご連絡","htmlBody":"<p>資料は /var/data にあります。</p>"}' > "$IN/dm-subj-html.json"
mcp_input "$TR/rr-noread.jsonl" "$PROJ" mcp__chat__create_draft \
  '{"subject":"ご連絡","body":"   "}'                                      > "$IN/dm-blank-body.json"
DPFSTR="$PROJ/.claude/harness-dpfstr.json"
DPFEMPTY="$PROJ/.claude/harness-dpfempty.json"
DPFNUM="$PROJ/.claude/harness-dpfnum.json"
DPCUSTOM="$PROJ/.claude/harness-dpcustom.json"
DPDIGIT="$PROJ/.claude/harness-dpdigit.json"
DPNOKEY="$PROJ/.claude/harness-dpnokey.json"
DPREQ="$PROJ/.claude/harness-dpreq.json"
jq -cn --arg tr "$TR/rr-noread.jsonl" --arg cwd "$PROJ" --arg p "$DRAFT" --arg n "資料は /var/data にあります。" \
  '{tool_name:"MultiEdit",tool_input:{file_path:$p,edits:[{old_string:"a",new_string:$n}]},transcript_path:$tr,cwd:$cwd}' \
  > "$IN/dm-multiedit.json"

# require-reading
edit_input  "$TR/rr-noread.jsonl"  "$PROJ"   "$PROJ/TODO.md"   "b"      > "$IN/rr-noread.json"
edit_input  "$TR/rr-read.jsonl"    "$PROJ"   "$PROJ/TODO.md"   "b"      > "$IN/rr-read.json"
edit_input  "$TR/rr-noread.jsonl"  "$NOCONF" "$PROJ/TODO.md"   "b"      > "$IN/rr-noconf.json"
edit_input  "$TR/rr-noread.jsonl"  "$PROJ"   "$PROJ/README.md" "b"      > "$IN/rr-nontarget.json"
write_input "$TR/rr-noread.jsonl"  "$PROJ"   "$WORKLOG"        "# ログ" > "$IN/rr-lognew.json"
edit_input  "$TR/rr-noread.jsonl"  "$PROJ"   "$WORKLOG"        "b"      > "$IN/rr-logedit.json"
edit_input  "$TR/rr-logread.jsonl" "$PROJ"   "$WORKLOG"        "b"      > "$IN/rr-logedit2.json"
edit_input  "$TR/rr-logalt.jsonl"  "$PROJ"   "$WORKLOG"        "b"      > "$IN/rr-logalt.json"

# require-reading のツールの規則
TL_DRAFT='{"room_id":"R1","reply_to":"111.222","message":"本文"}'
TL_TOP='{"room_id":"R1","message":"本文"}'
for n in noread read other noresult error stale bypass meta; do
  mcp_input "$TR/tl-$n.jsonl" "$PROJ" mcp__chat__create_draft "$TL_DRAFT" > "$IN/tl-$n.json"
done
mcp_input "$TR/tl-noread.jsonl" "$PROJ"   mcp__chat__create_draft "$TL_TOP"   > "$IN/tl-top.json"
mcp_input "$TR/tl-noread.jsonl" "$PROJ"   mcp__chat__read_thread  "$TL_READ"  > "$IN/tl-nontarget.json"
mcp_input "$TR/tl-noread.jsonl" "$NOCONF" mcp__chat__create_draft "$TL_DRAFT" > "$IN/tl-noconf.json"
mcp_input "$TR/none.jsonl"      "$PROJ"   mcp__chat__create_draft "$TL_DRAFT" > "$IN/tl-notr.json"

# tool-result-check (結果がテキストの配列の場合と、オブジェクトの場合)
tc_noid_text='{"link":"https://chat.example.com/R1","result":"created"}'
tc_id_text='{"link":"https://chat.example.com/R1","created_id":"X0ABC123","result":"created"}'
tc_id_spaced='{"link": "https://chat.example.com/R1", "created_id": "X0ABC123", "result": "created"}'
tc_noid_blocks=$(jq -cn --arg t "$tc_noid_text" '[{type:"text",text:$t}]')
tc_id_blocks=$(jq -cn --arg t "$tc_id_text" '[{type:"text",text:$t}]')
tc_id_spaced_blocks=$(jq -cn --arg t "$tc_id_spaced" '[{type:"text",text:$t}]')
post_input "$PROJ"   mcp__chat__create_draft "$tc_noid_blocks"      > "$IN/tc-noid.json"
post_input "$PROJ"   mcp__chat__create_draft "$tc_id_blocks"        > "$IN/tc-id.json"
post_input "$PROJ"   mcp__chat__create_draft "$tc_id_spaced_blocks" > "$IN/tc-spaced.json"
post_input "$PROJ"   mcp__chat__create_draft "$tc_id_text"          > "$IN/tc-obj.json"
post_input "$PROJ"   mcp__chat__create_draft "$tc_noid_text"        > "$IN/tc-objnoid.json"
post_input "$PROJ"   mcp__chat__read_thread  "$tc_noid_blocks"      > "$IN/tc-nontarget.json"
post_input "$NOCONF" mcp__chat__create_draft "$tc_noid_blocks"      > "$IN/tc-noconf.json"
jq -c 'del(.tool_response)' "$IN/tc-id.json"                        > "$IN/tc-nores.json"

# no-inline-powershell
stop_input "$TR/ps-block.jsonl"  "$PROJ"   false > "$IN/ps-block.json"
stop_input "$TR/ps-block.jsonl"  "$PROJ/project-a/docs" false > "$IN/ps-cwd-hit.json"
stop_input "$TR/ps-block.jsonl"  "$PROJ/other"      false > "$IN/ps-cwd-miss.json"
stop_input "$TR/ps-spaced.jsonl" "$PROJ"   false > "$IN/ps-spaced.json"
stop_input "$TR/rq-p8ok.jsonl"   "$PROJ"   false > "$IN/ps-none.json"
stop_input "$TR/ps-block.jsonl"  "$NOCONF" false > "$IN/ps-noconf.json"

# ---------------------------------------------------------------------------
# 判定
# ---------------------------------------------------------------------------
pass=0
fail=0

verdict() { # verdict <名前> <期待> <実際> <PASS|FAIL>
  if [[ "$4" == PASS ]]; then pass=$((pass+1)); else fail=$((fail+1)); fi
  printf '%-56s 期待=%s 実際=%s %s\n' "$1" "$2" "$3" "$4"
}

run() { # run <名前> <期待 exit> <hook> <config> <input> [期待メッセージ断片]
  local name="$1" exp="$2" hook="$3" cfg="$4" inp="$5" want="${6:-}" err rc=0 v
  err=$(env -u CLAUDE_PROJECT_DIR HARNESS_CONFIG="$cfg" bash "$H/$hook" < "$inp" 2>&1 >/dev/null) || rc=$?
  v=PASS
  [[ "$rc" == "$exp" ]] || v=FAIL
  # パイプ (printf | grep -q) は使わない。pipefail の下では、grep が先に閉じると printf が
  # 失敗し、文言が出ていても不一致と判定することがある
  if [[ -n "$want" && "$err" != *"$want"* ]]; then v=FAIL; fi
  verdict "$name" "$exp" "$rc" "$v"
  if [[ "$v" == FAIL && -n "$err" ]]; then printf '%s\n' "$err" | head -6 | sed 's/^/      /'; fi
}

check() { # check <名前> <期待値> <実際値>
  local v=PASS
  [[ "$3" == "$2" ]] || v=FAIL
  verdict "$1" "$2" "$3" "$v"
}

exists() { if [[ -f "$1" ]]; then echo yes; else echo no; fi; }
lines() { grep -c . "$1" 2>/dev/null || echo 0; }

echo "== response-quality (既定で有効な 4 パターン) =="
rm -f "$LOG"
run "RQ-1 パターン3 ひな形の完了扱い -> block" 2 response-quality.sh "$CFG" "$IN/rq-p3.json" "ひな形・叩きを完了扱い"
run "RQ-2 パターン3 報告書は完了扱いでない -> pass" 0 response-quality.sh "$CFG" "$IN/rq-p3ok.json"
run "RQ-3 パターン4 組版記号 -> block" 2 response-quality.sh "$CFG" "$IN/rq-p4.json" "組版記号濫用"
run "RQ-4 パターン4 記号なし -> pass" 0 response-quality.sh "$CFG" "$IN/rq-p4ok.json"
run "RQ-5 パターン8 空約束 -> block" 2 response-quality.sh "$CFG" "$IN/rq-p8.json" "以後注意します"
run "RQ-6 パターン8 実行結果の報告 -> pass" 0 response-quality.sh "$CFG" "$IN/rq-p8ok.json"
run "RQ-7 パターン19 資料本文を引かずに不在を断定 -> block" 2 response-quality.sh "$CFG" "$IN/rq-p19-doc.json" "資料の不在を断定"
run "RQ-8 パターン19 資料の見出し・目次を引いた -> pass" 0 response-quality.sh "$CFG" "$IN/rq-p19-docok.json"
run "RQ-9 パターン19 出典を引かずに認識を否定 -> block" 2 response-quality.sh "$CFG" "$IN/rq-p19-dis.json" "認識を否定"
run "RQ-10 パターン19 出典を引いた -> pass" 0 response-quality.sh "$CFG" "$IN/rq-p19-disok.json"

echo
echo "== response-quality (パターンの選択と境界) =="
run "RQ-11 既定では パターン5 を実行しない -> pass" 0 response-quality.sh "$CFG" "$IN/rq-p5.json"
run "RQ-12 patterns=[5,18] で文末の装飾語 -> block" 2 response-quality.sh "$P518" "$IN/rq-p5.json" "装飾語"
run "RQ-13 文中の「落ちる」は文末でない -> pass" 0 response-quality.sh "$P518" "$IN/rq-p5ok.json"
run "RQ-14 行頭の定型句 -> block" 2 response-quality.sh "$P518" "$IN/rq-p18.json" "前置き・自己評価"
run "RQ-15 文中の定型句は対象外 -> pass" 0 response-quality.sh "$P518" "$IN/rq-p18ok.json"

echo
echo "== response-quality (記録・バイパス・上限) =="
rm -f "$LOG"
run "RQ-16 検知ログを残す -> block" 2 response-quality.sh "$CFG" "$IN/rq-p8.json" "以後注意します"
check "RQ-16a 検知ログの非空行数" 1 "$(lines "$LOG")"
if command -v python3 >/dev/null 2>&1; then
  utf8=$(python3 - "$LOG" <<'PY'
import sys
try:
    s = open(sys.argv[1], 'rb').read().decode('utf-8')
except Exception:
    print('NG'); raise SystemExit(0)
print('OK' if [l for l in s.split('\n') if l.strip()] else 'NG')
PY
)
  check "RQ-16b 検知ログが UTF-8 として decode 可能" OK "$utf8"
else
  printf '%-56s %s\n' "RQ-16b 検知ログが UTF-8 として decode 可能" "SKIP (python3 なし)"
fi
check "RQ-16c 検知ログに session / input のタグ" 1 "$(grep -c '\[session:.*\] \[input:.*\]' "$LOG" 2>/dev/null || echo 0)"

run "RQ-17 バイパスの文字列だけの行 -> pass" 0 response-quality.sh "$CFG" "$IN/rq-bypass.json"
check "RQ-17a 検知ログは pass で増えない" 1 "$(lines "$LOG")"
run "RQ-18 再生成で uuid が取れない -> pass" 0 response-quality.sh "$CFG" "$IN/rq-active.json"
run "RQ-19 空白入り JSON の user 行を区切りに使う -> pass" 0 response-quality.sh "$CFG" "$IN/rq-spaced.json"
run "RQ-20 enabled:false -> pass" 0 response-quality.sh "$PROJ/.claude/harness-off.json" "$IN/rq-p8.json"

# CLAUDE_PROJECT_DIR 優先の確認
rm -f "$CPD_LOG"
CLAUDE_PROJECT_DIR="$CPD" HARNESS_CONFIG="$CFG" bash "$H/response-quality.sh" < "$IN/rq-p8.json" >/dev/null 2>&1 || true
check "RQ-21 CLAUDE_PROJECT_DIR が logPath の基点" yes "$(exists "$CPD_LOG")"

# 環境変数 HARNESS_DETECTIONS_LOG が logPath より優先する (replay.sh の隔離に使う)
rm -f "$LOG" "$W/rq-envlog.log"
HARNESS_DETECTIONS_LOG="$W/rq-envlog.log" env -u CLAUDE_PROJECT_DIR HARNESS_CONFIG="$CFG" \
  bash "$H/response-quality.sh" < "$IN/rq-p8.json" >/dev/null 2>&1 || true
check "RQ-27 HARNESS_DETECTIONS_LOG へ書き、logPath へは書かない" "yes no" \
  "$(exists "$W/rq-envlog.log") $(exists "$LOG")"

# 同じ入力への差し戻しの上限 (regenLimitPerInput=3)
rm -f "$REGEN_LOG"
rq_run() { # rq_run <設定> <入力> -> 終了コードを出す
  local rc=0
  env -u CLAUDE_PROJECT_DIR HARNESS_CONFIG="$1" bash "$H/response-quality.sh" < "$2" >/dev/null 2>&1 || rc=$?
  echo "$rc"
}
REGEN_CFG="$REGEN/.claude/harness.json"
check "RQ-22 初回 -> block"                     2 "$(rq_run "$REGEN_CFG" "$IN/rq-regen1.json")"
check "RQ-23 再生成 1 回目 -> block"            2 "$(rq_run "$REGEN_CFG" "$IN/rq-regen2.json")"
check "RQ-24 再生成 2 回目 -> block"            2 "$(rq_run "$REGEN_CFG" "$IN/rq-regen2.json")"
check "RQ-25 再生成 3 回目 (上限到達) -> pass"  0 "$(rq_run "$REGEN_CFG" "$IN/rq-regen2.json")"
check "RQ-26 [regen-limit] の行数"              1 "$(grep -c 'regen-limit' "$REGEN_LOG" 2>/dev/null || echo 0)"

echo
echo "== cloud-change-check =="
run "CG-1 変更系 (承認・手順書なし) -> block" 2 cloud-change-check.sh "$CFG" "$IN/cg-create.json" "[change-go: project-a]"
run "CG-2 read-only なコマンド -> pass" 0 cloud-change-check.sh "$CFG" "$IN/cg-list.json"
run "CG-3 承認の文字列だけの行 + 手順書 Read -> pass" 0 cloud-change-check.sh "$CFG" "$IN/cg-go.json"
run "CG-4 手順書は Write しただけ -> block" 2 cloud-change-check.sh "$CFG" "$IN/cg-writeonly.json" "直近で手順書"
run "CG-5 承認の文字列が質問文の中 -> block" 2 cloud-change-check.sh "$CFG" "$IN/cg-inline.json" "[change-go: project-a]"
run "CG-6 設定ファイルなし -> pass" 0 cloud-change-check.sh "$NOCFG" "$IN/cg-noconf.json"
run "CG-7 examples 設定 + cwd project-a -> block" 2 cloud-change-check.sh "$EX" "$IN/cg-example.json" "[change-go: project-a]"
run "CG-8 examples 設定 + npx cdk deploy -> block" 2 cloud-change-check.sh "$EX" "$IN/cg-cdk.json" "[change-go: project-b]"
run "CG-9 cdk watch -> block" 2 cloud-change-check.sh "$EX" "$IN/cg-cdkwatch.json" "[change-go: project-b]"
run "CG-10 aws s3 sync --delete -> block" 2 cloud-change-check.sh "$EX" "$IN/cg-s3sync.json" "[change-go: project-b]"
run "CG-11 aws cloudformation deploy -> block" 2 cloud-change-check.sh "$EX" "$IN/cg-cfndeploy.json" "[change-go: project-b]"
run "CG-12 aws lambda invoke -> pass" 0 cloud-change-check.sh "$EX" "$IN/cg-invoke.json"
run "CG-13 どの案件にも一致しない変更系 -> block (設定不足)" 2 cloud-change-check.sh "$EX" "$IN/cg-nomatch.json" "設定不足"
run "CG-14 cwd が project-a-old は一致しない -> block (設定不足)" 2 cloud-change-check.sh "$EX" "$IN/cg-suffix.json" "設定不足"
run "CG-15 ローカル CLI 設定 -> pass (除外)" 0 cloud-change-check.sh "$CFG" "$IN/cg-acct.json"
run "CG-16 az group show --query set -> pass" 0 cloud-change-check.sh "$CFG" "$IN/cg-query.json"
run "CG-17 echo az group create -> pass" 0 cloud-change-check.sh "$CFG" "$IN/cg-echo.json"

echo
echo "== harness-change-check =="
run "HG-1 .claude/rules/ を Write (承認なし) -> block" 2 harness-change-check.sh "$CFG" "$IN/hg-write.json" "[harness-go]"
run "HG-2 Bash のリダイレクト先が .claude/ -> block" 2 harness-change-check.sh "$CFG" "$IN/hg-bash.json" "[harness-go]"
run "HG-3 .claude/ からのコピー (読み取り) -> pass" 0 harness-change-check.sh "$CFG" "$IN/hg-read.json"
run "HG-4 承認の文字列だけの行 -> pass" 0 harness-change-check.sh "$CFG" "$IN/hg-go.json"
run "HG-5 承認の文字列が質問文の中 -> block" 2 harness-change-check.sh "$CFG" "$IN/hg-inline.json" "[harness-go]"
run "HG-6 除外パス (.claude/projects/) -> pass" 0 harness-change-check.sh "$CFG" "$IN/hg-proj.json"
run "HG-7 初期化の cp (プラグイン配下から) -> pass" 0 harness-change-check.sh "$CFG" "$IN/hg-initcp.json"
run "HG-8 mkdir は書き換えに数えない -> pass" 0 harness-change-check.sh "$CFG" "$IN/hg-mkdir.json"
run "HG-9 harness.json の新規作成 -> pass" 0 harness-change-check.sh "$CFG" "$IN/hg-initcfg.json"
run "HG-10 既存の harness.json の書き換え -> block" 2 harness-change-check.sh "$CFG" "$IN/hg-existcfg.json" "[harness-go]"
run "HG-11 enabled:false -> pass" 0 harness-change-check.sh "$PROJ/.claude/harness-hgoff.json" "$IN/hg-write.json"

echo
echo "== draft-precheck =="
run "DP-1 対象パス + 絶対パス -> block" 2 draft-precheck.sh "$CFG" "$IN/dp-abs.json" "絶対パス検出"
run "DP-2 除外パターン (-internal-) -> pass" 0 draft-precheck.sh "$CFG" "$IN/dp-excl.json"
run "DP-3 対象パス + 問題なし -> pass" 0 draft-precheck.sh "$CFG" "$IN/dp-clean.json"
run "DP-4 URL 中の docs/ は内部パスでない -> pass" 0 draft-precheck.sh "$CFG" "$IN/dp-url.json"
run "DP-5 禁止語 + 見出し敬称抜け -> block" 2 draft-precheck.sh "$CFG" "$IN/dp-hon.json" "禁止語"
run "DP-6 checks.internalPaths=false -> pass" 0 draft-precheck.sh "$DPOFF" "$IN/dp-abs.json"
run "DP-7 対象外パス -> pass" 0 draft-precheck.sh "$CFG" "$IN/dp-nontarget.json"
run "DP-8 設定ファイルなし -> pass" 0 draft-precheck.sh "$NOCFG" "$IN/dp-noconf.json"
run "DP-9 examples 設定 (honorific 空) -> pass" 0 draft-precheck.sh "$EX" "$IN/dp-hon.json"

echo
echo "== draft-precheck (MCP ツールの本文) =="
run "DM-1 下書きのツール + 本文に絶対パス -> block" 2 draft-precheck.sh "$CFG" "$IN/dm-abs.json" "絶対パス検出"
run "DM-2 下書きのツール + 件名に禁止語 -> block" 2 draft-precheck.sh "$CFG" "$IN/dm-term.json" "禁止語"
run "DM-3 下書きのツール + 問題なし -> pass" 0 draft-precheck.sh "$CFG" "$IN/dm-clean.json"
run "DM-4 htmlBody だけにある絶対パスは対象外 -> pass" 0 draft-precheck.sh "$CFG" "$IN/dm-html.json"
run "DM-5 toolRules に無いツール -> pass" 0 draft-precheck.sh "$CFG" "$IN/dm-nontarget.json"
run "DM-6 本文が無い呼び出し (requiredFields なし) -> pass" 0 draft-precheck.sh "$CFG" "$IN/dm-nocontent-opt.json"
run "DM-7 必須の引数 (requiredFields) が無い呼び出し -> block" 2 draft-precheck.sh "$CFG" "$IN/dm-nocontent-req.json" "必須の項目"
run "DM-8 バイパスの文字列だけの行 -> pass" 0 draft-precheck.sh "$CFG" "$IN/dm-bypass.json"
run "DM-9 examples 設定 (toolRules なし) -> pass" 0 draft-precheck.sh "$EX" "$IN/dm-abs.json"
run "DM-10 targets が空で toolRules だけある -> block" 2 draft-precheck.sh "$DPTOOLONLY" "$IN/dm-abs.json" "絶対パス検出"
run "DM-11 tool が正規表現として読めない -> block" 2 draft-precheck.sh "$DPBADRE" "$IN/dm-abs.json" "正規表現として読めません"
run "DM-12 設定ファイルなし -> pass" 0 draft-precheck.sh "$NOCFG" "$IN/dm-noconf.json"
run "DM-13 Write の既存の検査は変わらない (toolRules あり) -> block" 2 draft-precheck.sh "$CFG" "$IN/dp-abs.json" "絶対パス検出"
run "DM-14 tool_input が配列 -> block" 2 draft-precheck.sh "$CFG" "$IN/dm-arr.json" "オブジェクトではない"
run "DM-15 tool_input が文字列 -> block" 2 draft-precheck.sh "$CFG" "$IN/dm-str.json" "オブジェクトではない"
run "DM-16 tool_input が null (requiredFields なし) -> pass" 0 draft-precheck.sh "$CFG" "$IN/dm-null.json"
run "DM-17 fields が文字列 -> block" 2 draft-precheck.sh "$DPFSTR" "$IN/dm-abs.json" "形が正しくありません"
run "DM-18 fields が空配列 -> block" 2 draft-precheck.sh "$DPFEMPTY" "$IN/dm-abs.json" "形が正しくありません"
run "DM-19 fields に文字列以外 -> block" 2 draft-precheck.sh "$DPFNUM" "$IN/dm-abs.json" "形が正しくありません"
run "DM-20 fields で引数名を指定 + 該当の引数に絶対パス -> block" 2 draft-precheck.sh "$DPCUSTOM" "$IN/dm-custom-hit.json" "絶対パス検出"
run "DM-21 fields で引数名を指定 + 別の引数だけに絶対パス -> pass" 0 draft-precheck.sh "$DPCUSTOM" "$IN/dm-custom-miss.json"
run "DM-22 tool の正規表現は jq の test() (\\d) -> block" 2 draft-precheck.sh "$DPDIGIT" "$IN/dm-digit.json" "絶対パス検出"
run "DM-23 toolRules キーが無い設定 + MCP -> pass" 0 draft-precheck.sh "$DPNOKEY" "$IN/dm-abs.json"
run "DM-24 toolRules キーが無い設定 + Write -> block" 2 draft-precheck.sh "$DPNOKEY" "$IN/dp-abs.json" "絶対パス検出"
run "DM-25 MultiEdit の検査は変わらない -> block" 2 draft-precheck.sh "$CFG" "$IN/dm-multiedit.json" "絶対パス検出"
run "DM-26 htmlBody だけの呼び出し (requiredFields なし) は検査されない -> pass" 0 draft-precheck.sh "$CFG" "$IN/dm-htmlonly.json"
run "DM-27 htmlBody だけの呼び出し (requiredFields:[body]) -> block" 2 draft-precheck.sh "$DPREQ" "$IN/dm-htmlonly.json" "必須の項目 body"
run "DM-28 subject があり body が無く htmlBody だけ (requiredFields なし) -> pass" 0 draft-precheck.sh "$CFG" "$IN/dm-subj-html.json"
run "DM-29 subject があり body が無く htmlBody だけ (requiredFields:[body]) -> block" 2 draft-precheck.sh "$DPREQ" "$IN/dm-subj-html.json" "必須の項目 body"
run "DM-30 body が空白だけ (requiredFields:[body]) -> block" 2 draft-precheck.sh "$DPREQ" "$IN/dm-blank-body.json" "必須の項目 body"
run "DM-31 body があり問題なし (requiredFields:[body]) -> pass" 0 draft-precheck.sh "$DPREQ" "$IN/dm-clean.json"
run "DM-32 toolRules が文字列 + MCP -> block" 2 draft-precheck.sh "$DPSHAPE1" "$IN/dm-abs.json" "形が正しくありません"
run "DM-33 toolRules の要素が数値 + MCP -> block" 2 draft-precheck.sh "$DPSHAPE2" "$IN/dm-abs.json" "形が正しくありません"
run "DM-34 toolRules の要素に tool が無い + MCP -> block" 2 draft-precheck.sh "$DPSHAPE3" "$IN/dm-abs.json" "形が正しくありません"
run "DM-35 requiredFields が文字列 + MCP -> block" 2 draft-precheck.sh "$DPSHAPE4" "$IN/dm-abs.json" "形が正しくありません"
run "DM-36 toolRules が文字列でも Write の検査は動く -> block" 2 draft-precheck.sh "$DPSHAPE1" "$IN/dp-abs.json" "絶対パス検出"

echo
echo "== require-reading =="
run "RR-1 TODO.md を Read なしで Edit -> block" 2 require-reading.sh "$CFG" "$IN/rr-noread.json" "必読資料の先読みの原則"
run "RR-2 直近に TODO.md の Read あり -> pass" 0 require-reading.sh "$CFG" "$IN/rr-read.json"
rm -f "$WORKLOG"
run "RR-3 logs 新規 + Read なし -> block" 2 require-reading.sh "$CFG" "$IN/rr-lognew.json" "新規ログファイル"
run "RR-4 対象外パス -> pass" 0 require-reading.sh "$CFG" "$IN/rr-nontarget.json"
run "RR-5 設定ファイルなし -> pass" 0 require-reading.sh "$NOCFG" "$IN/rr-noconf.json"
touch "$WORKLOG" "$ALT_WORKLOG"
run "RR-6 logs 既存編集 + 自ファイル Read なし -> block" 2 require-reading.sh "$CFG" "$IN/rr-logedit.json" "既存ログファイル"
run "RR-7 logs 既存編集 + 自ファイル Read あり -> pass" 0 require-reading.sh "$CFG" "$IN/rr-logedit2.json"
run "RR-8 同名ログの別パスを Read しただけ -> block" 2 require-reading.sh "$CFG" "$IN/rr-logalt.json" "既存ログファイル"

echo
echo "== require-reading (ツールの規則) =="
run "RT-1 スレッドを読まずに下書きのツール -> block" 2 require-reading.sh "$CFG" "$IN/tl-noread.json" "送付先のスレッド を読んでいません"
run "RT-2 同じスレッドを読み、結果を受け取った -> pass" 0 require-reading.sh "$CFG" "$IN/tl-read.json"
run "RT-3 別のスレッドを読んだだけ -> block" 2 require-reading.sh "$CFG" "$IN/tl-other.json" "thread_id=111.222"
run "RT-4 読み取りの結果がまだ返っていない -> block" 2 require-reading.sh "$CFG" "$IN/tl-noresult.json" "送付先のスレッド"
run "RT-5 読み取りがエラーで終わった -> block" 2 require-reading.sh "$CFG" "$IN/tl-error.json" "送付先のスレッド"
run "RT-6 読んだのが依頼者の最後の入力より前 -> block" 2 require-reading.sh "$CFG" "$IN/tl-stale.json" "送付先のスレッド"
run "RT-7 スレッドの指定が無い呼び出しは対象外 -> pass" 0 require-reading.sh "$CFG" "$IN/tl-top.json"
run "RT-8 規則に無いツール -> pass" 0 require-reading.sh "$CFG" "$IN/tl-nontarget.json"
run "RT-9 バイパスの文字列だけの行 -> pass" 0 require-reading.sh "$CFG" "$IN/tl-bypass.json"
run "RT-10 toolRules が空の設定 (examples) -> pass" 0 require-reading.sh "$EX" "$IN/tl-noread.json"
run "RT-11 読み取りの後に isMeta の行 -> pass" 0 require-reading.sh "$CFG" "$IN/tl-meta.json"
run "RT-12 requireReading.enabled:false -> pass" 0 require-reading.sh "$RROFF" "$IN/tl-noread.json"
run "RT-13 先頭の規則が対象外で、次の規則が当たる -> block" 2 require-reading.sh "$TL2" "$IN/tl-top.json" "送付先の部屋 を読んでいません"
run "RT-14 requiredTool の無い規則を飛ばす -> block" 2 require-reading.sh "$TLSKIP" "$IN/tl-noread.json" "送付先のスレッド を読んでいません"
run "RT-15 requiredTool が正規表現として読めない -> block" 2 require-reading.sh "$TLBADRE" "$IN/tl-read.json" "正規表現として読めません"
run "RT-16 transcript が無い -> block" 2 require-reading.sh "$CFG" "$IN/tl-notr.json" "transcript が取得できない"

echo
echo "== tool-result-check =="
run "TC-1 結果のテキストに下書きの ID がない -> 通知" 2 tool-result-check.sh "$CFG" "$IN/tc-noid.json" "下書きの ID がありません"
run "TC-2 結果のテキストに下書きの ID がある -> pass" 0 tool-result-check.sh "$CFG" "$IN/tc-id.json"
run "TC-3 結果がオブジェクトで ID がある -> pass" 0 tool-result-check.sh "$CFG" "$IN/tc-obj.json"
run "TC-4 結果がオブジェクトで ID がない -> 通知" 2 tool-result-check.sh "$CFG" "$IN/tc-objnoid.json" "成立していないものとして"
run "TC-5 規則に無いツール -> pass" 0 tool-result-check.sh "$CFG" "$IN/tc-nontarget.json"
run "TC-6 enabled:false -> pass" 0 tool-result-check.sh "$PROJ/.claude/harness-tcoff.json" "$IN/tc-noid.json"
run "TC-7 rules が空の設定 (examples) -> pass" 0 tool-result-check.sh "$EX" "$IN/tc-noid.json"
run "TC-8 コロンの後に空白のある結果に ID がある -> pass" 0 tool-result-check.sh "$CFG" "$IN/tc-spaced.json"
run "TC-9 successPattern の無い規則を飛ばす -> 通知" 2 tool-result-check.sh "$TLSKIP" "$IN/tc-noid.json" "下書きの ID がありません"
run "TC-10 入力に tool_response が無い -> 通知" 2 tool-result-check.sh "$CFG" "$IN/tc-nores.json" "下書きの ID がありません"

echo
echo "== no-inline-powershell =="
run "PS-1 6 行の powershell ブロック -> block" 2 no-inline-powershell.sh "$CFG" "$IN/ps-block.json" "scripts/{category}/*.ps1"
run "PS-2 空白入り JSON でも検知 -> block" 2 no-inline-powershell.sh "$CFG" "$IN/ps-spaced.json" "scripts/{category}/*.ps1"
run "PS-3 ブロックなし -> pass" 0 no-inline-powershell.sh "$CFG" "$IN/ps-none.json"
run "PS-4 enabled:false -> pass" 0 no-inline-powershell.sh "$PROJ/.claude/harness-psoff.json" "$IN/ps-block.json"
run "PS-5 cwdMatch 一致 -> block" 2 no-inline-powershell.sh "$PROJ/.claude/harness-pscwd.json" "$IN/ps-cwd-hit.json"
run "PS-6 cwdMatch 不一致 -> pass" 0 no-inline-powershell.sh "$PROJ/.claude/harness-pscwd.json" "$IN/ps-cwd-miss.json"

echo
echo "== 設定ファイルなし (全 hook が何もしない) =="
run "NC-1 response-quality -> pass" 0 response-quality.sh "$NOCFG" "$IN/rq-noconf.json"
run "NC-2 no-inline-powershell -> pass" 0 no-inline-powershell.sh "$NOCFG" "$IN/ps-noconf.json"
run "NC-3 cloud-change-check -> pass" 0 cloud-change-check.sh "$NOCFG" "$IN/cg-noconf.json"
run "NC-4 harness-change-check -> pass" 0 harness-change-check.sh "$NOCFG" "$IN/hg-noconf.json"
run "NC-5 draft-precheck -> pass" 0 draft-precheck.sh "$NOCFG" "$IN/dp-noconf.json"
run "NC-6 require-reading -> pass" 0 require-reading.sh "$NOCFG" "$IN/rr-noconf.json"
run "NC-7 require-reading (ツールの規則) -> pass" 0 require-reading.sh "$NOCFG" "$IN/tl-noconf.json"
run "NC-8 tool-result-check -> pass" 0 tool-result-check.sh "$NOCFG" "$IN/tc-noconf.json"

echo
echo "== 設定ファイルが JSON として読めない =="
run "BC-1 PreToolUse (cloud-change) -> block" 2 cloud-change-check.sh "$BROKEN" "$IN/cg-create.json" "設定ファイルが読めません"
run "BC-2 PreToolUse (harness-change) -> block" 2 harness-change-check.sh "$BROKEN" "$IN/hg-write.json" "設定ファイルが読めません"
run "BC-3 PreToolUse (draft-precheck) -> block" 2 draft-precheck.sh "$BROKEN" "$IN/dp-abs.json" "設定ファイルが読めません"
run "BC-4 PreToolUse (require-reading) -> block" 2 require-reading.sh "$BROKEN" "$IN/rr-noread.json" "設定ファイルが読めません"
run "BC-5 Stop (response-quality) -> pass + 通知" 0 response-quality.sh "$BROKEN" "$IN/rq-p8.json" "設定ファイルが読めません"
run "BC-6 Stop (no-inline-powershell) -> pass + 通知" 0 no-inline-powershell.sh "$BROKEN" "$IN/ps-block.json" "設定ファイルが読めません"
run "BC-7 PreToolUse (require-reading のツールの規則) -> block" 2 require-reading.sh "$BROKEN" "$IN/tl-noread.json" "設定ファイルが読めません"
run "BC-8 PostToolUse (tool-result-check) -> pass + 通知" 0 tool-result-check.sh "$BROKEN" "$IN/tc-noid.json" "設定ファイルが読めません"

echo
echo "== replay.sh (過去の記録での再生) =="
# 出力の 1 行: 時刻 / session_id / 行 / hook / ツール / メッセージの 1 行目 (TSV)
rp_count() { # rp_count <出力> <固定文字列>  一致する行数を出す
  grep -cF -- "$2" <<< "$1" || true
}
rm -f "$LOG" "$CPD_LOG"
rp_rc=0
rp_out=$(CLAUDE_PROJECT_DIR="$CPD" bash "$RP" --config "$CFG" --labels "$W/rp-labels.tsv" \
  "$TR/s-rp.jsonl" "$TR/agent-rp1.jsonl" 2>"$W/rp-err") || rp_rc=$?
check "RP-1 再生の終了コード" 0 "$rp_rc"
# 止めた点の節 (hook ごとの件数とラベルの照合表を除く)
rp_blocks=$(sed '/^== hook ごとの件数 ==/,$d' <<< "$rp_out")
check "RP-2 PreToolUse: Read の前の Edit -> block" 1 \
  "$(rp_count "$rp_blocks" $'\ts-rp\t2\trequire-reading\tEdit\t[必読資料の未読]')"
check "RP-3 PreToolUse: Read の後の Edit -> pass" 0 "$(rp_count "$rp_blocks" $'\ts-rp\t6\t')"
check "RP-4 PreToolUse: az の変更系 -> block" 1 \
  "$(rp_count "$rp_blocks" $'\ts-rp\t12\tcloud-change-check\tBash\t')"
check "RP-5 Stop: 空約束の応答 -> block" 1 \
  "$(rp_count "$rp_blocks" $'2026-01-01T00:00:08Z\ts-rp\t8\tresponse-quality\t(Stop)\t')"
check "RP-6 Stop: 差し戻しの後に作り直した応答 -> pass" 0 "$(rp_count "$rp_blocks" $'\ts-rp\t10\t')"
check "RP-7 Stop: 最後の応答 -> pass" 0 "$(rp_count "$rp_blocks" $'\ts-rp\t14\t')"
check "RP-8 hook ごとの件数 (require-reading 3 回中 2 回止めた)" 1 \
  "$(rp_count "$rp_out" $'require-reading\t3\t2\t0')"
check "RP-9 サブエージェントの記録: PreToolUse を流す -> block" 1 \
  "$(rp_count "$rp_blocks" $'\tagent-rp1\t2\trequire-reading\tEdit\t')"
check "RP-10 サブエージェントの記録: Stop は流さない" 0 "$(rp_count "$rp_blocks" $'\tagent-rp1\t4\t')"
check "RP-11 ラベルの照合の件数" 1 "$(rp_count "$rp_out" \
  '件数: 止めるべきを止めた 2 / 止めるべきでないのに止めた 1 / 止めるべきを止めなかった 1 / 止めるべきでないのを通した 1 / 記録に無い 1')"
check "RP-12 ラベル: 時刻で指した Stop を誤って止めた" 1 \
  "$(rp_count "$rp_out" $'止めるべきでないのに止めた\ts-rp\t2026-01-01T00:00:08Z\tpass\tblock\tresponse-quality\t')"
check "RP-13 ラベル: 止めるべきを止めなかった行" 1 \
  "$(rp_count "$rp_out" $'止めるべきを止めなかった\ts-rp\t6\tblock\tpass\t')"
check "RP-14 本物の検知ログ (logPath 相対) に書かない" no "$(exists "$LOG")"
check "RP-15 CLAUDE_PROJECT_DIR の下の検知ログに書かない" no "$(exists "$CPD_LOG")"

rp_rc=0
rp_out=$(bash "$RP" --config "$W/abs-harness.json" --hook response-quality.sh \
  "$TR/s-rp.jsonl" "$TR/s-rp2.jsonl" 2>/dev/null) || rp_rc=$?
check "RP-16 --hook で絞った再生の終了コード" 0 "$rp_rc"
rp_blocks=$(sed '/^== hook ごとの件数 ==/,$d' <<< "$rp_out")
check "RP-17 --hook: 指定した hook だけを流す" "1 0" \
  "$(rp_count "$rp_blocks" $'\ts-rp\t8\tresponse-quality\t(Stop)\t') $(rp_count "$rp_out" 'require-reading')"
check "RP-18 本物の検知ログ (logPath 絶対) の行数が変わらない" 1 "$(lines "$W/abs/real.log")"
check "RP-19 実行の記録あり: 他のセッションからのメッセージで始まった応答 -> block" 1 \
  "$(rp_count "$rp_blocks" $'\ts-rp2\t5\tresponse-quality\t(Stop)\t')"
check "RP-20 実行の記録あり: 実行の記録の無い応答は流さない" 0 "$(rp_count "$rp_blocks" $'\ts-rp2\t11\t')"
check "RP-21 Stop を流した点 (s-rp 3 件 + s-rp2 4 件)" 1 "$(rp_count "$rp_out" 'Stop を流した点 7 件')"

rp_rc=0
bash "$RP" --config "$CFG" --hook tool-result-check "$TR/s-rp.jsonl" >/dev/null 2>&1 || rp_rc=$?
check "RP-22 PostToolUse の hook の名前 -> 1" 1 "$rp_rc"
rp_rc=0
bash "$RP" --config "$CFG" "$TR/none.jsonl" >/dev/null 2>&1 || rp_rc=$?
check "RP-23 記録のファイルが無い -> 1" 1 "$rp_rc"

echo
echo "PASS ${pass} / FAIL ${fail}"
if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
exit 0
