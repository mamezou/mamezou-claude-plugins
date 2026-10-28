#!/bin/bash
# 文面のコードブロックの各行が、会話の記録のどこに出ていたかを表示する。/docs-tools:draft-precheck から呼ばれる。
# 使い方: code-origin.sh <下書きのファイル> [<会話の記録の JSONL>]
# 会話の記録を省くと、今のディレクトリの会話の記録の置き場から、最後に書かれた記録を使う。
# 記録と同じ名前のフォルダの下のサブエージェントの記録も読む。止めない。終了コードは常に 0。

set -uo pipefail

LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../lib" && pwd)
if ! command -v python3 > /dev/null 2>&1; then
  echo "python3 が見つからないため、コードの出どころを表示できません" >&2
  exit 0
fi

DOCS_TOOLS_LIB="$LIB_DIR" python3 -I -B - "$@" << 'PY'
import os
import re
import sys

sys.path.insert(0, os.environ["DOCS_TOOLS_LIB"])
import transcript as tr  # noqa: E402

USAGE = "使い方: code-origin.sh <下書きのファイル> [<会話の記録の JSONL>]"
MIN_CHARS = 4  # 空白を除いた字数がこれより少ない行は、どこにでも出るため判定しない
EVIDENCE = ("依頼者の入力", "ツールの結果", "成功したコマンド", "Claude の応答")


def stop(message):
    print(message)
    sys.exit(0)


args = sys.argv[1:]
if not args or len(args) > 2 or args[0] in ("-h", "--help"):
    stop(USAGE)
draft = args[0]
if not os.path.isfile(draft):
    stop(f"下書きのファイルが見つかりません: {draft}")

if len(args) == 2:
    transcript = args[1]
    if not os.path.isfile(transcript):
        stop(f"会話の記録が見つかりません: {transcript}")
else:
    tdir = tr.transcripts_dir(os.getcwd())
    candidates = tr.main_files(tdir)
    if not candidates:
        stop(f"会話の記録が見つかりません (探した置き場: {tdir})。2 つ目の引数に記録のファイルを渡してください")
    transcript = max(candidates, key=os.path.getmtime)
transcript = os.path.abspath(transcript)
tdir = os.path.dirname(transcript)

# コードブロックの行を取り出す。閉じるのは、開いたフェンスと同じ記号で同じ長さ以上のフェンスだけ
fence_re = re.compile(r"^\s*(`{3,}|~{3,})")
blocks = []
fence = None
with open(draft, encoding="utf-8", errors="replace") as fh:
    for lineno, line in enumerate(fh, 1):
        line = line.rstrip("\r\n")
        match = fence_re.match(line)
        if match:
            mark = match.group(1)
            if fence is None:
                fence = mark
                blocks.append({"start": lineno, "end": lineno, "lines": []})
                continue
            if mark[0] == fence[0] and len(mark) >= len(fence):
                fence = None
                blocks[-1]["end"] = lineno
                continue
        if fence is not None and line.strip():
            blocks[-1]["lines"].append((lineno, line))

print(f"文面: {draft}")
if not any(b["lines"] for b in blocks):
    stop("コードブロックはありません")

# 文面のファイルに触れた呼び出し (書き込み・読み込み・検査) と、その結果は数えない。
# 送付の後に名前から -draft を外す運用があるため、拡張子と末尾の -draft を除いた名前で探す
stem = os.path.basename(draft)
stem = re.sub(r"\.[^.]+$", "", stem)
stem = re.sub(r"-draft$", "", stem) or os.path.basename(draft)

files = [transcript] + tr.subagent_files(tdir, transcript)
records = []
for path in files:
    records.extend(tr.iter_records(path, tdir))

touched = set()
first_touch = None
for rec in records:
    if rec.kind == "tool_use" and stem in rec.text:
        touched.add(rec.tool_id)
        if rec.ts and (first_touch is None or rec.ts < first_touch):
            first_touch = rec.ts

results = {rec.tool_id: rec for rec in records if rec.kind == "tool_result"}
sources = []  # (区分, 失敗かどうか, Record, 正規化した本文)
for rec in records:
    if rec.tool_id in touched:
        continue
    if rec.kind == "user":
        sources.append(("依頼者の入力", False, rec))
    elif rec.kind == "assistant":
        sources.append(("Claude の応答", False, rec))
    elif rec.kind == "tool_result":
        sources.append(("ツールの結果", rec.is_error, rec))
    elif rec.kind == "tool_use":
        result = results.get(rec.tool_id)
        if rec.is_command:
            failed = result is None or result.is_error
            sources.append(("成功したコマンド", failed, rec))
        else:
            sources.append(("Claude の応答", False, rec))
sources = [(cat, failed, rec, tr.normalize(rec.text)) for cat, failed, rec in sources]

print(f"会話の記録: {transcript} (サブエージェントの記録 {len(files) - 1} 件を含む)")
print(f"数えない記録: 文面の名前 ({stem}) を含むツールの呼び出しと、その結果 {len(touched)} 件")
if first_touch:
    print(f"文面の名前を含む最初の呼び出し: {tr.fmt_jst(first_touch)}。この後の記録にだけ出ている区分には「文面を作り始めた後」を付ける")
print("区分: 依頼者の入力 / ツールの結果 (エラーを除く) / 成功したコマンド / Claude の応答 (ほかのツールへの入力を含む)")


def place(rec):
    if rec.agent:
        return f"サブエージェント {rec.agent} の記録の {rec.lineno} 行目"
    return f"{os.path.basename(rec.path)} の {rec.lineno} 行目"


nowhere = []
claude_only = []
failed_only = []
def rank(rec, count):
    """同じ区分の候補から 1 件を選ぶ順。コードブロックの行を多く含む記録、文面に触れる前の記録、早い記録の順"""
    before = first_touch is None or (rec.ts is not None and rec.ts < first_touch)
    stamp = rec.ts.timestamp() if rec.ts else float("inf")
    return (-count, not before, stamp)


for number, block in enumerate(blocks, 1):
    if not block["lines"]:
        continue
    print()
    print(f"[コードブロック {number}: {block['start']}〜{block['end']} 行目]")
    targets = {}
    for lineno, line in block["lines"]:
        target = tr.normalize(line)
        if len(target.replace(" ", "")) >= MIN_CHARS:
            targets[lineno] = target
    # 記録ごとに、このコードブロックの判定する行を何行含むかを数える。1 語だけの行は、
    # 検索の語など別の文脈でも出るため、ほかの行も含む記録を優先して示す
    contains = []
    for cat, failed, rec, text in sources:
        hit = {n for n, target in targets.items() if target in text}
        if hit:
            contains.append((cat, failed, rec, hit))
    for lineno, line in block["lines"]:
        print(f"{lineno}: {line}")
        if lineno not in targets:
            print("    (短い行のため判定しない)")
            continue
        found = {}
        failed_hit = None
        for cat, failed, rec, hit in contains:
            if lineno not in hit:
                continue
            if failed:
                if failed_hit is None or rank(rec, len(hit)) < rank(*failed_hit):
                    failed_hit = (rec, len(hit))
                continue
            if cat not in found or rank(rec, len(hit)) < rank(*found[cat]):
                found[cat] = (rec, len(hit))
        if not found:
            if failed_hit is not None:
                failed_only.append(lineno)
                rec = failed_hit[0]
                print(f"    どこにも出ていない (失敗したコマンドかエラーの結果にはある: {tr.fmt_jst(rec.ts)} {rec.label()} {place(rec)})")
            else:
                nowhere.append(lineno)
                print("    どこにも出ていない")
            continue
        for cat in EVIDENCE:
            if cat not in found:
                continue
            rec, count = found[cat]
            detail = f" {rec.tool_name}" if rec.kind in ("tool_use", "tool_result") and rec.tool_name else ""
            if cat == "Claude の応答" and rec.kind == "tool_use":
                detail = f" ({rec.tool_name} への入力)"
            notes = [f"このブロックの {count}/{len(targets)} 行を含む"]
            if rank(rec, count)[1]:
                notes.append("文面を作り始めた後")
            print(f"    {cat}{detail}  {tr.fmt_jst(rec.ts)}  {place(rec)}  ({'、'.join(notes)})")
        if set(found) == {"Claude の応答"}:
            claude_only.append(lineno)

print()
print("どこにも出ていない行: " + (", ".join(map(str, nowhere)) if nowhere else "なし"))
print("失敗したコマンドかエラーの結果にだけ出ている行: " + (", ".join(map(str, failed_only)) if failed_only else "なし"))
print("Claude の応答にだけ出ている行: " + (", ".join(map(str, claude_only)) if claude_only else "なし"))
PY
exit 0
