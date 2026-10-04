#!/bin/bash
# クリティカルファイルの編集前に関連資料の Read を強制する hook
# (PreToolUse, matcher=Write|Edit|MultiEdit)
# 外部へ書き込むツールの前に、対応する読み取りのツールを強制する hook
# (PreToolUse, matcher=mcp__.*)
#
# 発火条件 (ファイルの編集):
#   - 編集対象のパスが requireReading.rules[] の target (bash の case パターン) に一致
#     配列順に照合し、最初に一致した要素を使う
#   - cwd には依存しない (リポジトリルート起動のセッションでも発火する)
#
# 通過条件 (ファイルの編集):
#   - 通常: requiredReadPattern に一致する資料を直近 200 行の transcript で Read
#   - mode="logs" の既存ファイル編集: そのファイル自身の Read。判定は cwd 基準で
#     正規化した絶対パスの一致で行う (同名の別ファイルの Read では通さない)
#   - mode="logs" の新規作成: requiredReadPattern に一致する任意のファイルの Read
#
# 発火条件 (ツール):
#   - ツール名が requireReading.toolRules[] の tool (正規表現) に一致し、sameInput の
#     左側の引数がすべて呼び出しにある。配列順に照合し、最初に当てはまった要素を使う
#     (例: スレッドの指定が無い呼び出しは、スレッドを読ませる規則の対象にならない)。
#     requiredTool の無い要素は飛ばす
#
# 通過条件 (ツール):
#   - 依頼者の最後のテキスト入力より後に、名前が requiredTool (正規表現) に一致する
#     ツールを呼び、エラーでない結果を受け取っている
#   - sameInput の各組で、呼び出しの引数 (左) と、読み取りの引数 (右) の値が等しい
#   - 読み取りは依頼者の入力ごとに要る。前の入力のときに読んだ内容は、その後に
#     書き換わっていることがあるため数えない
#
# バイパス:
#   - 依頼者の最後のテキスト入力に [hook-bypass: resource-reading] がそれだけの行としてある
#
# 設定 (.claude/harness.json):
#   requireReading.enabled      false で無効化
#   requireReading.rules[]      target / requiredReadPattern / hint / mode
#   requireReading.toolRules[]  tool / requiredTool / sameInput / hint
#   設定ファイルが無い、または rules と toolRules がどちらも空なら何もしない

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/config.sh"

input=$(cat)
harness_load_config "$input"
harness_config_guard pre

if ! cfg_enabled '.requireReading'; then
  exit 0
fi

rule_count=$(cfg '.requireReading.rules | length' '0')
tool_rule_count=$(cfg '.requireReading.toolRules | length' '0')
if [[ "${rule_count:-0}" -eq 0 && "${tool_rule_count:-0}" -eq 0 ]]; then
  exit 0
fi

# 0) ツールの規則 (ファイルの編集以外のツール)
#    当てはまる規則が無ければ通す。当てはまれば、対応する読み取りの有無で通すか止める。
check_tool_rules() {
  local rule pat want="" required_re="" hint="" transcript last_user_msg hit want_text re_rc

  while IFS= read -r rule; do
    [[ -z "$rule" ]] && continue
    pat=$(printf '%s' "$rule" | jq -r '.tool // empty')
    [[ -z "$pat" ]] && continue
    jq -en --arg n "$tool_name" --arg re "$pat" '$n | test($re)' >/dev/null 2>&1 || continue
    # 読み取りの側で一致を求める引数 {読み取りの引数名: 値}。
    # sameInput の左側の引数が呼び出しに 1 つでも無ければ、この規則は使わない
    want=$(printf '%s' "$input" | jq -c --argjson rule "$rule" '
      (.tool_input // {}) as $in
      | [($rule.sameInput // {}) | to_entries[]
         | {key: .value, value: (($in[.key] // "") | tostring)}]
      | if any(.[]; .value == "") then empty else from_entries end' 2>/dev/null || true)
    [[ -z "$want" ]] && continue
    # requiredTool の無い規則は使わず、次の規則を見る
    required_re=$(printf '%s' "$rule" | jq -r '.requiredTool // empty')
    [[ -z "$required_re" ]] && continue
    hint=$(printf '%s' "$rule" | jq -r '.hint // empty')
    break
  done < <(cfg_list '.requireReading.toolRules[]? | @json')

  [[ -n "$required_re" ]] || return 0
  [[ -n "$hint" ]] || hint="対象"

  # requiredTool が正規表現として読めないと、どの読み取りにも一致せず、常に止まる。
  # 原因が分かるように、設定の誤りとして知らせて止める (jq の終了コード 0 / 1 は式として有効)
  re_rc=0
  jq -en --arg re "$required_re" '"" | test($re)' >/dev/null 2>&1 || re_rc=$?
  if [[ "$re_rc" -gt 1 ]]; then
    cat >&2 <<MSG
[必読資料の未読]
設定 requireReading.toolRules の requiredTool が正規表現として読めません: ${required_re}
設定を直すまで、${tool_name} の前に ${hint} を読んだかを確かめられません。
MSG
    exit 2
  fi

  transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
  if [[ -z "$transcript" || ! -f "$transcript" ]]; then
    cat >&2 <<MSG
[必読資料の未読]
transcript が取得できないため、${hint} を読んだかを確認できません。
${hint} を読んでから ${tool_name} を呼び出してください。
MSG
    exit 2
  fi

  last_user_msg=$(harness_last_user_message "$transcript")
  if harness_has_token "$last_user_msg" '[hook-bypass: resource-reading]'; then
    return 0
  fi

  hit=$(harness_tool_uses_since_user "$transcript" \
    | jq -c --arg re "$required_re" --argjson want "$want" '
        select(.done and (.name | test($re)))
        | . as $u
        | select([$want | to_entries[] | (($u.input[.key] // "") | tostring) == .value] | all)' \
        2>/dev/null | head -1 || true)
  if [[ -n "$hit" ]]; then
    return 0
  fi

  want_text=$(printf '%s' "$want" | jq -r 'to_entries | map("\(.key)=\(.value)") | join(", ")' 2>/dev/null || true)
  cat >&2 <<MSG
[必読資料の未読]
${tool_name} を呼ぼうとしていますが、依頼者の最後の入力より後に ${hint} を読んでいません。

通す条件: 名前が ${required_re} に一致するツールを先に呼び、結果を受け取っていること
読み取りの引数: ${want_text:-指定なし}

対象を読み、内容を踏まえてから再度呼び出してください。
緊急時のみ [hook-bypass: resource-reading] だけの行で回避できます。
MSG
  exit 2
}

tool_name=$(printf '%s' "$input" | jq -r '.tool_name // empty')
case "$tool_name" in
  ""|Write|Edit|MultiEdit) : ;;
  *)
    if [[ "${tool_rule_count:-0}" -gt 0 ]]; then
      check_tool_rules
    fi
    exit 0
    ;;
esac
if [[ "${rule_count:-0}" -eq 0 ]]; then
  exit 0
fi

# 1) cwd 取得 (相対パス解決にのみ使用。cwd では発火制限しない)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')

# パスを cwd 基準の絶対パスへ正規化する (`/./` と重複スラッシュ、末尾の `/` を畳む)
# シンボリックリンクと `..` は解決しない (存在しないファイルも扱うため)
normalize_path() {
  local p="$1"
  case "$p" in
    /*) : ;;
    "~/"*) p="${HOME}/${p#\~/}" ;;
    *) p="${cwd:-$PWD}/$p" ;;
  esac
  printf '%s' "$p" | sed -E 's#/\./#/#g; s#/+#/#g; s#(.)/$#\1#'
}

# 2) 編集対象ファイルパス抽出
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // empty')
if [[ -z "$file_path" ]]; then
  exit 0
fi

target_file_path=$(normalize_path "$file_path")

# 3) クリティカル判定 (target_file_path で cwd 非依存に判定)
related_pattern=""
target_name=""
is_logs=0

while IFS= read -r rule; do
  [[ -z "$rule" ]] && continue
  pat=$(printf '%s' "$rule" | jq -r '.target // empty')
  [[ -z "$pat" ]] && continue
  case "$target_file_path" in
    $pat)
      related_pattern=$(printf '%s' "$rule" | jq -r '.requiredReadPattern // empty')
      target_name=$(printf '%s' "$rule" | jq -r '.hint // empty')
      [[ "$(printf '%s' "$rule" | jq -r '.mode // empty')" == "logs" ]] && is_logs=1
      break
      ;;
  esac
done < <(cfg_list '.requireReading.rules[]? | @json')

if [[ -z "$related_pattern" ]]; then
  exit 0
fi
[[ -n "$target_name" ]] || target_name="対象資料"

# 4) transcript 取得
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
if [[ -z "$transcript" || ! -f "$transcript" ]]; then
  cat >&2 <<MSG
[必読資料の未読]
transcript が取得できないため、直近の資料参照を確認できません。
新規セッションでは、最初に対象資料 (${target_name}) を Read してから編集してください。
MSG
  exit 2
fi

# 5) バイパス判定 (それだけの行にある場合のみ有効)
last_user_msg=$(harness_last_user_message "$transcript")
if harness_has_token "$last_user_msg" '[hook-bypass: resource-reading]'; then
  exit 0
fi

# 6) Read 済みファイル一覧 (直近 200 行)
read_files=$(tail -200 "$transcript" \
  | jq -rR -n '[inputs | fromjson? // empty] | .[]
      | select(.type=="assistant") | .message.content[]?
      | select(.type=="tool_use" and .name=="Read")
      | .input.file_path // .input.path // empty' 2>/dev/null || true)

# 7) logs 特例 (既存編集 vs 新規作成で分岐)
if [[ "$is_logs" -eq 1 ]]; then
  if [[ -f "$target_file_path" ]]; then
    # 既存ファイル編集: 対象ファイル自身の Read が必要 (絶対パスの一致で判定する。
    # ファイル名だけの一致では、同名の別ファイルを読んだだけで通ってしまう)
    self_read=""
    while IFS= read -r read_path; do
      [[ -z "$read_path" ]] && continue
      if [[ "$(normalize_path "$read_path")" == "$target_file_path" ]]; then
        self_read="$read_path"
        break
      fi
    done <<< "$read_files"

    if [[ -n "$self_read" ]]; then
      exit 0
    fi

    cat >&2 <<MSG
[必読資料の未読]
既存ログファイル ${file_path} を編集しようとしていますが、
このファイル自身を直近で Read していません。

追記前にファイル内容を確認してください。
緊急時のみ [hook-bypass: resource-reading] だけの行で回避できます。
MSG
    exit 2
  else
    # 新規作成: 同じ資料群の任意の Read で OK
    logs_dir_read=$(printf '%s\n' "$read_files" | grep -E -- "$related_pattern" || true)
    if [[ -n "$logs_dir_read" ]]; then
      exit 0
    fi

    cat >&2 <<MSG
[必読資料の未読]
新規ログファイル ${file_path} を作成しようとしていますが、
直近で ${target_name} 配下の既存ログを Read していません。

前回までの作業記録を確認してから新規ログを作成してください。
緊急時のみ [hook-bypass: resource-reading] だけの行で回避できます。
MSG
    exit 2
  fi
else
  # 8) 通常: 関連資料の Read チェック
  related_read=$(printf '%s\n' "$read_files" | grep -E -- "$related_pattern" || true)
  if [[ -n "$related_read" ]]; then
    exit 0
  fi

  cat >&2 <<MSG
[必読資料の未読]
${file_path} を編集しようとしていますが、
直近で ${target_name} 配下の資料を Read していません。

必読資料の先読みの原則:
- 該当セクションが参照する資料の本文を先に読む (ファイル名で判断しない)
- 最初に「読むべき資料リスト」を提示 → ユーザー確認 → 編集/提示

対象資料を Read してから再度編集を試みてください。
緊急時のみ [hook-bypass: resource-reading] だけの行で回避できます。
MSG
  exit 2
fi
