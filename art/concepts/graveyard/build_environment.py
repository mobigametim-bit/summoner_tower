"""Graveyard environment concepts, all geometry authored as SVG code."""
from html import escape
from pathlib import Path
import re

INK = '#29180f'
SOIL = '#303838'


def path(d, fill, stroke=INK, width=5, opacity=1):
    return f'<path d="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{width}" opacity="{opacity}"/>'


def oval(x, y, rx, ry, fill, opacity=1):
    return f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{fill}" stroke="none" opacity="{opacity}"/>'


def ground():
    # Edge-to-edge soil, no border or grass rim. All marks stay inside the tile.
    s = path('M0 0H256V256H0Z', SOIL, 'none', 0)
    s += path('m26 34 41-8 26 18-17 20-39-6Z m118 104 51-10 25 19-16 29-54-5Z', '#343e3b', 'none', 0)
    s += path('m30 178 17-5 23 6-4 6-34 1Z m133-125 20-5 11 5-5 7-21-1Z', '#485044', 'none', 0)
    s += path('m114 32 8 2 m79 62 7-2 M34 117l6 2 m91 96 6-1 m88 10 8 1', 'none', '#596057', 3)
    s += path('m84 122 10-6 8 5-5 6-11 0Z m101 76 12-8 9 7-5 7-12 0Z', '#525958', 'none', 0)
    return s


def road():
    s = ground()
    # Cobblestones touch top/bottom edges; no colored rectangular underlay.
    s += path('M40-8H216V264H40Z', '#555b57', '#414844', 8)
    for y in (-8, 56, 120, 184, 248):
        s += path(f'M49 {y+4}H113L118 {y+58} 49 {y+61}Z', '#87887a', '#444b46', 5)
        s += path(f'M128 {y+6} 205 {y+3} 206 {y+60} 127 {y+58}Z', '#999783', '#444b46', 5)
        s += path(f'M56 {y+13} 104 {y+13} M137 {y+14} 193 {y+11}', 'none', '#b3b09a', 3)
    return s


def pedestal():
    s = oval(128, 220, 101, 17, '#111e23', .45)
    s += path('M30 156 49 138H207L226 156V200L207 218H49L30 201Z', '#525e65', '#293536', 7)
    s += path('M30 164H226L216 193H40Z', '#727e80', '#374449', 5)
    s += path('M39 157 57 139H199L217 157 202 180H54Z', '#a4aaa1', '#414d50', 6)
    s += path('M61 157H195 M72 167H184', 'none', '#c5c7b7', 4)
    s += path('m48 190 14 0 0 16-14-3Z m146 0 14 0-1 13-13 3Z', '#929b93', '#414d50', 3)
    s += path('m116 190 12-8 12 8-12 12Z', '#a5c8b6', '#414d50', 3)
    return s


def portal():
    s = oval(128, 235, 91, 13, '#101e24', .6)
    s += oval(128, 143, 54, 84, '#53706b', .18)
    s += path('M74 219V105Q75 42 128 39 181 42 182 105V219Z', '#213a39', '#242d2c', 8)
    s += path('M82 217V112Q84 63 128 59 172 63 174 112V217Z', '#386a62', 'none', 0)
    s += oval(128, 141, 41, 70, '#579b85', .65)
    s += path('M123 202Q174 163 143 115 120 86 101 116 87 148 121 155 146 156 139 135 130 118 117 134', 'none', '#b3f4cc', 8)
    s += path('M107 191Q84 160 99 132 M145 95q22 28 12 49', 'none', '#dcffe5', 4, .8)
    s += path('M59 223V110Q58 33 128 24 198 33 197 110V223H175V112Q174 56 128 48 82 56 81 112V223Z', '#737e76', '#2f3c39', 7)
    s += path('M61 112 79 113 M64 79l20 7 M82 48l16 17 M158 64l17-17 M175 86l19-7 M177 114l19-1 M60 151h19 M60 187h19 M177 151h19 M177 187h19', 'none', '#3f4d47', 5)
    s += path('m109 26 11-11 21 0 12 12-4 22-12 10h-16l-12-12Z', '#d9d6b8', INK, 5)
    s += oval(120, 34, 5, 7, '#29473f') + oval(140, 34, 5, 7, '#29473f')
    s += path('m126 45 5-6 4 6 M122 54v-6 m15 6v-6', 'none', '#514e3c', 3)
    s += path('M51 222H205L216 240H40Z', '#8c978a', '#34423c', 6)
    for x, y, r in ((94,94,5),(158,163,6),(105,190,4),(143,75,4),(119,168,5)):
        s += oval(x, y, r+4, r+7, '#7ee8b2', .18) + oval(x, y, r, r+2, '#b8ffd2', .85)
    return s


def dead_tree():
    s = oval(126, 231, 85, 12, '#121e23', .5)
    s += path('M93 229 105 197 103 152 83 133 56 125 30 94 47 98 68 110 91 113 75 84 76 55 91 77 101 97 113 104 114 59 102 31 118 41 130 66 130 93 148 79 160 47 174 27 170 62 159 94 142 116 140 144 166 133 183 102 203 82 196 114 179 145 143 168 146 205 162 231 135 224 120 234Z', '#686859', INK, 7)
    s += path('m114 223 10-35-4-56 4-23 M138 157l-3 40 7 25', 'none', '#8a8870', 6)
    s += path('m76 228 14-9 13 4-9 12Z m63-1 19-6 14 12-25 3Z', '#454f40', 'none', 0)
    return s


def headstone(cross=False):
    s = oval(127, 230, 81, 11, '#111e23', .45)
    if cross:
        s += path('M106 202V117H69V80H107V42H148V80H187V117H147V202Z', '#8a9185', '#343b38', 7)
        s += path('m114 50 17 0v142h-17 M78 89h27', 'none', '#b6b7a0', 6)
        s += path('m146 98-14 16 10 13-12 16', 'none', '#515c52', 4)
    else:
        s += path('M67 205 76 84Q85 42 130 42 181 43 187 85L192 205Z', '#858d84', '#343b38', 7)
        s += path('M84 175 90 86Q99 60 128 59', 'none', '#b1b4a0', 6)
        s += path('m114 90 17-11 18 11-4 21-28 0Z', '#535f55', 'none', 0)
        s += path('M105 135h49 m-45 16h35 m21 19-14 14 7 12', 'none', '#525d54', 5)
    s += path('M59 201H199L210 226H46Z', '#66766a', '#34453b', 6)
    s += path('m52 217 26-7 13 7-12 10H47Z m121-5 21 4 8 13-32-1Z', '#586b4c', 'none', 0)
    return s


def crypt():
    s = oval(128, 230, 107, 15, '#101e23', .45)
    s += path('M38 111H218V223H38Z', '#727a74', '#323e3a', 7)
    s += path('M24 110 128 37 232 110Z', '#92998b', '#34403b', 7)
    s += path('m47 102 81-54 82 54Z', '#67776a', 'none', 0)
    s += path('M90 222V155Q90 124 128 124 166 124 166 155V222Z', '#263436', '#424d45', 6)
    s += path('M101 220V160Q101 139 128 137 155 139 155 160V220 M128 141v76', 'none', '#4c6257', 6)
    s += path('M44 136h35 m99 0h34 M44 176h35 m99 0h34 M58 114v106 M199 114v106', 'none', '#505e52', 5)
    s += path('M29 221H227L238 237H18Z', '#909a88', '#34403b', 6)
    s += path('m116 86 12-15 12 15-12 13Z', '#ade4be', '#34403b', 4)
    return s


def fence():
    s = oval(128, 214, 113, 12, '#111e23', .4)
    s += path('M19 140H237M19 181H237', 'none', '#222e2e', 12)
    s += path('M19 138H237 M19 179H237', 'none', '#68756b', 4)
    for x, y in ((36,67),(96,55),(156,65),(216,73)):
        s += path(f'M{x} 207V{y+22}', 'none', '#253331', 13)
        s += path(f'M{x+2} 199V{y+22}', 'none', '#718174', 4)
        s += path(f'M{x-10} {y+22} {x} {y} {x+10} {y+22}Z', '#778278', '#26332f', 4)
    return s


def remains():
    s = oval(128, 204, 92, 20, '#111e23', .4)
    # Bones lie side by side in perspective, rather than crossing as a pirate emblem.
    s += path('M124 192 195 183 M146 212l57-13 M76 203l26 15', 'none', INK, 12)
    s += path('M124 192 195 183 M146 212l57-13 M76 203l26 15', 'none', '#d9d0ad', 7)
    s += path('M57 171Q59 145 90 147 113 149 117 168L113 190 94 203 67 197 55 186Z', '#e6ddbd', INK, 6)
    s += oval(72, 173, 7, 9, '#41433b') + oval(96, 169, 8, 9, '#41433b')
    s += path('m82 183 6-7 6 8 M70 196l15-7 21 0', 'none', '#5c5c4c', 4)
    s += path('m117 169 15-7 28 2 11 7 m-47 7 11-5 25 2', 'none', '#c2bd9e', 6)
    return s


def candles():
    s = oval(129, 220, 76, 13, '#111e23', .4)
    for x, y, h in ((79,148,59),(124,117,90),(163,160,47)):
        s += oval(x+11, y-15, 23, 32, '#f6c776', .09)
        s += path(f'M{x} {y}H{x+22}V{y+h}H{x}Z', '#cfb98a', '#544635', 4)
        s += path(f'M{x+4} {y+4}v12 m13-9v20', 'none', '#f4dd9f', 4)
        s += path(f'M{x+5} {y-3}Q{x-4} {y-14} {x+13} {y-33} {x+28} {y-14} {x+18} {y-3}Z', '#ffc96a', '#6e5034', 3)
    return s


def lantern():
    s = oval(126, 230, 61, 10, '#111e23', .45)
    s += path('M120 221V49Q120 28 145 29H171', 'none', '#2a3631', 14)
    s += path('M123 215V50Q123 34 144 34H165', 'none', '#7c8676', 5)
    s += oval(174, 111, 40, 44, '#7cd5a9', .1)
    s += path('M149 73H197L203 134 173 149 144 134Z', '#314e43', '#2b3933', 5)
    s += path('M155 83H191L194 127 174 136 153 126Z', '#8de2b2', '#4a6c55', 4)
    s += path('m168 122-6-9 8-21 14 24-5 10Z', '#e0ffdb', 'none', 0)
    s += path('M143 72 173 54 204 72Z M173 56V35 M174 78v62', 'none', '#637760', 6)
    s += path('m105 220 36 0 8 14H97Z', '#737c68', '#344034', 5)
    return s


def flowers():
    s = oval(128, 214, 77, 10, '#111e23', .35)
    s += path('M93 214 82 160 M131 211l7-62 M158 213l18-46 m-80 32-17-14 m54 12 19-18', 'none', '#677057', 6)
    for x, y in ((81,155),(138,142),(178,165)):
        s += path(f'M{x} {y-16}Q{x+9} {y-21} {x+12} {y-7} {x+29} {y+1} {x+11} {y+9} {x+7} {y+23} {x-4} {y+10} {x-24} {y+5} {x-12} {y-6} {x-14} {y-20} {x} {y-16}Z', '#aaa2a0', '#504942', 4)
        s += oval(x, y, 6, 6, '#c6b78b')
    return s


def coffin():
    s = oval(127, 212, 96, 21, '#111e23', .45)
    s += path('M49 155 87 125 161 128 210 164 198 211 83 219 47 198Z', '#51473b', INK, 6)
    s += path('M49 155 87 125 161 128 210 164 187 187 80 197 47 177Z', '#897355', INK, 6)
    s += path('m76 158 26-17 51 3 35 20-15 12-86 8Z', '#655840', '#3d362c', 4)
    s += path('m130 149 6 25 m-20-11 33-2', 'none', '#c0ae82', 6)
    s += path('m62 191 14 9 m113-4 12-8', 'none', '#a6a58e', 5)
    return s


ASSETS = {
    'ground': ('Земля', 'Холодная почва, мох и редкие камешки. Без рамки клетки.', ground),
    'road': ('Дорога', 'Старая мощёная дорожка; края плиток стыкуются.', road),
    'pedestal': ('Постамент', 'Каменная плита склепа с открытой площадкой для бойца.', pedestal),
    'portal': ('Портал', 'Костяная арка с мятно-зелёным вихрем душ.', portal),
    'dead_tree': ('Мёртвое дерево', 'Короткий сухой ствол и крупные развилки.', dead_tree),
    'headstone': ('Надгробие', 'Старая плита с трещиной и мхом у основания.', headstone),
    'grave_cross': ('Каменный крест', 'Крупный простой силуэт, без мелких надписей.', lambda: headstone(True)),
    'crypt': ('Склеп', 'Низкий склеп; крупный декор для свободного места.', crypt),
    'fence': ('Ограда', 'Небольшой участок старой железной ограды.', fence),
    'remains': ('Останки', 'Череп, рёбра и кости лежат на земле.', remains),
    'candles': ('Свечи', 'Тёплый акцент среди холодной почвы.', candles),
    'lantern': ('Фонарь душ', 'Мягкий зеленоватый огонь в старом фонаре.', lantern),
    'flowers': ('Увядшие цветы', 'Серо-лиловые цветки и тусклые стебли.', flowers),
    'coffin': ('Гроб', 'Закрытый старый гроб, лежащий на земле.', coffin),
}


def wrap(name, body, width=256, height=256):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}"><title>{escape(name)}</title><g stroke-linecap="round" stroke-linejoin="round">{body}</g></svg>\n'


def battlefield(character_bodies):
    # Static art arrangement, independent of gameplay generation and its parameters.
    s = '<defs><clipPath id="field"><rect width="640" height="800"/></clipPath>'
    for key, (_, _, draw) in ASSETS.items():
        s += f'<g id="env_{key}">{draw()}</g>'
    for key, body in character_bodies.items():
        s += f'<g id="actor_{key}" stroke="{INK}" stroke-width="7">{body}</g>'
    tower_source = Path(__file__).resolve().parents[3] / 'art/source/tower/master.svg'
    tower = tower_source.read_text(encoding='utf-8')
    tower_view = re.search(r'viewBox="([^"]+)"', tower).group(1).split()
    tx, ty, tw, th = map(float, tower_view)
    tower = re.sub(r'^.*?<svg[^>]*>', '', tower, flags=re.S)
    tower = re.sub(r'</svg>\s*$', '', tower)
    s += f'<g id="existing_tower">{tower}</g></defs><g clip-path="url(#field)">'
    for row in range(10):
        for col in range(8):
            angle = ((row*3+col)%4)*90
            s += f'<use href="#env_ground" transform="translate({col*80} {row*80}) scale(.3125) rotate({angle} 128 128)"/>'
    d = 'M440-15V120H120V360H440V600H280V767'
    s += path(d, 'none', '#414944', 64)
    s += path(d, 'none', '#727a6b', 54)
    # Individually laid paving stones, with no green rectangular road tiles.
    centers = [(440,y,False) for y in range(0,121,40)]
    centers += [(x,120,True) for x in range(120,440,40)]
    centers += [(120,y,False) for y in range(160,361,40)]
    centers += [(x,360,True) for x in range(160,441,40)]
    centers += [(440,y,False) for y in range(400,601,40)]
    centers += [(x,600,True) for x in range(280,440,40)]
    centers += [(280,y,False) for y in range(640,800,40)]
    for i, (x,y,horizontal) in enumerate(centers):
        fill = ('#92917e','#818675','#a09b86')[i%3]
        s += f'<g transform="translate({x} {y}) rotate({90 if horizontal else 0})">'
        s += path('M-22-17 0-16-1 16-22 17Z', fill, '#464e45', 3)
        s += path('M4-16 22-18 23 16 4 15Z', '#a19d89', '#464e45', 3) + '</g>'
    def place(key, col, row, size=80):
        nonlocal s
        x, y = (col+.5)*80-size/2, (row+1)*80-size
        s += f'<use href="#env_{key}" transform="translate({x} {y}) scale({size/256})"/>'
    for key,col,row,size in (
        ('dead_tree',0,0,80),('headstone',2,0,70),('lantern',6,0,80),('grave_cross',7,1,82),
        ('flowers',3,2,67),('candles',6,2,75),('crypt',7,3,110),('headstone',0,4,75),
        ('remains',3,3,82),('dead_tree',7,5,100),('coffin',3,5,90),('headstone',0,6,75),
        ('fence',6,7,110),('flowers',6,8,70),('grave_cross',1,8,82),('candles',4,9,74)):
        place(key,col,row,size)
    for col,row in ((3,0),(0,2),(2,2),(0,3),(2,3),(2,5),(4,5),(6,5),(2,7),(4,8)):
        place('pedestal',col,row)
    place('portal',5,0,80)
    for key,x,y,size in (('skeleton',354,120,79),('zombie',240,123,82),('priest',280,50,64),('necromancer',124,261,83)):
        s += f'<use href="#actor_{key}" transform="translate({x-size/2} {y-size*.9}) scale({size/256})"/>'
    size=103
    s += f'<use href="#existing_tower" transform="translate({280-size/2} {800-size}) scale({size/tw} {size/th}) translate({-tx} {-ty})"/>'
    s += '</g>'
    return wrap('Кладбище — пример композиции поля, не игровой генератор',s,640,800)


def build(root, character_bodies):
    for key,(name,_,draw) in ASSETS.items():
        (root/f'env_{key}.svg').write_text(wrap(name,draw()),encoding='utf-8')
    (root/'battlefield.svg').write_text(battlefield(character_bodies),encoding='utf-8')
    def card(key):
        name,note,_=ASSETS[key]
        return f'<article class="card" style="--tier:#a5c8b6"><div class="level">{name}</div><a href="env_{key}.svg" target="_blank"><img src="env_{key}.svg" alt="{name}" width="256" height="256"></a><p>{note}</p></article>'
    terrain = '<section id="environment" data-entity="environment"><h2>Земля, дорога, постамент и портал</h2><p class="subtitle">Собственные SVG-концепты окружения. Вихрь и свечение пока статичные — анимация обсуждается отдельно.</p><div class="cards terrain">'+''.join(card(k) for k in list(ASSETS)[:4])+'</div></section>'
    decorations = '<section id="decorations" data-entity="decorations"><h2>Декорации кладбища</h2><p class="subtitle">10 концептов. Останки и гроб лежат на земле; обломков стен нет.</p><div class="cards">'+''.join(card(k) for k in list(ASSETS)[4:])+'</div></section>'
    field = '<section id="battlefield" data-entity="battlefield"><h2>Пример игрового поля</h2><p class="subtitle">Композиция для оценки сочетания ассетов. Башня — существующая. Это статичное превью, размеры и размещение ещё не меняют генератор игры.</p><a href="battlefield.svg" target="_blank"><img class="field" src="battlefield.svg" width="640" height="800" alt="Пример поля кладбища"></a></section>'
    return terrain+decorations+field
