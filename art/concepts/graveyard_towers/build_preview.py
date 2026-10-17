"""Own SVG tower concepts and a reproducible browser review; no image generators."""
from pathlib import Path
from shutil import copyfile
import json
import os
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
WEB = ROOT / 'build/web/preview/graveyard-towers'

# Same 256px canvas and large dark outlines as the existing tower. These are
# silhouette concepts, not runtime parts or an approved replacement visual.
COMMON = 'stroke="#292421" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"'
SHADOW = '<ellipse cx="128" cy="240" rx="108" ry="9" fill="#10191b" opacity=".4" stroke="none"/>'
CRYSTAL = '''<path d="m128 16 26 35-4 32-22 14-22-14-4-32Z" fill="#7ae7bf"/>
<path d="m128 22 0 67-19-12-2-24Z" fill="#c5ffe7" stroke="none"/>
<path d="m128 89 19-13 3-24-22 15Z" fill="#3caa96" stroke="none"/>'''

TOWERS = [
('crypt', '01 · Башня-склеп', 'Приземистый каменный склеп, широкая арка и кристалл в навершии.', '''
<path d="m51 124 154 0 12 91 15 19-208 0 15-19Z" fill="#88928a"/>
<path d="m178 130 22 0 13 83-29 0Z" fill="#5c6d65" stroke="none"/>
<path d="m47 111 37-39 88 0 37 39 9 18-180 0Z" fill="#a6afa1"/>
<path d="m49 111 159 0" fill="none" stroke="#687a70" stroke-width="6"/>
<path d="m80 232 0-54q0-43 48-43t48 43v54Z" fill="#475b51"/>
<path d="m95 229 0-49q0-29 33-29t33 29v49Z" fill="#273d35" stroke-width="5"/>
<path d="m104 215 0-33q0-22 24-22t24 22v33Z" fill="#3e6e5a" stroke="none"/>
<path d="m128 169 0 38m-10-22 20 0" fill="none" stroke="#9be8b4" stroke-width="6"/>
<path d="m47 151 18 0 0 38-18 0Z m144 0 18 0 0 38-18 0Z" fill="#b6bea9" stroke-width="5"/>
<path d="m47 195 16 0m132 0 15 0" fill="none" stroke="#5f7265" stroke-width="5"/>
<path d="m91 82 10-24 8 25 38 0 8-25 10 24-12 20-48 0Z" fill="#d7cfaf"/>
''' + CRYSTAL + '''<path d="m24 234 208 0 0 10-208 0Z" fill="#68796d" stroke-width="6"/>
'''),
('obelisk', '02 · Обелиск душ', 'Ступенчатое основание, цельный тёмный камень и открытое свечение.', '''
<path d="m32 222 192 0 9 19-210 0Z" fill="#727f78"/>
<path d="m48 200 160 0 11 23-182 0Z" fill="#a1aa9d"/>
<path d="m81 101 94 0 13 100-120 0Z" fill="#68796e"/>
<path d="m144 105 27 0 13 92-40 0Z" fill="#465c52" stroke="none"/>
<path d="m85 113 16 0-7 68-16 0Z" fill="#a2b4a0" stroke="none"/>
<path d="m128 124 17 19-5 26-12 13-12-13-5-26Z" fill="#87e4b7" stroke-width="5"/>
<path d="m128 132 0 37" fill="none" stroke="#d4ffe5" stroke-width="5"/>
<path d="m66 100 17-28 11-20 9 35 50 0 9-35 11 20 17 28-18 14-88 0Z" fill="#c4c9b2"/>
''' + CRYSTAL + '''<path d="m53 190 14-9 7 18-14 1Z m130-9 15 9-7 10-14-1Z" fill="#bad8bc" stroke-width="5"/>
'''),
('bone_altar', '03 · Костяной алтарь', 'Костяные опоры, небольшой череп и высокий парящий кристалл.', '''
<path d="m35 222 186 0 12 19-210 0Z" fill="#69776b"/>
<path d="m58 139 140 0 12 83-164 0Z" fill="#5e7163"/>
<path d="m160 145 31 0 12 71-43 0Z" fill="#3d5449" stroke="none"/>
<path d="m96 215 0-32q0-31 32-31t32 31v32Z" fill="#283f33"/>
<path d="m38 115 24-8 16 97-8 17-22 0 3-25Z m180 0-24-8-16 97 8 17 22 0-3-25Z" fill="#dbd2ac"/>
<path d="m53 128 10 61m140-61-10 61" fill="none" stroke="#a7aa8a" stroke-width="5"/>
<path d="m42 109-14-16 8-22 18 13 13-18 12 18-10 25Z m172 0 14-16-8-22-18 13-13-18-12 18 10 25Z" fill="#e7dfbd"/>
<path d="m70 127 16-40 13 11-4 24 66 0-4-24 13-11 16 40-18 19-80 0Z" fill="#c9c3a0"/>
<path d="M103 125q0-22 25-22t25 22l-5 18-10 5-1 12-18 0-1-12-11-5Z" fill="#eee4bf" stroke-width="6"/>
<path d="m112 125 10 2-2 10-9-2Z m22 2 10-2 1 10-9 2Z" fill="#3e493b" stroke="none"/>
<path d="m128 137-4 7 8 0Z" fill="#62725b" stroke="none"/>
''' + CRYSTAL + '''<path d="m128 177 9 11-9 15-9-15Z" fill="#98eabd" stroke-width="5"/>
'''),
('lantern', '04 · Фонарь смотрителя', 'Каменный цоколь и крупная клетка-фонарь с кристаллом внутри.', '''
<path d="m39 220 178 0 16 20-210 0Z" fill="#728276"/>
<path d="m59 185 138 0 12 35-162 0Z" fill="#99a692"/>
<path d="m78 172 100 0 7 22-114 0Z" fill="#52685b"/>
<path d="m70 78 116 0 0 98-116 0Z" fill="#39594c"/>
<path d="m84 86 88 0 0 77-88 0Z" fill="#6aaf8b" stroke="none"/>
<path d="m97 99 63 0 0 48-63 0Z" fill="#b4edc7" stroke="none" opacity=".45"/>
<path d="m64 75 23-35 82 0 23 35 3 10-134 0Z" fill="#65766c"/>
<path d="m95 40 17-19 32 0 17 19" fill="#bfc6ac"/>
<path d="m128 52 24 34-4 34-20 16-20-16-4-34Z" fill="#82e9be"/>
<path d="m128 60 0 67-16-12-3-28Z" fill="#d2ffe6" stroke="none"/>
<path d="m74 88 0 80m108-80v80" fill="none" stroke="#c0c5a5" stroke-width="10"/>
<path d="m62 173 132 0 0 12-132 0Z" fill="#a5ad93"/>
<path d="m76 202 20 0m64 0 20 0" fill="none" stroke="#596f5e" stroke-width="5"/>
''')]


def main():
    WEB.mkdir(parents=True, exist_ok=True)
    for key, title, _, shapes in TOWERS:
        svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256"><title>{title}</title><g {COMMON}>{SHADOW}{shapes}</g></svg>\n'
        (HERE / f'{key}.svg').write_text(svg, encoding='utf-8')
        (WEB / f'{key}.svg').write_text(svg, encoding='utf-8')
    assets = {
        'priest.svg': ROOT / 'art/concepts/graveyard/priest_lv1.svg',
        'mage.svg': HERE / 'mage_lv2_preview.svg',
        'ground.svg': ROOT / 'assets/environment/graveyard/ground.svg',
        'tree.svg': ROOT / 'assets/environment/graveyard/dead_tree.svg',
        'road.svg': ROOT / 'assets/environment/graveyard/road.svg',
    }
    mage = ET.parse(ROOT / 'art/source/mage/master.svg')
    # Apply the same blue-cloth mask and shade ratio as MageVisual's shader;
    # leave skin, outline, gold and the red crystal untouched.
    for shape in mage.getroot().iter():
        color = shape.get('fill', '')
        if len(color) != 7 or not color.startswith('#'):
            continue
        r, g, b = [int(color[i:i+2], 16) / 255 for i in (1, 3, 5)]
        if b > g * 1.4 and b > r * 1.8:
            shade = (r + g + b) / (0.208 + 0.408 + 0.714)
            orange = [239, 150, 57]
            shape.set('fill', '#' + ''.join(f'{min(255, round(c * shade)):02x}' for c in orange))
    ET.register_namespace('', 'http://www.w3.org/2000/svg')
    mage.write(HERE / 'mage_lv2_preview.svg', encoding='unicode')
    for dest, source in assets.items():
        copyfile(source, WEB / dest)
    names = json.dumps([item[1] for item in TOWERS], ensure_ascii=False)
    cards = ''.join(f'''<article><h2>{title}</h2><p>{desc}</p>
<a href="{key}.svg" aria-label="Открыть SVG: {title}"><img class="large" src="{key}.svg" alt="{title}"></a>
<div class="scales"><figure><div class="tile"><img src="{key}.svg" width="112" height="112" alt="{title}: 112 px"></div><figcaption>112 px</figcaption></figure><figure><div class="tile tiny"><img src="{key}.svg" width="72" height="72" alt="{title}: 72 px"></div><figcaption>72 px</figcaption></figure></div>
<button data-key="{key}" data-i="{i}" aria-pressed="{'true' if i == 0 else 'false'}">Показать в композиции</button></article>'''
        for i, (key, title, desc, _) in enumerate(TOWERS))
    html = '''<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Кладбище · варианты башни</title>
<style>*{box-sizing:border-box}body{margin:0;padding:24px;background:#101521;color:#d5dfd9;font:16px/1.5 system-ui,sans-serif}main{max-width:1280px;margin:auto}h1,h2{color:#e6bd68;line-height:1.25}h1{margin:0 0 12px;font-size:28px}h2{font-size:20px;margin:0}p{margin:8px 0 16px}header p{max-width:900px}.grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:16px}article{min-width:0;text-align:center;border:1px solid #405b56;border-radius:16px;padding:18px 12px;background:#1a272b}article p{font-size:14px;min-height:64px;color:#b5c9c1}.large{display:block;width:220px;height:220px;max-width:100%;margin:auto}.scales{display:flex;justify-content:center;gap:10px;margin:16px 0}figure{margin:0}.tile{width:112px;height:112px;background:#303b38 url(ground.svg) center/cover;border-radius:8px;display:grid;place-items:center}.tiny{width:80px;height:112px}.tile img{display:block}figcaption{color:#a8bdb2;font-size:13px}button{background:#253d36;color:#e3f5e8;border:1px solid #527565;border-radius:8px;padding:12px 8px;width:100%;font:inherit;font-size:14px;cursor:pointer}button[aria-pressed=true]{border-color:#a3f0c6;color:#c2ffdc;background:#365b48}section{margin-top:28px;padding:20px;background:#162126;border:1px solid #405b56;border-radius:16px}section h2{text-align:center}.context{display:block;width:min(720px,100%);height:auto;margin:auto}footer{margin-top:20px;color:#9ab2a8;font-size:14px}@media(max-width:1000px){.grid{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:520px){body{padding:16px}.grid{grid-template-columns:1fr}article p{min-height:0}.large{width:240px;height:240px}.scales{gap:24px}section{padding:12px}h1{font-size:24px}}</style>
<main><header><h1>Кладбище · башня призывателя</h1><p>Четыре разных силуэта. Собственная ручная SVG-отрисовка, толстый контур, крупные формы и мятная энергия. Ни один вариант пока не заменяет башню в игре.</p><p>На каждой карточке — крупный вид и проверка на 112 / 72 px. Кнопки меняют башню в общей композиции ниже.</p></header><div class="grid">''' + cards + '''</div>
<section id="composition"><h2 id="selected">01 · Башня-склеп</h2><svg class="context" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 720 400" aria-label="Пример композиции меню кладбища"><defs><pattern id="road" width="46" height="46" patternUnits="userSpaceOnUse"><image href="road.svg" width="46" height="46"/></pattern></defs><ellipse cx="360" cy="260" rx="345" ry="110" fill="#303838"/><path d="M100 296 260 296 355 241 430 281 610 293" stroke="url(#road)" stroke-width="46" fill="none" stroke-linejoin="round"/><image href="tree.svg" x="8" y="90" width="155" height="155"/><image href="tree.svg" x="552" y="80" width="176" height="176"/><image href="priest.svg" x="130" y="175" width="128" height="128"/><image id="context-tower" href="crypt.svg" x="250" y="95" width="220" height="220"/><image href="necromancer.svg" x="467" y="176" width="128" height="128"/></svg><p>Жрец света слева, некромант справа — принятые концепты персонажей. Текущие меню и игровые сцены получат новую башню после выбора и приёмки.</p></section><footer>Концепты, без рига и новых VFX. После выбора: разделение на base / body / crystal, существующие idle/tap/sell/hit/destroyed и проверка читаемости счётчика призыва у нижнего края.</footer></main>
<script>const names=''' + names + ''';document.querySelectorAll('button[data-key]').forEach(b=>b.addEventListener('click',()=>{document.querySelector('#context-tower').setAttribute('href',b.dataset.key+'.svg');document.querySelector('#selected').textContent=names[Number(b.dataset.i)];document.querySelectorAll('button[data-key]').forEach(x=>x.setAttribute('aria-pressed',String(x===b)));document.querySelector('#composition').scrollIntoView({behavior:'smooth',block:'nearest'});}));</script></html>'''
    # The menu review now uses allied characters, as requested after selection.
    html = html.replace('necromancer.svg', 'mage.svg').replace(
        'Жрец света слева, некромант справа — принятые концепты персонажей.',
        'Жрец света слева, огненный маг Lv2 справа — союзники в меню кладбища.')
    # The source page resolves the unchanged accepted concept/environment assets.
    source_html = html
    for name, source in assets.items():
        source_html = source_html.replace(name, os.path.relpath(source, HERE).replace('\\', '/'))
    (HERE / 'index.html').write_text(source_html, encoding='utf-8')
    (WEB / 'index.html').write_text(html, encoding='utf-8')

    menu = ROOT / 'assets/ui/graveyard_menu'
    menu.mkdir(parents=True, exist_ok=True)
    for name in ['priest']:
        copyfile(ROOT / f'art/concepts/graveyard/{name}_lv1.svg', menu / f'{name}.svg')
    print('Built 4 SVG concepts, review page, and the accepted priest menu copy.')


if __name__ == '__main__':
    main()
