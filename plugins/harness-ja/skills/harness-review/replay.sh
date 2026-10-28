#!/bin/bash
# harness-ja: hook の変更案を、過去の会話の記録 (Claude Code の transcript JSONL) で試す。
# harness-review Skill から呼ぶ。
#
# 使い方:
#   replay.sh [--config <harness.json>] [--labels <labels.tsv>] [--hook <hook名>]... <transcript.jsonl>...
#   --config  流すときの設定ファイル。一時ディレクトリへ写してから使う (元のファイルは読むだけ)。
#             省略時は、最初の記録に残る cwd から上へ辿って最初に見つかる .claude/harness.json
#   --labels  人が付けた正誤のラベル (TSV)。列は session_id、時刻か行番号、expected (block か
#             pass)、メモ。# で始まる行と空行、1 列目が session_id の見出しの行は読み飛ばす。
#             指定すると、ラベルの行ごとに期待どおりかを表にし、件数を出す
#   --hook    流す hook を名前で絞る (例: response-quality。.sh は付けても付けなくてもよい)。
#             複数回指定できる。省略時は hooks.json の PreToolUse と Stop の hook をすべて流す
#
# 流す hook は、このスクリプトと同じプラグインの hooks/hooks.json と hooks/*.sh。
# hook を変える案を試すときは、変更を入れたプラグインの写しにある replay.sh を実行する。
#
# 再生のしかた:
#   PreToolUse  記録の中のツール呼び出しのうち、名前が hooks.json の PreToolUse の matcher
#               (名前の全体に当てる正規表現として扱う) に一致するものごとに、その行までの記録を
#               一時ファイルへ切り出し、hook の入力 (session_id / transcript_path / cwd /
#               hook_event_name / tool_name / tool_input / tool_use_id) を作って流す
#   Stop        Stop の hook が流れた点ごとに、その前の最後の assistant の行までを切り出して
#               流す。Stop が流れた点は次のどちらかで決める:
#                 - 記録に Stop の hook の実行の記録 (type が system、subtype が
#                   stop_hook_summary の行) があれば、その行ごと。他のセッションからの
#                   メッセージ (isMeta) で始まった応答の終わりも拾える
#                 - 無ければ (Stop の hook を入れていない頃の記録)、依頼者の入力
#                   (lib/config.sh の HARNESS_JQ_USER_INPUT と同じ定義) の直前、Stop hook の
#                   差し戻し (isMeta の行で "Stop hook feedback" で始まる行) の直前、記録の
#                   末尾ごと。依頼者の中断 ("[Request interrupted by user" で始まる行) の直前は
#                   除く (Claude Code は中断では Stop の hook を流さない)。要約で続けた
#                   セッションの要約の行と、応答の途中で届いた依頼者の入力の直前も点になるため、
#                   Stop が流れていない点を流すことがある
#               差し戻しの後の生成は stop_hook_active=true で流す。区切りの後ろに assistant の
#               text が無い点は流さない (response-quality.sh は text が空だと 2 秒待ってから
#               通すため、先に除く)
#   終了コード 2 を「止めた」と数える。0 と 2 以外はエラーとして数え、標準エラーへ出す
#
# 隔離 (利用者の本物のログと設定を汚さない):
#   - 設定ファイルは一時ディレクトリへ写し、環境変数 HARNESS_CONFIG で写しを渡す
#   - hook が書き込むのは検知ログ (再生成の回数の集計にも使う) だけ。環境変数
#     HARNESS_DETECTIONS_LOG で一時ディレクトリへ向ける。設定の logPath が絶対パスでも、
#     本物のログには書かない
#   - CLAUDE_PROJECT_DIR は外す。TMPDIR とカレントディレクトリも一時ディレクトリにする
#   - 一時ディレクトリは終了時に消す
#
# 出力:
#   止めた点を 1 行ずつ (TSV): 時刻 / session_id / 行 / hook / ツール / メッセージの 1 行目
#     時刻は記録の timestamp の値、行は記録のファイルの行番号 (1 始まり)。PreToolUse は
#     ツール呼び出しの行、Stop は切り出した最後の assistant の行。Stop のツールは "(Stop)"
#   最後に hook ごとの、流した回数・止めた回数・エラーの件数。--labels を指定したら、
#   ラベルとの照合表と件数
#
# 限界:
#   - ファイルの状態を見る検査は、今のファイルで判定する (過去の時点の状態ではない)。
#     例: require-reading.sh の「既存ログの編集か新規作成か」、harness-change-check.sh の
#     「harness.json の新規作成か」
#   - 過去の設定とプラグインの版は復元しない。--config の設定と、このプラグインの hook で
#     流す。記録の当時に実際に止まったかとは一致しないことがある
#   - 記録の途中から Stop の hook を入れた場合、入れる前の応答では Stop を流さない
#     (stop_hook_summary の行がある記録は、その行だけを Stop の点に使うため)
#   - PostToolUse の hook (tool-result-check.sh) は流さない
#   - サブエージェントの記録: 会話の記録の中で isSidechain が true の行は流さない。
#     サブエージェントの記録 (<セッション>/subagents/agent-*.jsonl) は自動では読まない。
#     引数に渡すと、そのファイルを transcript として PreToolUse だけを流す (Stop は流さない)。
#     session_id の列はファイル名 (agent-<ID>) になる。実際の実行で、サブエージェントの
#     hook に transcript_path としてどちらの記録が渡るかは確かめていない。結果は参考にとどめる
#   - 同じ応答で並べたツール呼び出しは、それぞれの行までを切り出す。実際の実行で hook が
#     動いた時点に、後ろの行がもう書かれていたかは確かめていない

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
HOOKS_JSON="$ROOT/hooks/hooks.json"

die() { printf '%s\n' "$*" >&2; exit 1; }
usage() {
  echo "使い方: replay.sh [--config <harness.json>] [--labels <labels.tsv>] [--hook <hook名>]... <transcript.jsonl>..."
}

command -v jq >/dev/null 2>&1 || die "jq が見つかりません。jq を入れてから再実行してください。"
[[ -f "$HOOKS_JSON" ]] || die "hooks.json が見つかりません: $HOOKS_JSON"
[[ -f "$ROOT/hooks/lib/config.sh" ]] || die "hooks/lib/config.sh が見つかりません: $ROOT/hooks/lib/config.sh"
# 依頼者の入力の判定 (HARNESS_JQ_USER_INPUT) を hook と同じ定義で使う
# shellcheck source=../../hooks/lib/config.sh
source "$ROOT/hooks/lib/config.sh"

config=""; labels=""; sel=(); transcripts=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) [[ $# -ge 2 ]] || die "--config の値がありません"; config="$2"; shift 2 ;;
    --labels) [[ $# -ge 2 ]] || die "--labels の値がありません"; labels="$2"; shift 2 ;;
    --hook)   [[ $# -ge 2 ]] || die "--hook の値がありません"; sel+=("${2%.sh}"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; transcripts+=("$@"); break ;;
    -*) usage >&2; die "知らないオプションです: $1" ;;
    *) transcripts+=("$1"); shift ;;
  esac
done

[[ ${#transcripts[@]} -gt 0 ]] || { usage >&2; die "会話の記録 (.jsonl) を 1 つ以上渡してください。"; }
for f in "${transcripts[@]}"; do
  [[ -f "$f" ]] || die "会話の記録が見つかりません: $f"
done
if [[ -n "$labels" && ! -f "$labels" ]]; then
  die "ラベルのファイルが見つかりません: $labels"
fi

# ---------------------------------------------------------------------------
# hooks.json から、流す hook を決める
# ---------------------------------------------------------------------------
JQ_HOOK_NAME='def hook_name: ([match("([A-Za-z0-9_.-]+)\\.sh"; "g") | .captures[0].string] | last) // .;'
all_names=$(jq -r "$JQ_HOOK_NAME"'
  [(.hooks.PreToolUse[]?, .hooks.Stop[]?) | .hooks[]? | select(.type == "command") | .command | hook_name]
  | reduce .[] as $n ([]; if any(.[]; . == $n) then . else . + [$n] end) | .[]' "$HOOKS_JSON") \
  || die "hooks.json が読めません: $HOOKS_JSON"
for s in "${sel[@]+"${sel[@]}"}"; do
  if ! grep -qxF -- "$s" <<< "$all_names"; then
    die "hook の名前が hooks.json の PreToolUse と Stop にありません: $s (流せる hook: $(tr '\n' ' ' <<< "$all_names"))"
  fi
done
if [[ ${#sel[@]} -gt 0 ]]; then
  sel_json=$(printf '%s\n' "${sel[@]}" | jq -R . | jq -cs .)
  run_names=$(grep -xF -f <(printf '%s\n' "${sel[@]}") <<< "$all_names")
else
  sel_json='[]'
  run_names="$all_names"
fi
pre_json=$(jq -c '[.hooks.PreToolUse[]? | {matcher: (.matcher // ""),
  commands: [.hooks[]? | select(.type == "command") | .command]}]' "$HOOKS_JSON")
stop_json=$(jq -c '[.hooks.Stop[]? | .hooks[]? | select(.type == "command") | .command]' "$HOOKS_JSON")

# ---------------------------------------------------------------------------
# 設定ファイル (一時ディレクトリへ写して使う)
# ---------------------------------------------------------------------------
if [[ -z "$config" ]]; then
  first_cwd=$(jq -rR 'fromjson? // empty | objects | .cwd // empty' "${transcripts[0]}" 2>/dev/null | head -n 1)
  dir="$first_cwd"
  while [[ -n "$dir" && "$dir" != "/" ]]; do
    if [[ -f "$dir/.claude/harness.json" ]]; then
      config="$dir/.claude/harness.json"
      break
    fi
    dir=$(dirname "$dir")
  done
  [[ -n "$config" ]] || die "設定ファイルが見つかりません (記録の cwd: ${first_cwd:-なし})。--config で渡してください。"
fi
[[ -f "$config" ]] || die "設定ファイルが見つかりません: $config"
jq -e . "$config" >/dev/null 2>&1 || die "設定ファイルが JSON として読めません: $config"

W=$(mktemp -d "${TMPDIR:-/tmp}/harness-replay.XXXXXX") || die "一時ディレクトリを作れません。"
[[ -n "$W" && -d "$W" ]] || die "一時ディレクトリを作れません。"
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/config/.claude" "$W/state" "$W/tmp" "$W/run" "$W/slice"
CFG_COPY="$W/config/.claude/harness.json"
cp "$config" "$CFG_COPY" || die "設定ファイルを写せません: $config"
DETECT_LOG="$W/state/detections.log"
RESULTS="$W/results.tsv"
: > "$RESULTS"

# ---------------------------------------------------------------------------
# 記録から、hook を流す点を取り出す
#   1 行 1 点。欄の区切りは \x1f (空の欄を保つため)、hook のコマンドの区切りは \x1e
#   欄: 行 / 種類 (pre|stop) / 時刻 / 表示用の ID / ファイル名の ID / ツール / コマンド / hook の入力
# ---------------------------------------------------------------------------
JQ_POINTS="$HARNESS_JQ_USER_INPUT$JQ_HOOK_NAME"'
  def selected: ($sel | length) == 0 or (hook_name as $n | $sel | any(.[]; . == $n));
  def is_delim: .type == "user"
    and ((.message.content | type) == "string"
         or ((.message.content | type) == "array"
             and ([.message.content[]? | select(.type == "tool_result")] | length) == 0));
  def is_feedback: .type == "user" and (.isMeta // false) and (user_text | test("^\\s*Stop hook feedback"));
  def is_interrupt: user_text | test("^\\s*\\[Request interrupted by user");
  def has_text: [.message.content[]? | select(.type == "text" and ((.text // "") | length) > 0)] | length > 0;
  def is_stop_summary: .type == "system" and .subtype == "stop_hook_summary";
  def clean: tostring | gsub("[\\t\\n\\r\\x1e\\x1f]"; " ");
  [foreach inputs as $l (0; . + 1; {n: ., o: ($l | fromjson? // null)})]
  | map(select(.o | type == "object")) as $all
  | (if $force_sub then true
     else ([$all[] | .o.isSidechain | select(type == "boolean")] | first // false) end) as $sub
  | ([$all[] | select((.o.isSidechain // false) | not) | .o | select(is_stop_summary)] | length > 0) as $has_summary
  | def point_id($o): if $sub then $base else (($o.sessionId // "") | if . == "" then $base else . end) end;
    ($pre | map({re: (if .matcher == "" or .matcher == "*" then "" else "^(?:" + .matcher + ")$" end),
                 commands: [.commands[] | select(selected)]})) as $groups
  | [$stop[] | select(selected)] as $stopcmds
  | [
      ( $all[] | select(.o.type == "assistant" and ((.o.isSidechain // false) == $sub))
        | .n as $n | .o as $o
        | $o.message.content[]? | select(.type == "tool_use")
        | (.name // "") as $name
        | {line: $n, kind: "pre", ts: ($o.timestamp // ""), id: point_id($o), tool: $name,
           hooks: [$groups[] | select(.re as $re | $name | test($re)) | .commands[]],
           input: {session_id: ($o.sessionId // ""), transcript_path: $slice, cwd: ($o.cwd // ""),
                   hook_event_name: "PreToolUse", tool_name: $name, tool_input: (.input // {}),
                   tool_use_id: (.id // "")}} ),
      ( if $sub then empty else
          # 状態: a = 最後の assistant の行 (text = 区切りの後ろに text があるか、
          #       active = 差し戻しの後の生成か) / tf = 区切りの後ろに text があるか /
          #       fb = 依頼者の最後の入力の後に差し戻しがあったか / used = 点にした最後の行
          def take($skip): if .a != null and .a.n > .used then
              (if $skip or (.a.text | not) then . else .pts += [.a] end) | .used = .a.n
            else . end;
          reduce ($all[] | select((.o.isSidechain // false) | not)) as $e
            ({a: null, tf: false, fb: false, used: 0, pts: []};
             if $e.o.type == "assistant" then
               .tf = (.tf or ($e.o | has_text))
               | .a = {n: $e.n, o: $e.o, text: .tf, active: .fb}
             elif $has_summary and ($e.o | is_stop_summary) then
               take(false)
             elif ($e.o | is_delim) then
               (if ($has_summary | not) and (($e.o | is_user_input) or ($e.o | is_feedback))
                then take($e.o | is_interrupt) else . end)
               | .tf = false
               | (if ($e.o | is_feedback) then .fb = true
                  elif ($e.o | is_user_input) then .fb = false
                  else . end)
             else . end)
          | (if $has_summary then . else take(false) end)
          | .pts[]
          | {line: .n, kind: "stop", ts: (.o.timestamp // ""), id: point_id(.o), tool: "(Stop)",
             hooks: $stopcmds,
             input: {session_id: (.o.sessionId // ""), transcript_path: $slice, cwd: (.o.cwd // ""),
                     hook_event_name: "Stop", stop_hook_active: .active}}
        end )
    ]
  | sort_by(.line, (if .kind == "stop" then 1 else 0 end))
  | .[]
  | [(.line | tostring), .kind, (.ts | clean), (.id | clean), $base, (.tool | clean),
     (.hooks | join("\u001e")), (.input | tojson)]
  | join("\u001f")'

declare -A ran blocked errs
total_files=0; total_tools=0; total_tool_hooked=0; total_stops=0; read_errors=0

run_hook() { # run_hook <コマンド>  結果は hook_rc / hook_msg に入れる
  local cmd="$1"
  local -a guard=()
  command -v timeout >/dev/null 2>&1 && guard=(timeout 60)
  hook_msg=$(cd "$W/run" && env -u CLAUDE_PROJECT_DIR \
      HARNESS_CONFIG="$CFG_COPY" \
      HARNESS_DETECTIONS_LOG="$DETECT_LOG" \
      CLAUDE_PLUGIN_ROOT="$ROOT" \
      TMPDIR="$W/tmp" \
      "${guard[@]+"${guard[@]}"}" bash -c "$cmd" < "$W/input.json" 2>&1 >/dev/null)
  hook_rc=$?
}

hook_name_of() { # hook_name_of <コマンド>
  local base
  base=$(grep -oE '[A-Za-z0-9_.-]+\.sh' <<< "$1" | tail -n 1)
  if [[ -n "$base" ]]; then printf '%s' "${base%.sh}"; else printf '%s' "$1"; fi
}

echo "== 止めた点 =="
printf '時刻\tsession_id\t行\thook\tツール\tメッセージの1行目\n'

for f in "${transcripts[@]}"; do
  total_files=$((total_files + 1))
  base=$(basename "$f" .jsonl)
  force_sub=false
  [[ "$base" == agent-* ]] && force_sub=true
  slice="$W/slice/$(basename "$f")"
  if ! jq -rR -n --argjson sel "$sel_json" --argjson pre "$pre_json" --argjson stop "$stop_json" \
       --arg base "$base" --arg slice "$slice" --argjson force_sub "$force_sub" \
       "$JQ_POINTS" < "$f" > "$W/points"; then
    printf '警告: 会話の記録を読めませんでした: %s\n' "$f" >&2
    read_errors=$((read_errors + 1))
    continue
  fi
  sliced_line=""
  while IFS=$'\x1f' read -r line kind ts id fbase tool hooks_joined input_json; do
    [[ -n "$line" ]] || continue
    if [[ "$kind" == "pre" ]]; then
      total_tools=$((total_tools + 1))
    fi
    blocked_here=""
    if [[ -n "$hooks_joined" ]]; then
      if [[ "$kind" == "pre" ]]; then
        total_tool_hooked=$((total_tool_hooked + 1))
      else
        total_stops=$((total_stops + 1))
      fi
      if [[ "$sliced_line" != "$line" ]]; then
        head -n "$line" "$f" > "$slice"
        sliced_line="$line"
      fi
      printf '%s\n' "$input_json" > "$W/input.json"
      IFS=$'\x1e' read -r -a cmds <<< "$hooks_joined"
      for cmd in "${cmds[@]}"; do
        [[ -n "$cmd" ]] || continue
        name=$(hook_name_of "$cmd")
        run_hook "$cmd"
        ran[$name]=$(( ${ran[$name]:-0} + 1 ))
        first=$(printf '%s\n' "$hook_msg" | awk 'NF {print; exit}')
        if [[ "$hook_rc" -eq 2 ]]; then
          blocked[$name]=$(( ${blocked[$name]:-0} + 1 ))
          blocked_here="${blocked_here:+$blocked_here,}$name"
          printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${ts:--}" "$id" "$line" "$name" "$tool" "${first:--}"
        elif [[ "$hook_rc" -ne 0 ]]; then
          errs[$name]=$(( ${errs[$name]:-0} + 1 ))
          printf '警告: %s が終了コード %s で終わりました (%s 行 %s): %s\n' \
            "$name" "$hook_rc" "$id" "$line" "${first:--}" >&2
        fi
      done
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$fbase" "$line" "${ts:--}" "$kind" "$tool" \
      "${blocked_here:--}" >> "$RESULTS"
  done < "$W/points"
done

echo
echo "== hook ごとの件数 =="
printf 'hook\t流した回数\t止めた回数\tエラー\n'
while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  printf '%s\t%s\t%s\t%s\n' "$name" "${ran[$name]:-0}" "${blocked[$name]:-0}" "${errs[$name]:-0}"
done <<< "$run_names"
echo
echo "記録 ${total_files} 本 / ツール呼び出し ${total_tools} 件 (うち hook を流した ${total_tool_hooked} 件) / Stop を流した点 ${total_stops} 件"

# ---------------------------------------------------------------------------
# ラベルとの照合
# ---------------------------------------------------------------------------
if [[ -n "$labels" ]]; then
  echo
  echo "== ラベルとの照合 =="
  awk -F'\t' -v OFS='\t' '
    function add_hit(k, b,    i, n, parts) {
      hit[k] = 1
      if (b == "-") return
      n = split(b, parts, ",")
      for (i = 1; i <= n; i++) {
        if (index("," blk[k] ",", "," parts[i] ",") == 0) blk[k] = (blk[k] == "" ? parts[i] : blk[k] "," parts[i])
      }
    }
    FNR == NR {
      # 結果: id / ファイル名の ID / 行 / 時刻 / 種類 / ツール / 止めた hook
      add_hit($1 SUBSEP $3, $7); add_hit($2 SUBSEP $3, $7)
      if ($4 != "-") { add_hit($1 SUBSEP $4, $7); add_hit($2 SUBSEP $4, $7) }
      next
    }
    {
      gsub(/\r/, "")
      if ($0 ~ /^[[:space:]]*(#|$)/) next
      if ($1 == "session_id") next
      sid = $1; key = $2; want = $3; memo = $4
      if (want != "block" && want != "pass") {
        printf "警告: ラベルの expected が block でも pass でもありません (%s 行目): %s\n", FNR, want > "/dev/stderr"
        bad++
        next
      }
      k = sid SUBSEP key
      if (!(k in hit)) { verdict = "記録に無い"; act = "-"; hooks = "-"; c_none++ }
      else {
        act = (k in blk) ? "block" : "pass"; hooks = (k in blk) ? blk[k] : "-"
        if (want == "block" && act == "block") { verdict = "止めるべきを止めた"; c_tp++ }
        else if (want == "pass" && act == "block") { verdict = "止めるべきでないのに止めた"; c_fp++ }
        else if (want == "block" && act == "pass") { verdict = "止めるべきを止めなかった"; c_fn++ }
        else { verdict = "止めるべきでないのを通した"; c_tn++ }
      }
      rows[++nrow] = verdict OFS sid OFS key OFS want OFS act OFS hooks OFS memo
    }
    END {
      print "判定", "session_id", "時刻か行", "期待", "実際", "止めた hook", "メモ"
      for (i = 1; i <= nrow; i++) print rows[i]
      print ""
      printf "件数: 止めるべきを止めた %d / 止めるべきでないのに止めた %d / 止めるべきを止めなかった %d / 止めるべきでないのを通した %d / 記録に無い %d", c_tp, c_fp, c_fn, c_tn, c_none
      if (bad > 0) printf " / 読めないラベル %d", bad
      printf "\n"
    }' "$RESULTS" "$labels" || read_errors=$((read_errors + 1))
fi

# 読めなかった記録があるか、ラベルの照合に失敗したら 1 で終える (件数は読めた記録の分)
if [[ "$read_errors" -gt 0 ]]; then
  exit 1
fi
exit 0
