"""Deploy-time step: inline assets/styles.css into every page.

The source pages link the stylesheet so the site still works by opening the
files locally. On deploy each page gets the CSS in a <style> block instead,
which removes the one render-blocking request (and with it a first-paint stall
Lighthouse's headless Chrome shows on slow connections).
"""
import pathlib, re

root = pathlib.Path(__file__).resolve().parents[2]
css = (root / 'assets/styles.css').read_text()
css = css.replace('url("fonts/archivo.woff2")', 'url("/assets/fonts/archivo.woff2")')
link = re.compile(r'<link rel="stylesheet" href="(?:\.\./|/)?assets/styles\.css">')

for page in root.rglob('*.html'):
    html = page.read_text()
    if link.search(html):
        page.write_text(link.sub(lambda _: '<style>' + css + '</style>', html, count=1))
        print('inlined', page.relative_to(root))
