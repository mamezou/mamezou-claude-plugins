#!/usr/bin/env python3
"""共有用の版の HTML(Artifact に載せる形、doctype なし)を A4 の PDF に書き出す。

使い方: python3 export_pdf.py <共有用の版.html> <出力.pdf>
前提: Python の playwright と、Google Chrome が入っていること。
"""
import os
import sys
import tempfile

from playwright.sync_api import sync_playwright

src, out = sys.argv[1], sys.argv[2]
head = ('<!doctype html><html lang="ja"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        '<style>body{margin:0}</style></head><body>\n')
with open(src, encoding="utf-8") as f:
    page = head + f.read() + "</body></html>"
with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False, encoding="utf-8",
                                 dir=os.path.dirname(os.path.abspath(src))) as t:
    t.write(page)
    tmp = t.name
try:
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome")
        pg = browser.new_page()
        pg.emulate_media(media="print", color_scheme="light")
        pg.goto("file://" + tmp, wait_until="networkidle")
        pg.evaluate("document.fonts.ready")
        pg.pdf(path=out, format="A4", print_background=True, scale=0.78,
               margin={"top": "10mm", "bottom": "10mm", "left": "10mm", "right": "10mm"})
        browser.close()
finally:
    os.unlink(tmp)
