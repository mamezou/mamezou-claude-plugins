#!/bin/bash
# 前のセッションの会話の記録 (Claude Code の JSONL) を語で探す。/docs-tools:session-recall から呼ばれる。
# 使い方: session-recall.sh [--project <dir>] [--days N] [--kind user|assistant|tool_use|tool_result]... [--limit N] <語>...
# 読むのは --project (既定は今のディレクトリ) の会話の記録の置き場と、その下のサブエージェントの記録だけ。
# 各行の cwd が --project の下にある行だけを使う。出力の秘匿値らしい値は *** に伏せる。

set -uo pipefail

LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../lib" && pwd)
if ! command -v python3 > /dev/null 2>&1; then
  echo "python3 が見つかりません" >&2
  exit 1
fi

DOCS_TOOLS_LIB="$LIB_DIR" exec python3 -I -B - "$@" << 'PY'
import os
import sys
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.environ["DOCS_TOOLS_LIB"])
import transcript as tr  # noqa: E402

USAGE = ("使い方: session-recall.sh [--project <dir>] [--days N] "
         "[--kind user|assistant|tool_use|tool_result]... [--limit N] <語>...")
CONTEXT = 2       # 一致した行の前後に出す行数
WIDTH = 200       # 1 行に出す字数
NEIGHBOR = 8      # 直前・直後の記録から出す行数
MAX_LINES = 14    # 1 件に出す行数の上限


def die(message):
    print(message, file=sys.stderr)
    print(USAGE, file=sys.stderr)
    sys.exit(2)


def positive_int(option, value):
    if not value.isdigit() or int(value) < 1:
        die(f"{option} には 1 以上の整数を渡してください: {value}")
    return int(value)


args = sys.argv[1:]
project = os.getcwd()
days = None
kinds = []
limit = 20
words = []
i = 0
while i < len(args):
    arg = args[i]
    if arg in ("-h", "--help"):
        print(USAGE)
        sys.exit(0)
    if arg == "--":
        words.extend(args[i + 1:])
        break
    if arg in ("--project", "--days", "--kind", "--limit"):
        if i + 1 >= len(args):
            die(f"{arg} の値がありません")
        value = args[i + 1]
        i += 2
        if arg == "--project":
            project = os.path.abspath(os.path.expanduser(value))
        elif arg == "--days":
            days = positive_int(arg, value)
        elif arg == "--limit":
            limit = positive_int(arg, value)
        else:
            if value not in tr.KIND_LABEL:
                die(f"--kind は user / assistant / tool_use / tool_result のどれかです: {value}")
            kinds.append(value)
        continue
    if arg.startswith("--"):
        die(f"知らないオプションです: {arg}")
    words.append(arg)
    i += 1

words = [w for w in words if w.strip()]
if not words:
    die("探す語を 1 つ以上渡してください")
kinds = kinds or list(tr.KIND_LABEL)
needles = [w.casefold() for w in words]

tdir = tr.transcripts_dir(project)
if not os.path.isdir(tdir):
    print(f"会話の記録の置き場がありません: {tdir}", file=sys.stderr)
    print(f"--project ({project}) で Claude Code を使ったことがあるかを確かめてください", file=sys.stderr)
    sys.exit(1)

cutoff = datetime.now(timezone.utc) - timedelta(days=days) if days else None
files = tr.main_files(tdir)
subs = tr.subagent_files(tdir)


def clip(line, pos=None):
    if len(line) <= WIDTH:
        return line
    if pos is None or pos < WIDTH - 40:
        return line[:WIDTH] + "…"
    start = max(0, pos - 80)
    return "…" + line[start:start + WIDTH] + "…"


def snippet(text):
    """一致した行と前後の行。一致した行には > を付ける"""
    lines = text.splitlines() or [text]
    hits = [n for n, line in enumerate(lines) if any(w in line.casefold() for w in needles)]
    if not hits:  # 語が行をまたいで並ぶときなど。先頭を出す
        hits = [0]
    shown = set()
    for n in hits:
        shown.update(range(max(0, n - CONTEXT), min(len(lines), n + CONTEXT + 1)))
    out = []
    prev = None
    for n in sorted(shown):
        if len(out) >= MAX_LINES:
            rest = len([h for h in hits if h > prev])
            if rest:
                out.append(f"      …(この記録の中の一致はほかに {rest} 行)")
            break
        if prev is not None and n != prev + 1:
            out.append("      …")
        line = lines[n]
        if n in hits:
            positions = [line.casefold().find(w) for w in needles if w in line.casefold()]
            out.append("    > " + clip(line, min(positions) if positions else None))
        else:
            out.append("      " + clip(line))
        prev = n
    return out


def head_lines(text, tail=False):
    lines = text.splitlines()
    picked = lines[-NEIGHBOR:] if tail else lines[:NEIGHBOR]
    out = ["      " + clip(line) for line in picked]
    rest = len(lines) - len(picked)
    if rest > 0:
        note = f"      …(この前に {rest} 行)" if tail else f"      …(この後に {rest} 行)"
        if tail:
            out.insert(0, note)
        else:
            out.append(note)
    return out


hits = []
seen = set()
read_count = 0
for path in files + subs:
    if cutoff is not None:
        try:
            if datetime.fromtimestamp(os.path.getmtime(path), timezone.utc) < cutoff:
                continue
        except OSError:
            continue
    read_count += 1
    records = list(tr.iter_records(path, tdir, project))
    for n, rec in enumerate(records):
        if rec.kind not in kinds:
            continue
        if cutoff is not None and (rec.ts is None or rec.ts < cutoff):
            continue
        if not all(w in rec.text.casefold() for w in needles):
            continue
        # 伏せ字にした後も語が残る記録だけを出す (秘匿値の中だけで一致した記録は出さない)
        rec.text = tr.redact(rec.text)
        if not all(w in rec.text.casefold() for w in needles):
            continue
        key = (rec.uuid, rec.kind, rec.tool_id, hash(rec.text)) if rec.uuid else None
        if key is not None:
            if key in seen:
                continue
            seen.add(key)
        neighbor = None
        if rec.kind == "tool_use":
            for later in records[n + 1:]:
                if later.kind == "tool_result" and later.tool_id == rec.tool_id:
                    neighbor = ("直後", later)
                    break
        elif rec.kind == "assistant" and n + 1 < len(records) and records[n + 1].kind == "user":
            neighbor = ("直後", records[n + 1])
        elif rec.kind == "user" and n > 0 and records[n - 1].kind == "assistant":
            neighbor = ("直前", records[n - 1])
        hits.append((rec, neighbor))

min_ts = datetime.min.replace(tzinfo=timezone.utc)
hits.sort(key=lambda h: h[0].ts or min_ts, reverse=True)

print(f"探した範囲: {tdir} の記録のファイル {read_count} 件 (サブエージェントの記録を含む)。cwd が {project} の下にある行だけ")
cond = f"語: {' '.join(words)} (すべてを含む記録。英字の大文字と小文字は区別しない)"
if days:
    cond += f"、直近 {days} 日"
if len(kinds) < len(tr.KIND_LABEL):
    cond += "、種類: " + " / ".join(tr.KIND_LABEL[k] for k in kinds)
print(cond)
if not hits:
    print("一致する記録はありません")
    sys.exit(0)
print(f"一致: {len(hits)} 件。新しい順に {min(limit, len(hits))} 件を出す")

for number, (rec, neighbor) in enumerate(hits[:limit], 1):
    print()
    print(f"[{number}] {tr.fmt_jst(rec.ts)}  {rec.label()}  {rec.where()}")
    print(f"    記録: {rec.path} の {rec.lineno} 行目")
    if rec.kind == "tool_result" and rec.tool_input:
        print(f"    呼び出し: {clip(rec.tool_input.splitlines()[0] if rec.tool_input.splitlines() else '')}")
    if rec.saved:
        print(f"    全文の保存先: {rec.saved}")
    for line in snippet(rec.text):
        print(line)
    if neighbor:
        side, other = neighbor
        other.text = tr.redact(other.text)
        place = "同じ記録" if other.path == rec.path else other.path
        print(f"    {side}の記録: {tr.fmt_jst(other.ts)}  {other.label()}  ({place}の {other.lineno} 行目)")
        for line in head_lines(other.text, tail=(side == "直前")):
            print(line)
PY
