# -*- coding: utf-8 -*-
"""Claude Code の会話の記録 (JSONL) を読む共通の処理。

skills/session-recall/scripts/session-recall.sh と skills/draft-precheck/scripts/code-origin.sh から使う。
標準ライブラリだけで動く。記録の 1 行 (1 つの JSON) から、依頼者の入力・Claude の応答・
ツールの呼び出し・ツールの結果を取り出す。思考の記録、添付、API の要求の控えなどは読まない。
"""

import glob
import json
import os
import re
from datetime import datetime, timedelta, timezone

JST = timezone(timedelta(hours=9))

KIND_LABEL = {
    "user": "依頼者の入力",
    "assistant": "Claude の応答",
    "tool_use": "ツールの呼び出し",
    "tool_result": "ツールの結果",
}

# origin の欄がない古い形式で、依頼者が書いた文ではない入力の書き出し
_NOT_HUMAN_PREFIXES = (
    "<local-command-",
    "<task-notification>",
    "<side-sessions-event>",
    "<cross-session-message",
    "<agent-message",
    "Another Claude session",
    "Task (from the session",
    "[Request interrupted",
    "Caveat:",
    "This session is being continued",
)

_REMINDER_RE = re.compile(r"<system-reminder>.*?</system-reminder>\s*", re.S)
_TYPE_RE = re.compile(r'"type"\s*:\s*"(user|assistant)"')
SAVED_RE = re.compile(r"Full output saved to: (\S+)")

_SECRET_WORDS = (
    r"password|passwd|pwd|secret|token|api[_-]?key|access[_-]?key|private[_-]?key|"
    r"client[_-]?secret|account[_-]?key|shared[_-]?access[_-]?key|sas[_-]?token|sig|"
    r"credentials?|connection[_-]?string|conn[_-]?str"
)

# 伏せ字にする値。名前で分かる値 (key=value) と、形で分かるトークン
_SECRET_PATTERNS = [
    (re.compile(r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----.*?(?:-----END [A-Z0-9 ]*PRIVATE KEY-----|\Z)", re.S),
     "-----BEGIN PRIVATE KEY----- *** -----END PRIVATE KEY-----"),
    (re.compile(r"(\b[A-Za-z][A-Za-z0-9+.-]*://[^\s:/@]+:)[^\s@/]+@"), r"\1***@"),
    (re.compile(r"\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]{8,}"), r"\1 ***"),
    (re.compile(r"(?i)(--(?:[a-z0-9]+-)*(?:" + _SECRET_WORDS + r")[ =]\s*)([^\s\"';,&]+)"), r"\1***"),
    (re.compile(r"(?i)([\"']?[A-Za-z0-9_.-]*?(?:" + _SECRET_WORDS + r")[\"']?\s*[:=]\s*[\"']?)([^\s\"';,&]+)"),
     r"\1***"),
    (re.compile(r"\bAKIA[0-9A-Z]{16}\b"), "***"),
    (re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}"), "***"),
    (re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}"), "***"),
    (re.compile(r"\bxox[abprs]-[A-Za-z0-9-]{10,}"), "***"),
    (re.compile(r"\bsk-[A-Za-z0-9_-]{20,}"), "***"),
    (re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"), "***"),
    (re.compile(r"(hooks\.slack\.com/services/)[A-Za-z0-9/]+"), r"\1***"),
]


def redact(text):
    """秘匿値らしい値を *** に置き換える。名前と形で見分けるので、漏れも伏せすぎもある"""
    for pattern, repl in _SECRET_PATTERNS:
        text = pattern.sub(repl, text)
    return text


def claude_home():
    return os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude")


def transcripts_dir(project):
    """project (絶対パス) の会話の記録の置き場。

    Claude Code は作業ディレクトリのパスの英数字以外 (/ を含む) を - に置き換えた名前で置く。
    名前が 200 字を超えるときは、先頭の 200 字の後ろに - と別の文字列を付ける。
    その名前の置き場がなければ、/ だけを - に置き換えた名前を探す。
    """
    base = os.path.join(claude_home(), "projects")
    name = re.sub(r"[^A-Za-z0-9]", "-", project)
    if len(name) > 200:
        found = sorted(glob.glob(os.path.join(glob.escape(base), glob.escape(name[:200]) + "-*")))
        if len(found) == 1:
            return found[0]
    for candidate in (name, project.replace("/", "-")):
        path = os.path.join(base, candidate)
        if os.path.isdir(path):
            return path
    return os.path.join(base, name)


def main_files(tdir):
    """置き場の直下の会話の記録 (サブエージェントの記録を含まない)"""
    return sorted(glob.glob(os.path.join(tdir, "*.jsonl")))


def subagent_files(tdir, session_file=None):
    """サブエージェントの記録。session_file を渡すと、そのセッションの分だけ"""
    if session_file:
        root = os.path.join(os.path.dirname(session_file), os.path.basename(session_file)[:-len(".jsonl")])
        pattern = os.path.join(root, "subagents", "**", "*.jsonl")
    else:
        pattern = os.path.join(tdir, "*", "subagents", "**", "*.jsonl")
    return sorted(glob.glob(pattern, recursive=True))


def is_under(path, project):
    if not isinstance(path, str) or not path:
        return False
    path = os.path.normpath(path)
    project = os.path.normpath(project)
    if project == os.sep:
        return path.startswith(os.sep)
    return path == project or path.startswith(project + os.sep)


def parse_ts(value):
    if not isinstance(value, str) or not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def fmt_jst(dt):
    if dt is None:
        return "日時不明"
    return dt.astimezone(JST).strftime("%Y-%m-%d %H:%M JST")


def read_saved_output(path, tdir, limit=5_000_000):
    """「Full output saved to:」の別ファイルを読む。記録の置き場の下にあるファイルだけを読む"""
    real = os.path.realpath(path)
    base = os.path.realpath(tdir)
    if not real.startswith(base + os.sep) or not os.path.isfile(real):
        return None
    try:
        with open(real, encoding="utf-8", errors="replace") as fh:
            return fh.read(limit)
    except OSError:
        return None


def _tool_input_text(inp):
    if not isinstance(inp, dict):
        return "" if inp is None else str(inp)
    if isinstance(inp.get("command"), str):
        return inp["command"]
    parts = []
    for key, value in inp.items():
        if isinstance(value, str):
            parts.append(f"{key}: {value}")
        else:
            parts.append(f"{key}: {json.dumps(value, ensure_ascii=False)}")
    return "\n".join(parts)


def _result_text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        out = []
        for block in content:
            if isinstance(block, str):
                out.append(block)
            elif isinstance(block, dict):
                if block.get("type") == "text":
                    out.append(str(block.get("text", "")))
                elif block.get("type") == "tool_reference":
                    out.append("tool_reference: " + str(block.get("tool_name", "")))
        return "\n".join(out)
    return "" if content is None else str(content)


def _human_text(entry, content, sidechain):
    """依頼者が書いた入力の本文。依頼者の入力でなければ空文字"""
    if sidechain or entry.get("isMeta") or entry.get("isCompactSummary") or entry.get("isVisibleInTranscriptOnly"):
        return ""
    if isinstance(content, str):
        text = content
    elif isinstance(content, list):
        text = "\n".join(str(b.get("text", "")) for b in content if isinstance(b, dict) and b.get("type") == "text")
    else:
        return ""
    text = _REMINDER_RE.sub("", text).strip()
    if not text:
        return ""
    origin = entry.get("origin")
    if isinstance(origin, dict):
        return text if origin.get("kind") == "human" else ""
    if text.startswith(_NOT_HUMAN_PREFIXES):
        return ""
    return text


class Record:
    """記録から取り出した 1 件。kind は user / assistant / tool_use / tool_result"""

    __slots__ = ("path", "lineno", "session", "agent", "ts", "uuid", "kind", "text",
                 "tool_id", "tool_name", "tool_input", "is_command", "is_error", "saved")

    def __init__(self, **kw):
        for name in self.__slots__:
            setattr(self, name, kw.get(name))

    def label(self):
        base = KIND_LABEL[self.kind]
        if self.kind in ("tool_use", "tool_result") and self.tool_name:
            base += f" ({self.tool_name})"
        if self.kind == "tool_result" and self.is_error:
            base += " エラー"
        return base

    def where(self):
        who = f"セッション {self.session}"
        if self.agent:
            who += f" のサブエージェント {self.agent}"
        return who


def iter_records(path, tdir, project=None):
    """1 つの記録のファイルから Record を順に返す。project を渡すと、cwd がその下にある行だけ"""
    sidechain_file = os.sep + "subagents" + os.sep in path
    stem = os.path.basename(path)[:-len(".jsonl")]
    tools = {}
    try:
        fh = open(path, encoding="utf-8", errors="replace")
    except OSError:
        return
    with fh:
        for lineno, line in enumerate(fh, 1):
            if not _TYPE_RE.search(line):
                continue
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            if not isinstance(entry, dict) or entry.get("type") not in ("user", "assistant"):
                continue
            if project is not None and not is_under(entry.get("cwd"), project):
                continue
            message = entry.get("message")
            content = message.get("content") if isinstance(message, dict) else None
            sidechain = sidechain_file or bool(entry.get("isSidechain"))
            common = dict(
                path=path,
                lineno=lineno,
                session=entry.get("sessionId") or stem,
                agent=entry.get("agentId") if sidechain else None,
                ts=parse_ts(entry.get("timestamp")),
                uuid=entry.get("uuid"),
            )
            if entry["type"] == "assistant":
                blocks = content if isinstance(content, list) else [{"type": "text", "text": content or ""}]
                for block in blocks:
                    if not isinstance(block, dict):
                        continue
                    if block.get("type") == "text":
                        yield Record(kind="assistant", text=str(block.get("text", "")), **common)
                    elif block.get("type") == "tool_use":
                        inp = block.get("input")
                        text = _tool_input_text(inp)
                        name = str(block.get("name", ""))
                        tools[block.get("id")] = (name, text)
                        is_command = isinstance(inp, dict) and isinstance(inp.get("command"), str)
                        yield Record(kind="tool_use", text=text, tool_id=block.get("id"), tool_name=name,
                                     is_command=is_command, **common)
                continue
            results = [b for b in content if isinstance(b, dict) and b.get("type") == "tool_result"] \
                if isinstance(content, list) else []
            if results:
                for block in results:
                    tool_id = block.get("tool_use_id")
                    name, tool_input = tools.get(tool_id, ("", ""))
                    text = _result_text(block.get("content"))
                    saved = None
                    match = SAVED_RE.search(text)
                    if match:
                        full = read_saved_output(match.group(1), tdir)
                        if full is not None:
                            text = full
                            saved = match.group(1)
                    yield Record(kind="tool_result", text=text, tool_id=tool_id, tool_name=name,
                                 tool_input=tool_input, is_error=bool(block.get("is_error")), saved=saved, **common)
                continue
            text = _human_text(entry, content, sidechain)
            if text:
                yield Record(kind="user", text=text, **common)


def normalize(text):
    """空白の並び (改行を含む) を 1 つの空白にする"""
    return " ".join(text.split())
