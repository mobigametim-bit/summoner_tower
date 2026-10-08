"""Static review only: compose original cutout art with hand-authored SVG equipment.

Run from any directory. Production masters, parts, scenes and rigs remain unchanged.
All added equipment uses the original full canvas and named parent part.
"""
from pathlib import Path
import copy
import html
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
NS = 'http://www.w3.org/2000/svg'
ET.register_namespace('', NS)
COLORS = ['#88b96b', '#ec9b49', '#df5654', '#5295ef', '#b66dea']
NAMES = ['Гоблин', 'Орк', 'Голем']
ENTITIES = ['goblin', 'orc', 'golem']
BASE_HP = [30, 60, 120]
CANVAS = [86.4, 120, 140]
CAPTIONS = {
    'goblin': ['Кинжал · лёгкая одежда', 'Широкий кинжал · металлический наплечник',
               'Короткий меч · деревянный щит', 'Зубчатый меч · окантованный щит · нагрудник',
               'Тесак · металлический щит · открытый шлем'],
    'orc': ['Топор · исходные наплечники', 'Увеличенный топор · усиленный наплечник',
            'Большой топор · металлические наручи', 'Двулезвийный топор · круглый щит · нагрудник',
            'Тяжёлый двулезвийный топор · усиленный щит · открытый шлем'],
    'golem': ['Каменные кулаки · мох', 'Каменные накладки на оба кулака',
              'Большие кулаки · плечевые плиты', 'Скобы на кулаках · каменный нагрудник',
              'Бронированные кулаки · усиленные плечи · надбровная плита'],
}


def shade(color, factor):
    return '#' + ''.join(f'{min(255, round(int(color[i:i+2], 16)*factor)):02x}' for i in (1, 3, 5))


def fragment(xml):
    return ET.fromstring(f'<g xmlns="{NS}" stroke="#29180f" stroke-width="7" stroke-linecap="round" stroke-linejoin="round">{xml}</g>')


def add(parts, parent, name, xml):
    item = fragment(xml)
    item.set('id', name)
    item.set('data-parent-part', parent)
    parts[parent].append(item)


def recolor(root, entity, color):
    # These are equipment/moss paths only; faces and skin/stone never get tinted.
    if entity == 'goblin':
        for group in root.findall(f'{{{NS}}}g'):
            name = group.get('id', '')
            for path in group:
                selected = name.startswith('leg_') or (name.startswith('arm_'))
                if selected and path.get('fill') in ('#754229', '#aa7540'):
                    path.set('fill', color if path.get('fill') == '#754229' else shade(color, 1.18))
                if selected and path.get('stroke') == '#aa7540':
                    path.set('stroke', shade(color, 1.18))
                if name == 'body' and path.get('fill') in ('#9c642d', '#b77e42'):
                    path.set('fill', color if path.get('fill') == '#9c642d' else shade(color, 1.18))
    else:
        attr = 'data-equipment' if entity == 'orc' else 'data-moss'
        for group in root.iter(f'{{{NS}}}g'):
            if attr not in group.attrib:
                continue
            for path in group:
                old = path.get('fill')
                if old in ('#9c642d', '#88b96b'):
                    path.set('fill', color)
                elif old == '#b77e42':
                    path.set('fill', shade(color, 1.18))
                elif old == '#668b50':
                    path.set('fill', shade(color, .75))


def goblin(parts, tier, color):
    if tier < 2:
        return
    # Back shoulder: hidden overlap below the head, same base shoulder position.
    add(parts, 'body', 'metal_pauldron', '''
      <path d="M78 136 103 136 115 152 104 169 78 160 71 147Z" fill="#738587" stroke-width="6"/>
      <path d="m81 141 19 1 6 9-20 5-8-9Z" fill="#b9c9c3" stroke="none"/>''')
    weapon = parts['dagger']
    # Keep the original hand grip; remove only the blade and crossguard.
    for item in list(weapon)[2:]:
        weapon.remove(item)
    blades = {
        2: '<path d="M-8-16-7-66 8-96 19-68 14-17Z" fill="#c5c0b6"/><path d="M8-87 10-22 16-24 16-65Z" fill="#738587" stroke="none"/>',
        3: '<path d="M-7-15-7-99 5-121 16-100 15-15Z" fill="#c5c0b6"/><path d="M5-113 5-19 13-19 13-98Z" fill="#738587" stroke="none"/>',
        4: '<path d="M-7-15-7-104 6-126 21-109 14-99 23-89 15-80 23-69 15-59 22-48 14-37 15-15Z" fill="#c5c0b6"/><path d="M6-116 6-21 13-22 12-100Z" fill="#738587" stroke="none"/>',
        5: '<path d="M-9-16-12-119 15-133 27-112 25-32 15-15Z" fill="#738587"/><path d="M-5-114 12-123 17-107 16-32 7-20-3-20Z" fill="#b9c9c3" stroke="none"/>',
    }
    add(parts, 'dagger', 'tier_blade', f'<g transform="translate(205 190) rotate(12)" stroke-width="6">{blades[tier]}<path d="m-15-15 34 0-1 10-33 0Z" fill="#738587" stroke-width="5"/></g>')
    if tier >= 3:
        outer = '#895334' if tier == 3 else '#738587'
        inner = '#b77e42' if tier < 5 else '#4c5a5d'
        add(parts, 'arm_back', 'shield', f'''
          <path d="M20 161Q46 153 74 163L73 190Q67 215 47 226 25 214 20 190Z" fill="{outer}" stroke-width="6"/>
          <path d="M28 169Q46 163 66 169L65 189Q60 207 47 217 32 207 28 188Z" fill="{inner}" stroke-width="4"/>
          <path d="m46 171 1 35" fill="none" stroke="{'#754229' if tier < 5 else '#738587'}" stroke-width="4"/>
          <circle cx="47" cy="188" r="8" fill="{color}" stroke-width="4"/>''')
    if tier >= 4:
        add(parts, 'body', 'breastplate', f'''
          <path d="m103 152 40-3 17 20-9 19-41 3-15-17Z" fill="#738587" stroke-width="6"/>
          <path d="m105 158 34-2 10 13-27 8-19-10Z" fill="#b9c9c3" stroke="none"/>
          <path d="m113 181 26-3" stroke="{color}" stroke-width="6"/>''')
    if tier >= 5:
        add(parts, 'head', 'open_helmet', f'''
          <path d="M76 85 80 56 101 35 130 28 155 34 176 50 186 84 171 86 157 66 119 59 93 87Z" fill="#738587" stroke-width="6"/>
          <path d="m87 58 18-17 24-6 23 5 13 12-18-4-28-2-25 17Z" fill="#b9c9c3" stroke="none"/>
          <path d="m115 32 18-4 6 37-21-6Z" fill="{color}" stroke-width="5"/>''')


def orc(parts, tier, color):
    if tier < 2:
        return
    add(parts, 'arm_back', 'reinforced_pauldron', '''
      <path d="m36 115 37-8 24 28-20 27-37-12-14-17Z" fill="#738587" stroke-width="6"/>
      <path d="m42 122 28-7 15 20-14 16-28-10Z" fill="#b9c9c3" stroke="none"/>''')
    axe = parts['axe']
    # Same handle axis and hand grip as the accepted rig.
    for item in list(axe)[4:]:
        axe.remove(item)
    if tier == 2:
        blade = '<path d="M214 71 230 78Q252 96 250 127L246 149 231 171 226 151Q238 127 213 109L204 97Z" fill="#8d8981"/><path d="M228 86Q246 99 242 127L239 148 233 155Q239 123 223 107Z" fill="#c5c0b6" stroke="none"/>'
    elif tier == 3:
        blade = '<path d="M214 60 242 66 251 94 250 135 240 156 225 164 227 140Q238 118 214 104L204 88Z" fill="#738587"/><path d="m240 75 5 22-1 35-10 18 1-14 5-22-12-17Z" fill="#b9c9c3" stroke="none"/>'
    else:
        # A broad upper axe keeps both blade lobes outside the face silhouette.
        y = 16 if tier == 4 else 10
        left = 180 if tier == 4 else 171
        blade = f'''<path d="m220 {y+27} 10 3-8 63-13-4Z" fill="#895334" stroke-width="6"/>
          <path d="M219 {y+6} 242 {y} 251 {y+24} 245 {y+59} 232 {y+71} 227 {y+50} 217 {y+42} 203 {y+57} {left+6} {y+68} {left} {y+25} {left+9} {y} 209 {y+5}Z" fill="#738587"/>
          <path d="m240 {y+9} 5 18-6 26-5 7-1-19-10-8 9-7Z M{left+11} {y+10}l-5 17 3 23 8-6 6-14 10-8-11-8Z" fill="#b9c9c3" stroke="none"/>
          <path d="m214 {y+6} 13 0-5 35-13 4Z" fill="{color}" stroke-width="5"/>'''
        if tier == 5:
            blade += '<path d="m174 38-9-14 9-12 M249 41l3-12-6-10" fill="#b9c9c3" stroke-width="5"/>'
    add(parts, 'axe', 'tier_blade', f'<g stroke-width="6">{blade}</g>')
    if tier >= 3:
        add(parts, 'arm_back', 'metal_bracer_back', f'''<path d="m31 174 40 11-9 21-39-13Z" fill="#738587" stroke-width="5"/><path d="m32 180 26 8" stroke="#b9c9c3" stroke-width="5"/><path d="m29 190 28 8" stroke="{color}" stroke-width="4"/>''')
        add(parts, 'arm_front', 'metal_bracer_front', f'''<path d="m169 168 28-7 9 18-28 11Z" fill="#738587" stroke-width="5"/><path d="m178 172 17-5" stroke="#b9c9c3" stroke-width="5"/><path d="m180 183 15-5" stroke="{color}" stroke-width="4"/>''')
    if tier >= 4:
        add(parts, 'body', 'breastplate', f'''
          <path d="m97 145 54-2 20 20-10 24-67-1-7-24Z" fill="#738587" stroke-width="6"/>
          <path d="m102 150 43-1 15 13-30 10-32-11Z" fill="#b9c9c3" stroke="none"/>
          <path d="m103 178 42 0" stroke="{color}" stroke-width="6"/>''')
        # The shield belongs to the free hand, never the axe hand.
        extra = '<path d="M17 158 22 151 32 158 M61 158 72 151 77 164 M17 204 24 215 30 209 M63 210 72 215 79 200" fill="#b9c9c3" stroke-width="5"/>' if tier == 5 else ''
        add(parts, 'arm_back', 'round_shield', f'''
          <ellipse cx="46" cy="188" rx="34" ry="37" fill="#738587" stroke-width="6"/>
          <ellipse cx="46" cy="188" rx="25" ry="28" fill="{'#895334' if tier == 4 else '#4c5a5d'}" stroke-width="4"/>
          <path d="M25 188H67M46 164V212" stroke="{color}" stroke-width="7"/>
          <circle cx="46" cy="188" r="10" fill="#b9c9c3" stroke-width="5"/>{extra}''')
    if tier == 5:
        add(parts, 'head', 'open_helmet', f'''
          <path d="M70 83 73 58 90 37 116 27 145 31 172 49 181 79 167 81 153 63 112 61 88 83Z" fill="#738587" stroke-width="6"/>
          <path d="m86 55 15-13 21-8 19 4 18 11-21-4-22-1-24 16Z" fill="#b9c9c3" stroke="none"/>
          <path d="m111 28 20 1 7 34-23-3Z" fill="{color}" stroke-width="5"/>
          <path d="m71 57-15-14 2 30 17 10 M174 57l15-14-2 30-9 9" fill="#b9c9c3" stroke-width="6"/>''')


def golem(parts, tier, color):
    if tier < 2:
        return
    # Symmetric rigid fist covers: both arms retain the existing punch rig.
    big = tier >= 3
    for parent, mirror in [('arm_back_forearm', False), ('arm_front_forearm', True)]:
        transform = 'translate(256 0) scale(-1 1)' if mirror else ''
        shape = 'M7 174 35 166 66 181 68 207 49 229 18 226 5 207Z' if big else 'M15 181 36 174 59 184 59 204 45 219 22 216 13 203Z'
        xml = f'''<g transform="{transform}"><path d="{shape}" fill="#bba58b" stroke-width="6"/>
          <path d="m17 181 18-7 21 12-19 9-22-3Z" fill="#dfcbae" stroke="none"/>
          <path d="m37 197 20-10 3 15-16 17-20-4-9-11 16 4Z" fill="#887562" stroke="none"/>'''
        if tier >= 4:
            xml += f'''<path d="m7 180 10-4 4 39-10-6Z M52 177l11 6 2 24-13 14-8-6 11-15Z" fill="#738587" stroke-width="5"/>
              <path d="m25 202 17 0" stroke="{color}" stroke-width="6"/>'''
        if tier == 5:
            xml += '''<path d="M17 181 16 163 28 176 M37 175l5-21 8 26 M56 188l18-5-10 19" fill="#b9c9c3" stroke-width="5"/>
              <path d="m20 212 23 7-8 10-16-4Z" fill="#738587" stroke-width="5"/>'''
        add(parts, parent, 'fist_armor_' + parent, xml + '</g>')
    if tier >= 3:
        add(parts, 'arm_back_upper', 'shoulder_plate_back', '''<path d="M33 85 64 65 89 83 94 109 78 124 41 115 26 100Z" fill="#bba58b" stroke-width="6"/><path d="m39 86 24-15 18 13-16 14-29-4Z" fill="#dfcbae" stroke="none"/>''')
        add(parts, 'arm_front_upper', 'shoulder_plate_front', '''<path d="m171 103 13-19 24 8 18 20 1 28-23 10-29-14Z" fill="#bba58b" stroke-width="6"/><path d="m181 104 10-13 13 7 15 19-22 7-17-10Z" fill="#dfcbae" stroke="none"/>''')
    if tier >= 4:
        add(parts, 'body', 'stone_breastplate', f'''
          <path d="m97 153 30-5 34 10 8 24-17 16-46 0-17-19Z" fill="#bba58b" stroke-width="6"/>
          <path d="m105 163 23-5 25 9-8 16-33-3Z" fill="#dfcbae" stroke="none"/>
          <path d="m91 173 10 22 14 0 M164 174l-9 23-14 0" fill="none" stroke="#738587" stroke-width="8"/>
          <path d="m119 186 22 0" stroke="{color}" stroke-width="6"/>''')
    if tier == 5:
        for parent, xml in [
            ('arm_back_upper', 'M32 87 43 70 60 64 89 80 93 93 72 96 47 92Z'),
            ('arm_front_upper', 'M177 101 185 82 206 87 226 108 223 121 202 115Z'),
        ]:
            add(parts, parent, 'shoulder_reinforcement_' + parent, f'<path d="{xml}" fill="#738587" stroke-width="6"/>')
        add(parts, 'head', 'brow_plate', f'''
          <path d="m88 76 20-13 26 12 26-9 20 10-3 15-17-4-26 9-24-15-20 8Z" fill="#738587" stroke-width="6"/>
          <path d="m111 69 13 6-3 12-12-8Z M160 72l11 6-10 3-7 2Z" fill="#b9c9c3" stroke="none"/>
          <path d="m130 76 8 1-2 11" fill="none" stroke="{color}" stroke-width="5"/>''')


cards = []
for index, entity in enumerate(ENTITIES):
    original = ET.parse(ROOT / 'art/source' / entity / 'master.svg').getroot()
    for tier, color in enumerate(COLORS, 1):
        root = copy.deepcopy(original)
        root.find(f'{{{NS}}}title').text = f'{NAMES[index]} · уровень {tier} · preview only'
        parts = {g.get('id'): g for g in root.findall(f'{{{NS}}}g')}
        recolor(root, entity, color)
        globals()[entity](parts, tier, color)
        for item in root.iter():
            if 'id' in item.attrib:
                item.set('id', f'{entity}_lv{tier}_{item.get("id")}')
        svg = ET.tostring(root, encoding='unicode')
        (HERE / f'{entity}_lv{tier}.svg').write_text(svg + '\n', encoding='utf-8')
        hp = BASE_HP[index] * 2**(tier-1)
        hp_text = f'{hp}–{hp*2-1} HP' if tier < 5 else f'от {hp} HP'
        cards.append(f'''<article style="--tier:{color};--canvas:{CANVAS[index]}">
          <header><strong>{NAMES[index]}</strong><span class="tier">{tier}</span></header>
          <div class="stage"><div class="actor">{svg}</div></div>
          <div class="threshold">{hp_text} · ×{2**(tier-1)}</div>
          <p>{html.escape(CAPTIONS[entity][tier-1])}</p></article>''')

document = '''<!doctype html>
<html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Summoner Tower — экипировка врагов</title><link rel="icon" href="data:,">
<style>
*{box-sizing:border-box}body{margin:0;background:#101521;color:#cbd6ce;font:15px system-ui,sans-serif}
main{max-width:1520px;margin:auto;padding:28px}h1{margin:0 0 10px;font-size:28px;color:#e2bf70}
.intro{margin:0 0 18px;max-width:1050px;line-height:1.6;color:#9eb1ab}.intro b{color:#e2bf70}.intro a{color:#8abdee}
.controls{display:flex;gap:14px;align-items:center;flex-wrap:wrap;margin:0 0 18px;padding:14px;background:#192431;border-radius:10px}
button,select{font:inherit;background:#293a47;color:#dbe5da;border:1px solid #4d6268;padding:9px 14px;border-radius:7px;cursor:pointer}
button[aria-pressed=true]{background:#e2bf70;color:#171b22;border-color:#e2bf70}label{display:flex;align-items:center;gap:8px}
.note{color:#9eb1ab;font-size:13px;flex:1;min-width:220px}.grid{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:12px}
article{border:1px solid #33433f;border-top:3px solid var(--tier);border-radius:10px;overflow:hidden;background:#192c25;min-width:0}
header{display:flex;align-items:center;justify-content:space-between;padding:12px 14px;background:#19262c;font-size:18px}
.tier{display:inline-flex;justify-content:center;align-items:center;width:28px;height:28px;border-radius:50%;background:var(--tier);color:#101521;font-weight:800}
.stage{height:245px;position:relative;display:flex;align-items:flex-end;justify-content:center;background:radial-gradient(ellipse at 50% 84%,#304b36 0,transparent 60%);padding-bottom:0}
.actor{width:calc(var(--canvas) / 140 * 238px);height:calc(var(--canvas) / 140 * 238px);flex:none;position:relative;transform:translateY(-12px)}
.actor:before{content:"";position:absolute;background:#0c1719;opacity:.55;border-radius:50%;width:74%;height:8%;bottom:5%;left:13%}
.actor svg{position:relative;display:block;width:100%;height:100%}.threshold{text-align:center;font-size:13px;color:var(--tier);margin-top:4px}
article p{min-height:44px;text-align:center;font-size:13px;line-height:1.45;margin:8px 10px 14px;color:#c3cdc4}
footer{margin-top:18px;font-size:13px;line-height:1.6;color:#8fa39f}
body.game .actor{width:calc(var(--canvas) * var(--factor) * var(--screen) * 1px);height:calc(var(--canvas) * var(--factor) * var(--screen) * 1px)}
body.game .stage{height:150px;background:repeating-linear-gradient(90deg,transparent 0,transparent calc(var(--cell) - 1px),#32453b var(--cell)),repeating-linear-gradient(0deg,transparent 0,transparent calc(var(--cell) - 1px),#32453b var(--cell)),#1b3028}
@media(max-width:850px){main{padding:16px}.grid{min-width:1000px}.scroll{overflow-x:auto}h1{font-size:23px}.stage{height:220px}.actor{width:calc(var(--canvas) / 140 * 210px);height:calc(var(--canvas) / 140 * 210px)}}
</style></head><body><main><h1>Экипировка врагов · 5 уровней</h1>
<p class="intro">Сравнение уровней <b>гоблина, орка и голема</b>. Босса не меняем. Кожа и камень сохраняют исходные цвета; цвет уровня обозначают одежда, мох и акценты экипировки. Внешний вид принят, экипировка подключена к существующим ригам. <a href="http://127.0.0.1:4175/preview/enemy-equipment-animation/?asset=goblin&tier=5">Посмотреть анимации</a>.</p>
<div class="controls"><button id="large" aria-pressed="true">Крупный просмотр</button><button id="game" aria-pressed="false">Игровой масштаб</button>
<label>Сетка <select id="columns"><option value="6">6 столбцов</option><option value="7" selected>7 столбцов</option><option value="8">8 столбцов</option></select></label>
<label>Ширина экрана <select id="screen"><option value="390" selected>390 px · телефон</option><option value="450">450 px</option><option value="720">720 px · логический</option></select></label>
<span class="note" id="note"></span></div><div class="scroll"><div class="grid">__CARDS__</div></div>
<footer>Слева направо: зелёный → оранжевый → красный → синий → фиолетовый. Пороги — удвоение базового HP; это существующая логика, не новый баланс.<br>
Броня накапливается, оружие заменяется. У голема усиление обеих рук сохраняет двуручный удар. Здесь показана неподвижная поза; анимации проверены при интеграции. Внешний вид и игровая интеграция приняты пользователем.</footer>
</main><script>
const large=document.querySelector('#large'),game=document.querySelector('#game'),columns=document.querySelector('#columns'),screen=document.querySelector('#screen');
function update(){const cell=720/Number(columns.value),factor=Math.min((cell-12)/140,1),ratio=Number(screen.value)/720;
 document.body.style.setProperty('--factor',factor);document.body.style.setProperty('--screen',ratio);document.body.style.setProperty('--cell',`${cell*ratio}px`);
 document.querySelector('#note').textContent=`Игровые размеры canvas: гоблин ${(86.4*factor*ratio).toFixed(0)} px · орк ${(120*factor*ratio).toFixed(0)} px · голем ${(140*factor*ratio).toFixed(0)} px`;
}function mode(on){document.body.classList.toggle('game',on);large.setAttribute('aria-pressed',!on);game.setAttribute('aria-pressed',on);update()}
large.onclick=()=>mode(false);game.onclick=()=>mode(true);columns.onchange=screen.onchange=update;update();
</script></body></html>'''
(HERE / 'index.html').write_text(document.replace('__CARDS__', '\n'.join(cards)), encoding='utf-8')
print(f'Created 15 SVG previews and self-contained HTML in {HERE}')
