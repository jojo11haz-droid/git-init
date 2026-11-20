"""Door hangers (4.25 x 11 in) for people using Between on their own.
Writes HTML per language; door_print.cjs turns them into PDFs + PNG previews.
No transparency, shadows or blur anywhere (iOS PDF viewers draw soft masks as boxes)."""
import base64, io, os, sys
import segno
from PIL import Image

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
CREAM = (245, 244, 241)
ART = '/home/user/git-init/public/assets/fields/hero/individual.webp'

def art_jpeg():
    a = Image.open(ART).convert('RGBA')
    bg = Image.new('RGBA', a.size, CREAM + (255,))
    bg.alpha_composite(a)
    bg = bg.convert('RGB').crop((20, 70, 540, 500))
    buf = io.BytesIO(); bg.save(buf, 'JPEG', quality=92)
    return 'data:image/jpeg;base64,' + base64.b64encode(buf.getvalue()).decode()

def qr_svg(url):
    q = segno.make(url, error='m')
    buf = io.BytesIO()
    q.save(buf, kind='svg', scale=10, border=0, dark='#13294B', xmldecl=False, svgns=True, omitsize=True)
    return buf.getvalue().decode()

LOGO = '<svg viewBox="0 0 64 64"><rect width="64" height="64" rx="14" fill="#1E4C86"/><defs><clipPath id="fl"><circle cx="26" cy="32" r="13"/></clipPath></defs><circle cx="38" cy="32" r="13" fill="#C0392B" clip-path="url(#fl)"/><circle cx="26" cy="32" r="13" fill="none" stroke="#F5F4F1" stroke-width="5"/><circle cx="38" cy="32" r="13" fill="none" stroke="#F5F4F1" stroke-width="5"/></svg>'
CHECK = '<svg viewBox="0 0 20 20"><circle cx="10" cy="10" r="10" fill="#1E4C86"/><path d="M5.5 10.4l3 3 6-6.4" fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>'
NB = ' '

T = {
  'en': dict(lang='en', url='https://betweenpsych.com/individual?utm_source=doorhanger',
    show='betweenpsych.com/individual',
    eyebrow='Just for you', h1=f'A minute a day, just{NB}for{NB}you.',
    lede='Check in with yourself by voice or text. Between turns it into your mood trend and shows you what keeps coming back.',
    pts=['Private: no one else sees it', 'Mood, body, training or eating', f'Free to start · English{NB}&{NB}French'],
    steps=['Scan the code', 'Check in, in a minute', 'See your trend'], cta='Try it free', scan='Scan with your phone camera',
    foot=f'Not a crisis service. In an emergency, call 988 or{NB}911.'),
  'fr': dict(lang='fr', url='https://betweenpsych.com/fr/individual?utm_source=doorhanger',
    show='betweenpsych.com/fr/individual',
    eyebrow='Juste pour vous', h1=f'Une minute par jour, juste pour{NB}vous.',
    lede='Faites le point avec vous-même, par la voix ou par écrit. Between en tire la tendance de votre humeur et vous montre ce qui revient souvent.',
    pts=['Privé : personne d’autre ne le voit', 'Humeur, corps, sport ou alimentation', f'Gratuit pour commencer · Français{NB}et{NB}anglais'],
    steps=['Balayez le code', 'Un suivi en une minute', 'Voyez votre tendance'], cta='Essayez gratuitement', scan='Balayez avec l’appareil photo',
    foot=f'Ce n’est pas un service de crise. En cas d’urgence, composez le 988 ou le{NB}911.'),
}

CSS = '''
@page { size: 4.25in 11in; margin: 0; }
* { box-sizing: border-box; margin: 0; padding: 0; }
html, body { width: 4.25in; height: 11in; }
body { background: #F5F4F1; font-family: Inter, Arial, sans-serif; color: #1D2330; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
.page { position: relative; width: 4.25in; height: 11in; overflow: hidden; }
.top { height: 2.05in; position: relative; }
.guide { position: absolute; left: 50%; top: 0.5in; width: 1.25in; height: 1.25in; margin-left: -0.625in; border-radius: 50%; border: 1.2px dashed #C9CDD3; }
.slit { position: absolute; left: 50%; top: 0; width: 0; height: 0.5in; border-left: 1.2px dashed #C9CDD3; }
.brand { position: absolute; left: 0; right: 0; bottom: 0.02in; display: flex; justify-content: center; align-items: center; gap: 7px; font-family: Newsreader, Georgia, serif; font-size: 22px; font-weight: 600; letter-spacing: -0.01em; }
.brand svg { width: 26px; height: 26px; }
.body { padding: 0.12in 0.34in 0; }
.eyebrow { text-align: center; font-size: 10px; font-weight: 600; letter-spacing: .14em; text-transform: uppercase; color: #C0392B; margin-top: 2px; }
h1 { text-align: center; font-family: Newsreader, Georgia, serif; font-weight: 600; font-size: 33px; line-height: 1.06; letter-spacing: -0.015em; margin: 8px 0 0; }
.art { display: block; width: 3.3in; margin: 10px auto 2px; }
.lede { text-align: center; font-size: 13.2px; line-height: 1.5; color: #4A5160; }
ul { list-style: none; margin: 14px auto 0; width: 3.35in; }
li { display: flex; align-items: center; gap: 9px; font-size: 12.6px; font-weight: 500; padding: 5px 0; }
li svg { flex: 0 0 18px; width: 18px; height: 18px; }
.cta { position: absolute; left: 0.3in; right: 0.3in; bottom: 0.62in; background: #1E4C86; border-radius: 16px; padding: 14px; display: flex; gap: 13px; align-items: center; color: #fff; }
.qr { flex: 0 0 1.12in; height: 1.12in; background: #fff; border-radius: 10px; padding: 8px; }
.qr svg { width: 100%; height: 100%; display: block; }
.cta b { display: block; font-family: Newsreader, Georgia, serif; font-size: 21px; font-weight: 600; line-height: 1.1; }
.cta .u { display: block; font-size: 10.6px; font-weight: 600; margin-top: 6px; word-break: break-all; color: #DCE6F2; }
.cta .s { display: block; font-size: 9.6px; margin-top: 6px; color: #B9C9DD; }
.steps { position: absolute; left: 0.3in; right: 0.3in; bottom: 2.42in; display: flex; justify-content: space-between; gap: 6px; }
.step { flex: 1; text-align: center; font-size: 10.6px; font-weight: 500; line-height: 1.3; color: #1D2330; }
.step i { display: block; margin: 0 auto 5px; width: 24px; height: 24px; border-radius: 50%; background: #E3EAF3; color: #1E4C86; font-style: normal; font-weight: 600; font-size: 12px; line-height: 24px; }
.foot { position: absolute; left: 0.3in; right: 0.3in; bottom: 0.24in; text-align: center; font-size: 8.6px; color: #6B7280; line-height: 1.4; }
'''

FONTS = '<link href="https://fonts.googleapis.com/css2?family=Newsreader:opsz,wght@6..72,600&family=Inter:wght@400;500;600&display=block" rel="stylesheet">'

def page(t, art, guide):
    pts = ''.join(f'<li>{CHECK}<span>{p}</span></li>' for p in t['pts'])
    steps = ''.join(f'<div class="step"><i>{i+1}</i>{x}</div>' for i, x in enumerate(t['steps']))
    g = '<div class="slit"></div><div class="guide"></div>' if guide else ''
    return f'''<div class="page"><div class="top">{g}<div class="brand">{LOGO}<span>Between.</span></div></div>
<div class="body"><div class="eyebrow">{t["eyebrow"]}</div><h1>{t["h1"]}</h1>
<img class="art" src="{art}" alt=""><p class="lede">{t["lede"]}</p><ul>{pts}</ul></div>
<div class="steps">{steps}</div><div class="cta"><div class="qr">{qr_svg(t["url"])}</div><div><b>{t["cta"]}</b><span class="u">{t["show"]}</span><span class="s">{t["scan"]}</span></div></div>
<div class="foot">{t["foot"]}</div></div>'''

art = art_jpeg()
for guide, suffix in ((False, ''), (True, '-with-cut-guide')):
    for lang in ('en', 'fr'):
        html = f'<!doctype html><html lang="{lang}"><head><meta charset="utf-8">{FONTS}<style>{CSS}</style></head><body>{page(T[lang], art, guide)}</body></html>'
        open(os.path.join(OUT, f'between-door-hanger-{lang}{suffix}.html'), 'w', encoding='utf8').write(html)
    # bilingual: French front, English back
    html = f'<!doctype html><html lang="fr"><head><meta charset="utf-8">{FONTS}<style>{CSS}.page{{page-break-after:always}}</style></head><body>{page(T["fr"], art, guide)}{page(T["en"], art, guide)}</body></html>'
    open(os.path.join(OUT, f'between-door-hanger-bilingual{suffix}.html'), 'w', encoding='utf8').write(html)
print('ok')
