#!/usr/bin/env python3
"""資料の構成の機械検査。

Markdown の資料から題・見出し・各章の1文目を抜き出し、構成の検査のうち
機械で数えられる項目を表示する。入力の誤りを含めて、終了コードは常に 0。
当たった項目は行頭に [当たり] を付ける。当たりは「読む場所」の候補で、
直すかどうかは本体が現物を読んで決める。抜け(母集団との照らし合わせ)は検査しない。

使い方: outline-check.py <資料.md> --type <decision|record|runbook|explanation>
"""
import re
import sys
from collections import defaultdict

TYPES = ("decision", "record", "runbook", "explanation")
CONTAINER = ["一覧", "詳細", "検討", "背景", "その他", "補足", "まとめ", "概要", "はじめに", "おわりに", "備考"]
# 冒頭の一覧と対応させない、種類に共通の章
COMMON = ["前提", "停止条件", "確認", "元に戻す方法", "全体の構成", "作らないもの", "例外と条件",
          "参考情報", "参考", "用語", "出典", "付録", "改訂履歴"]
TAIL = ["用語", "出典", "参考情報", "参考", "付録", "改訂履歴"]
UNITS = "円|米ドル|%|時間|分間|分|秒|日分|日|か月|年|GB|MB"
NUM = re.compile(r"約?([0-9][0-9,]*(?:\.[0-9]+)?(?:〜[0-9][0-9,]*(?:\.[0-9]+)?)?)(" + UNITS + ")")
FENCE = re.compile(r"^\s*(`{3,}|~{3,})(.*)$")
SHELL = ("bash", "sh", "shell", "zsh", "console", "powershell", "pwsh", "ps1", "cmd", "bat")
RECORD_WORDS = re.compile(r"作成日|起票|ステータス|決めた|決定|指示|承認|了承|さん[:：]|依頼[:：]")
DATE = re.compile(r"20[0-9]{2}-[0-9]{2}-[0-9]{2}|(?<![0-9/])[0-9]{1,2}/[0-9]{1,2}(?![0-9/])")


def strip_num(title):
    return re.sub(r"^[0-9]+(?:[-.][0-9]+)*[.．、]?\s*", "", title).strip()


def norm(s):
    return re.sub(r"[^一-龥ぁ-んァ-ヶーA-Za-z0-9]", "", s)


def bigrams(s):
    s = norm(s)
    return {s[i:i + 2] for i in range(len(s) - 1)}


def corresponds(item, heading):
    """一覧の項目と見出しが同じ呼び名か。"""
    a, b = norm(item), norm(strip_num(heading))
    if not a or not b:
        return False
    if a == b or (len(a) >= 2 and a in b) or (len(b) >= 2 and b in a):
        return True
    common = len(bigrams(a) & bigrams(b))
    return common >= 3 and common / max(1, min(len(bigrams(a)), len(bigrams(b)))) >= 0.6


def read_lines(path):
    """(行の一覧, コードの中かどうか, フェンスの言語) を返す。"""
    with open(path, encoding="utf-8") as f:
        lines = f.read().split("\n")
    in_code, fence, lang = [], None, ""
    langs = []
    for l in lines:
        m = FENCE.match(l)
        if fence is None and m:
            fence, lang = m.group(1), m.group(2).strip().lower()
            in_code.append(True)
            langs.append(lang)
            continue
        if fence is not None:
            in_code.append(True)
            langs.append(lang)
            if m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence) and not m.group(2).strip():
                fence, lang = None, ""
            continue
        in_code.append(False)
        langs.append("")
    return lines, in_code, langs


def first_sentence(body):
    for l in body:
        t = l.strip()
        if not t:
            continue
        if t.startswith("#"):
            return None, "見出し"
        if t.startswith("|"):
            return None, "表"
        if re.match(r"^([-*・]|[0-9]+[.)])\s", t):
            return None, "箇条書き"
        if t.startswith(">") or re.match(r"^\*\*[^*]+\*\*\s*[:：]", t):
            return None, "注記か属性の行"
        if re.match(r"^(図|表)\s*[:：]", t) or t.endswith((":", "\uff1a")):
            return None, "図の題か見出しの代わりの行"
        t = t.replace("**", "")
        m = re.search(r"。|[.](?=\s|$)", t)
        return (t[:m.end()] if m else t), None
    return None, "中身なし"


def main():
    args = sys.argv[1:]
    doc_type = None
    if "--type" in args:
        i = args.index("--type")
        if i + 1 >= len(args) or args[i + 1] not in TYPES:
            print("[当たり] --type には " + "、".join(TYPES) + " のどれかを指定してください。検査していません")
            return
        doc_type = args[i + 1]
        del args[i:i + 2]
    if not args:
        print(__doc__)
        return
    if doc_type is None:
        print("[当たり] --type の指定がありません。種類ごとの検査を行っていません")
    try:
        lines, in_code, langs = read_lines(args[0])
    except (OSError, UnicodeDecodeError) as e:
        print(f"[当たり] 資料を読めません: {e}。検査していません")
        return

    heads = []
    for i, l in enumerate(lines):
        if in_code[i]:
            continue
        m = re.match(r"^(#{1,6})\s+(.+?)\s*$", l)
        if m:
            heads.append((i, len(m.group(1)), m.group(2)))
    if not heads:
        print("[当たり] 見出しがありません")
        return
    title = heads[0] if heads[0][1] == 1 else None
    rest = heads[1:] if title else heads
    if not rest:
        print("[当たり] 題の下に章がありません")
        return
    top = min(h[1] for h in rest)
    chapters = [h for h in rest if h[1] == top]
    hits = 0

    def hit(msg):
        nonlocal hits
        hits += 1
        print("[当たり] " + msg)

    def text_of(a, b):
        return [lines[i] for i in range(a, b) if not in_code[i]]

    def is_tail(t):
        return any(strip_num(t).startswith(x) for x in TAIL)

    def is_common(t):
        return any(strip_num(t).startswith(x) for x in COMMON)

    # --- 1. 骨組み ---
    print("== 1. 題・見出し・各章の1文目 ==")
    intro_start = (title[0] + 1) if title else 0
    intro_end = rest[0][0]
    intro = text_of(intro_start, intro_end)
    if title:
        print("題: " + title[2])
        if re.search(r"と、|および", title[2]):
            hit(f"題「{title[2]}」に主題が2つ以上あります。資料の種類が1つかを読む")
    s, why = first_sentence(intro)
    print("冒頭の1文目: " + (s if s else "(なし: " + why + ")"))
    lead_missing = []
    for idx, h in enumerate(rest):
        nxt = rest[idx + 1][0] if idx + 1 < len(rest) else len(lines)
        s, why = first_sentence(text_of(h[0] + 1, nxt))
        indent = "  " * (h[1] - top)
        print(f"{indent}{h[2]}")
        if h[1] == top:
            print(f"{indent}  1文目: " + (s if s else "(なし: " + why + ")"))
            if not s and not is_tail(h[2]):
                lead_missing.append(h[2])
    if lead_missing and doc_type in ("decision", "explanation"):
        hit("章の結論の1文が無い章: " + "、".join(lead_missing))

    # --- 2. 冒頭の一覧と章の題 ---
    print("\n== 2. 冒頭の一覧と章の題の対応 ==")
    items = []
    rows = [l for l in intro if l.startswith("|")]
    for r in rows[2:]:
        cells = [c.strip() for c in r.strip().strip("|").split("|")]
        cell = cells[0]
        if re.fullmatch(r"[0-9]+[.)．]?", cell) and len(cells) > 1:
            cell = cells[1]
        if cell:
            items.append(re.sub(r"^[0-9]+[.)．]\s*", "", cell))
    if not items:
        items = [re.sub(r"^([-*・]|[0-9]+[.)])\s*", "", l.strip())
                 for l in intro if re.match(r"^\s*([-*・]|[0-9]+[.)])\s", l)]
    body_chapters = [c for c in chapters if not is_common(c[2])]
    if not items:
        hit("冒頭に一覧がありません。決めること、作業、対象、問いの一覧を冒頭に置きます")
    else:
        order = []
        for it in items:
            exact = [k for k, c in enumerate(body_chapters) if norm(it) == norm(strip_num(c[2]))]
            match = exact or [k for k, c in enumerate(body_chapters) if corresponds(it, c[2])]
            if len(match) == 1:
                print(f"一覧「{it}」 → 章「{body_chapters[match[0]][2]}」")
                order.append(match[0])
            elif not match:
                sub = [h[2] for h in rest if h[1] > top and corresponds(it, h[2])]
                extra = f"。節「{sub[0]}」にはあります" if sub else ""
                hit(f"一覧「{it}」と同じ呼び名の章がありません{extra}")
            else:
                hit(f"一覧「{it}」と同じ呼び名の章が{len(match)}つあります")
        if order != sorted(order):
            hit("章の順が、冒頭の一覧の順と違います")
        listed = set(order)
        for k, c in enumerate(body_chapters):
            if k not in listed and not any(corresponds(it, c[2]) for it in items):
                print(f"一覧に無い章: 「{c[2]}」。共通の章か、一覧に足す章かを読む")

    # --- 3. 見出し ---
    print("\n== 3. 中身が分からない見出し ==")
    found = False
    for h in rest:
        if strip_num(h[2]) in CONTAINER:
            found = True
            hit(f"見出し「{h[2]}」は中身を表していません")
        if re.search("[(\uff08].+[)\uff09]", h[2]):
            found = True
            hit(f"見出し「{h[2]}」に括弧の注記があります")
    for a, b in zip(rest, rest[1:]):
        if b[1] - a[1] >= 2:
            found = True
            hit(f"見出しの階層が1つ飛んでいます: 「{a[2]}」→「{b[2]}」")
    if not found:
        print("なし")

    # --- 4. 章ごとの分量と、表の種類 ---
    print("\n== 4. 章ごとの字数と表(字数は、見出しを除き、コードを含む) ==")
    sizes = []
    for idx, c in enumerate(chapters):
        nxt = chapters[idx + 1][0] if idx + 1 < len(chapters) else len(lines)
        n = sum(len(lines[i]) for i in range(c[0] + 1, nxt)
                if in_code[i] or not lines[i].startswith("#"))
        headers, prev = [], ""
        for l in text_of(c[0] + 1, nxt):
            if re.match(r"^\|[\s:|-]+\|\s*$", l) and prev.startswith("|"):
                headers.append(prev.strip())
            prev = l
        sizes.append((c[2], n, len(headers), len(set(headers))))
    main_sizes = [x for x in sizes if not is_tail(x[0])]
    total = sum(x[1] for x in main_sizes) or 1
    for t, n, tb, kinds in sizes:
        share = "" if is_tail(t) else f" 本文の{n * 100 // total}%"
        print(f"{t}: {n}字{share}、表{tb}(列の組{kinds}種類)")
        if not is_tail(t) and n * 100 > total * 40 and len(main_sizes) >= 4:
            hit(f"「{t}」が本文の4割を超えています。1つの章に複数の判断か種類が入っていないかを読む")
        if kinds >= 4:
            hit(f"「{t}」に列の組が違う表が{kinds}種類あります。種類の違う中身が混ざっていないかを読む")
    if len(main_sizes) < 4:
        print("本文の章が3つ以下のため、4割の検査は行っていません")

    # --- 5. 同じ数値 ---
    print(f"\n== 5. 同じ数値の置き場所(対象の単位: {UNITS.replace('|', '、')}。「約」と桁の区切りは無視) ==")
    print("同じ数値が別の事柄を指す場合がある。当たりは、同じ事柄を2か所に書いていないかを読む場所")
    by_ch, by_sec = defaultdict(set), defaultdict(set)
    cur = None
    spans = []
    for idx, h in enumerate(rest):
        nxt = rest[idx + 1][0] if idx + 1 < len(rest) else len(lines)
        if h[1] == top:
            cur = h[2]
        spans.append((h[2], cur, h[0] + 1, nxt))
    for sec, ch, a, b in spans:
        if is_tail(ch):
            continue
        for l in text_of(a, b):
            for m in NUM.finditer(l):
                key = m.group(1).replace(",", "") + m.group(2)
                by_ch[key].add(ch)
                by_sec[key].add(sec)
    any5 = False
    for key in sorted(by_ch, key=lambda k: (-len(by_ch[k]), -len(by_sec[k]))):
        if len(by_ch[key]) >= 2:
            any5 = True
            hit(f"{key} が{len(by_ch[key])}つの章にあります: " + "、".join(sorted(by_ch[key])))
        elif len(by_sec[key]) >= 3:
            any5 = True
            hit(f"{key} が1つの章の{len(by_sec[key])}つの節にあります: " + "、".join(sorted(by_sec[key])))
    if not any5:
        print("なし")

    # --- 6. 推奨 ---
    print("\n== 6. 「推奨」が出る章(判定はしない。同じ判断の推奨が2つ以上の章に無いかを読む) ==")
    rec = []
    for idx, c in enumerate(chapters):
        nxt = chapters[idx + 1][0] if idx + 1 < len(chapters) else len(lines)
        k = sum(l.count("推奨") for l in text_of(c[0] + 1, nxt))
        if k:
            rec.append(f"{c[2]}({k}回)")
    print("、".join(rec) if rec else "なし")

    # --- 7. 見出しの形 ---
    print("\n== 7. 見出しの形 ==")
    ok7 = True
    numbered = [bool(re.match(r"^[0-9]", c[2])) for c in chapters if not is_tail(c[2])]
    if any(numbered) and not all(numbered):
        ok7 = False
        hit("同じ階層で、番号のある見出しと無い見出しが混ざっています")
    sent = [h[2] for h in rest if re.search(r"(する|した|ある|ない|です|ます|か)$", strip_num(h[2]))]
    if sent and len(sent) != len(rest):
        ok7 = False
        hit("名詞句の見出しと、文の見出しが混ざっています。文の見出し: " + "、".join(sent))
    if ok7:
        print("なし")

    # --- 8. 手順書 ---
    if doc_type == "runbook":
        print("\n== 8. 手順書(見出しとコードの位置だけを見る。中身は読んで確認する) ==")
        titles = [strip_num(h[2]) for h in rest]
        for key, label in [("前提", "前提"), ("停止条件", "停止条件"), ("戻", "元に戻す方法"), ("確認", "確認")]:
            if not any(key in t for t in titles):
                hit(f"「{label}」の見出しがありません。別の名前で書いていないかを読む")
        if not any("期待結果" in l for l in lines):
            hit("「期待結果」の語がありません。別の名前で書いていないかを読む")
        cmd_first = next((i for i, l in enumerate(lines)
                          if in_code[i] and FENCE.match(l) and langs[i] in SHELL), None)
        cond = next((h[0] for h in rest if "停止条件" in h[2]), None)
        if cmd_first is None:
            print("シェルの言語を指定したコードがありません。停止条件の位置は検査していません")
        elif cond is not None and cond > cmd_first:
            hit("停止条件の章が、最初のシェルのコードより後にあります")
        dated = [l for i, l in enumerate(lines)
                 if not in_code[i] and DATE.search(l) and RECORD_WORDS.search(l) and "http" not in l]
        if dated:
            hit(f"日付と、決定か経緯を表す語のある行が{len(dated)}行あります。判断の記録か経緯でないかを読む")

    print(f"\n当たり: {hits}件")


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        sys.stderr.close()
    except Exception as e:  # 検査は止めない
        print(f"[当たり] 検査の途中で失敗しました: {type(e).__name__}: {e}")
    sys.exit(0)
