#!/usr/bin/env python3
"""Costruisce il telecomando unico da pubblicare su GitHub Pages.

Parte dalla stessa pagina servita dal player in rete locale
(assets/remote/remote.html) e aggiunge l'accesso all'account
(web/remote/cloud.js): così le due versioni restano identiche.

Uso: python3 tool/build_web_remote.py _site
"""
import json
import pathlib
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else '_site')
SUPABASE_JS = 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.117.3/dist/umd/supabase.js'

if OUT.exists():
    shutil.rmtree(OUT)
OUT.mkdir(parents=True)

html = (ROOT / 'assets/remote/remote.html').read_text(encoding='utf-8')
for old, new in [
    ('{{TOKEN}}', ''),
    ('href="/manifest.webmanifest?t="', 'href="manifest.webmanifest"'),
    ('href="/apple-touch-icon.png"', 'href="apple-touch-icon.png"'),
    ('href="/icon-192.png"', 'href="icon-192.png"'),
    ('src="/logo.png"', 'src="logo.png"'),
]:
    if old not in html:
        sys.exit(f'remote.html: non trovo {old!r}')
    html = html.replace(old, new)
inject = f'<script src="{SUPABASE_JS}"></script>\n<script src="cloud.js"></script>\n<script>'
if html.count('<script>') != 1:
    sys.exit('remote.html: atteso un solo <script>')
html = html.replace('<script>', inject, 1)
(OUT / 'index.html').write_text(html, encoding='utf-8')

shutil.copy(ROOT / 'web/remote/cloud.js', OUT / 'cloud.js')
shutil.copy(ROOT / 'assets/remote/sw.js', OUT / 'sw.js')
for icon in ['icon-192.png', 'icon-512.png', 'apple-touch-icon.png']:
    shutil.copy(ROOT / 'assets/remote' / icon, OUT / icon)
shutil.copy(ROOT / 'assets/brand/logo.png', OUT / 'logo.png')
shutil.copytree(ROOT / 'assets/channels/logos', OUT / 'chlogo')

(OUT / 'manifest.webmanifest').write_text(json.dumps({
    'name': 'Telecomando B&B IPTV Player',
    'short_name': 'Telecomando',
    'start_url': './',
    'scope': './',
    'display': 'standalone',
    'background_color': '#05040e',
    'theme_color': '#05040e',
    'icons': [
        {'src': 'icon-192.png', 'sizes': '192x192', 'type': 'image/png'},
        {'src': 'icon-512.png', 'sizes': '512x512', 'type': 'image/png'},
    ],
}, ensure_ascii=False, indent=2), encoding='utf-8')
(OUT / '.nojekyll').write_text('')
print(f'Telecomando unico pronto in {OUT}')
