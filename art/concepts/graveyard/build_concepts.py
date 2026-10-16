"""Hand-authored SVG concept sheets. Shapes are written here; no image models/assets."""
from pathlib import Path
from html import escape
import math
from build_environment import build as build_environment

ROOT = Path(__file__).resolve().parent
INK = '#29180f'
BONE = '#e9dfbe'
BONE_SHADE = '#b6ac91'
METAL = '#87959d'
METAL_LIGHT = '#b5c0bd'
GOLD = '#e6b85a'
TIERS = ['#88b96b', '#ec9b49', '#df5654', '#5295ef', '#b66dea']
TIER_NAMES = ['Зелёный', 'Оранжевый', 'Красный', 'Синий', 'Фиолетовый']


def shade(color, factor):
    return '#' + ''.join(f'{min(255, round(int(color[i:i+2], 16)*factor)):02x}' for i in (1, 3, 5))


def p(d, fill='none', sw=None, stroke=None, opacity=None):
    attrs = f'd="{d}" fill="{fill}"'
    if sw is not None:
        attrs += ' stroke="none"' if sw == 0 else f' stroke-width="{sw}"'
    if stroke:
        attrs += f' stroke="{stroke}"'
    if opacity is not None:
        attrs += f' opacity="{opacity}"'
    return f'<path {attrs}/>'


def ellipse(x, y, rx, ry, fill, sw=0):
    return f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{fill}" stroke="{INK if sw else "none"}" stroke-width="{sw}"/>'


def circle(x, y, r, fill, sw=0):
    return ellipse(x, y, r, r, fill, sw)


def rect(x, y, w, h, fill, rx=4, sw=5):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" stroke="{INK if sw else "none"}" stroke-width="{sw}"/>'


def group(name, content, transform=None):
    return f'<g id="{name}"' + (f' transform="{transform}"' if transform else '') + '>' + content + '</g>'


def shadow():
    return '<ellipse cx="128" cy="239" rx="82" ry="10" fill="#0b1520" opacity=".35" stroke="none"/>'


def skull(x=0, y=0, scale=1, eye='#94e7b4'):
    s = p('M82 55Q101 32 132 37 170 35 180 66L183 96Q181 113 167 121L165 137Q133 151 100 137L97 122Q77 112 74 94L75 73Z', BONE)
    s += p('M83 68 96 58 91 90 98 111 108 117 105 134 99 127 99 119Q80 111 79 93Z', BONE_SHADE, 0)
    s += p('m96 53 32-10 28 6-19 7-21-2-22 9Z', '#fff0ce', 0)
    s += p('M88 83 116 88 114 106Q92 112 88 95Z M143 89l27-9-1 17Q164 108 146 107Z', '#332c29', 4)
    s += p('m95 93 14 3-4 6-9-2Z m55 1 12-4-2 8-10 3Z', eye, 0)
    s += p('m126 105-7 14 16 1Z', '#51493c', 0)
    s += p('m112 125 0 12 m14-10v12 m14-12v11 m13-15v11', 'none', 4)
    return group('skull', s, f'translate({x} {y}) scale({scale})')


def shoulder(x, y, color, size=1):
    return group('pauldron', p('M-18-9Q1-21 19-6L23 11 5 20-22 10Z', METAL, 5) + p('m-14-5 14-7 14 8-12 5Z', METAL_LIGHT, 0) + p('m-17 11 20 4 14-5', 'none', 5, color), f'translate({x} {y}) scale({size})')


def sword(level, color):
    blade = p('m207 156 7-69 14-18 10 22-17 70Z', '#d9dfd7', 5)
    blade += p('m220 91 7-14-8 77-7 0Z', '#8b9a9c', 0)
    blade += p('m201 155 28 4-1 11-29-4Z', color, 5)
    blade += p('m207 169 12 1-3 31-13-2Z', '#7e5138', 5)
    if level >= 4:
        blade += p('m222 108 15 3-4 11-13-3Z', color, 4)
    return group('sword', blade)


def skeleton(level):
    c, dark = TIERS[level-1], shade(TIERS[level-1], .68)
    s = shadow()
    # Separate rounded bones and real empty gaps, rather than a filled pale torso.
    def bone(d, width=7):
        return p(d, 'none', width+5, INK) + p(d, 'none', width, BONE)
    s += group('back_arm', bone('M92 141 70 151 M67 158 48 174')
               + circle(68, 154, 6, BONE, 3) + bone('m48 174-7 8 7 5 7-7', 5))
    s += group('legs', bone('m110 196-9 17 m-2 8-3 9 m58-34 4 17 m2 8 5 9')
               + circle(100, 217, 5, BONE, 3) + circle(159, 217, 5, BONE, 3)
               + bone('m96 230-10 4 20 0 m59-4 10 4-21 0', 6))
    if level >= 2:
        s += p('m86 219 24 1 5 15-34 1Z m53 0 24-2 4 17-38 0Z', dark, 5)
    ribs = bone('M129 131 129 184', 7)
    ribs += bone('M129 140Q114 133 102 141 M129 140Q144 133 156 141', 6)
    ribs += bone('M103 151Q110 157 124 156 M155 151Q148 157 134 156', 6)
    ribs += bone('M107 166Q114 172 124 170 M151 166Q144 172 134 170', 6)
    ribs += bone('M111 180Q119 185 129 185 140 185 147 180', 5)
    s += group('ribcage', ribs)
    s += group('pelvis', p('M106 190 116 186 129 195 142 186 152 190 148 203 137 208 129 201 120 208 110 203Z', BONE, 4)
               + p('m115 193 7 3-5 5Z m23 3 7-3-2 8Z', INK, 0))
    s += p('m120 201 17 0 6 12-13-5-12 7Z', c, 4)
    s += group('front_arm', bone('M164 141 180 153 M185 158 201 179')
               + circle(182, 155, 6, BONE, 3))
    s += p('m188 166 9-5 6 9-9 6Z', c, 4)
    s += skull()
    if level >= 2:
        s += p('M80 65Q80 34 121 30 165 24 178 60L176 74 154 65 113 64 86 76Z', c, 6)
        s += p('m88 58 39-8 40 8 1 12-42-8-40 10Z', METAL, 4)
    if level >= 3:
        s += shoulder(80, 139, c)
        s += p('M35 147 62 143 79 157 70 188 52 200 32 182Z', '#7f6044', 5)
        s += p('m41 153 17-3 12 12-8 21-11 9-12-15Z', c, 4)
        s += circle(54, 167, 7, METAL_LIGHT, 4)
    if level >= 4:
        # Side plates leave the central ribs and gaps readable even at high levels.
        s += p('m99 144 9 3-4 24-10-3Z m55-24 9-3 5 24-10 3Z', METAL, 4)
        s += p('m97 155 8 1 m52-1 8-1', 'none', 4, c)
        s += p('m127 32 11 3-4 39-9 17-8-9Z', METAL, 5)
        s += shoulder(172, 139, c, .85)
    if level >= 5:
        s += p('m87 43-13-23 26 12 24-12 26 10 23-11-6 25-38-7Z', c, 6)
        s += p('m88 149-14-18-10 15 m108 4 10-18 12 13', 'none', 6, BONE)
    s += sword(level, c)
    s += ellipse(203, 184, 12, 11, BONE, 5)
    return s


def zombie(level):
    c, dark = TIERS[level-1], shade(TIERS[level-1], .65)
    skin, shade_skin = '#91a58a', '#667c67'
    s = shadow()
    if level >= 5:
        s += p('m46 80 42 7 7 95-53 8-13-69Z', '#625348', 6)
        s += p('m43 96 36 0 m-37 27 39-4 m-35 29 35-6', 'none', 5, '#9d8771')
    s += p('M77 144Q53 137 43 155L35 187Q41 205 58 198L83 168Z', skin)
    s += p('m43 172 15 6-4 16-11-2Z', shade_skin, 0)
    s += p('m94 204 25 1-5 24 5 9-37 0 0-12Z m48 1 25-4 4 25 12 11-40 2-4-15Z', '#6b4936', 6)
    s += p('M84 127Q124 113 165 134 190 158 181 197L171 219 91 222 70 199 69 161Z', skin)
    s += p('M82 141 100 135 111 151 96 179 79 185 74 174Z M143 137l21-2 13 22 4 30-24-7-10-27Z', c, 5)
    s += p('M80 193Q120 205 180 187L177 209 163 224 88 223 76 210Z', c, 6)
    s += p('m84 208 40 5 35-9 12 8-12 10-66-1Z', dark, 0)
    s += p('m112 165 25 12 12 20 m-32-29-6 9 m16-3-6 10 m17-2-7 9', 'none', 4)
    s += p('M171 145Q188 137 201 150L216 175 208 191 188 177 168 164Z', skin, 6)
    s += p('m192 158 18 9-5 14-16-12Z', c, 5)
    s += group('head', p('M80 66Q94 34 135 40 177 43 185 80L182 119Q169 149 130 151L92 135 77 112Z', skin) + p('M83 76 94 71 90 104 104 126 137 143 119 144 93 133 82 112Z', shade_skin, 0) + p('m87 66 6-27 14 8 13-20 9 17 21-10 14 22-30-3-25 15Z', '#34433d', 5) + p('m90 90 22 6 m-13-15 0 27', 'none', 5) + ellipse(153, 94, 13, 15, '#d8d6a1', 5) + circle(154, 95, 5, '#2b3c30') + p('M113 118Q137 108 162 119L160 134 132 139 111 130Z', '#483d32', 5) + rect(121, 116, 10, 12, BONE, 1, 2) + rect(143, 117, 10, 10, BONE, 1, 2))
    if level >= 2:
        s += p('m78 72 101-1 3 17-99 1Z', c, 5)
        s += rect(93, 212, 18, 18, '#8c9a9c', 3, 4)
    if level >= 3:
        s += shoulder(76, 143, c, 1.1)
        s += p('m139 69 19-23 20 18-2 17Z', METAL, 5)
    if level >= 4:
        s += shoulder(178, 146, c, .9)
        s += p('m111 151 30-8 17 20-6 21-38 6-14-20Z', METAL, 6)
        s += p('m113 155 15-5 5 29-19 3Z', METAL_LIGHT, 0)
        s += p('m139 157 14 8-5 12-12 0Z', c, 0)
    weapon = p('m215 174 10 2-8 56-12 0Z', '#80563b', 5)
    if level < 3:
        weapon += p('m205 125 21-3 11 38-34 2Z', '#8b6946', 6)
        weapon += p('m209 135 21 3 m-20 13 22 2', 'none', 4, '#b68d5b')
    else:
        weapon += p('m213 162-15-18 8-32 33 3 0 39-14 12Z', METAL_LIGHT, 6)
        weapon += p('m222 120 12 0-1 29-13 10Z', '#697d84', 0)
    s += weapon + ellipse(211, 184, 14, 12, skin, 5)
    return s


def ghoul(level):
    c, dark = TIERS[level-1], shade(TIERS[level-1], .65)
    skin, sh = '#a393a5', '#756b83'
    s = shadow()
    s += p('M81 112 76 85 93 99 102 77 113 100 128 85 137 119Z', BONE_SHADE, 5)
    s += p('m101 196 19 3-16 22 6 14-33 2-4-11Z m45-39 25-1 0 23 20 15-38 2-15-16Z', sh, 6)
    s += p('m81 219 22 2 7 14-33 2Z m61-2 29 10-1 10-38-1Z', dark, 5)
    s += p('M91 122Q130 103 165 132L170 165 151 203 104 208 78 179 78 148Z', skin)
    s += p('m86 152 19 15 4 29-19-12-7-19Z', sh, 0)
    s += p('m103 191 47-4 12 21-16 5-17-8-17 10-17-10Z', c, 5)
    s += p('M85 143Q69 133 59 145L42 173 39 202 58 212 74 192 72 178 97 159Z', skin, 6)
    s += p('M158 142Q178 127 191 147L207 180 217 201 201 216 180 201 175 179 150 163Z', skin, 6)
    s += p('m42 184 26 7-4 16-25-9Z m145 2 25-10 7 14-26 11Z', c, 5)
    s += p('m43 207-16 21 7-26 m19 10-12 23 1-29 m23 4-6 22-5-20 M191 208l-3 25 12-22 m5-2 5 25 5-33 m3 0 16 22-6-29', BONE, 4)
    s += group('head', p('M82 75 65 64 66 92 79 105 M172 74l22-12-8 28-13 9', skin, 5) + p('M89 60Q122 39 152 56L176 75 180 104Q176 132 154 146L117 146 88 128 78 104 80 83Z', skin) + p('m85 84 13 11-2 20 19 20-20-9-11-20Z', sh, 0) + p('m99 61 21-16 24 8 11 13-22-4-12 6Z', '#c4b4c2', 0) + p('m91 89 28 5-4 16-19 0Z m49 5 27-11-3 20-20 6Z', '#302a34', 4) + p('m98 99 14 1 m38-1 10-4', 'none', 4, '#a6e6ba') + p('M111 124Q136 115 161 122L152 137 127 140Z', '#473544', 4) + p('m117 125 7 17 6-19 m15 0 5 16 8-18', BONE, 3))
    if level >= 2:
        s += p('m89 65 71 9-3 12-70-8Z', c, 5)
    if level >= 3:
        s += shoulder(82, 141, c, .85)
        s += p('m77 130-7-20 18 13 m-7 16-20-6 11 16', BONE, 4)
    if level >= 4:
        s += p('m40 176 29 5 4 17-34-4Z m142 4 26-14 8 17-25 14Z', METAL, 5)
        s += p('m103 198 22-6 3 13-20 8Z', METAL, 4)
    if level >= 5:
        s += p('m151 67 15-19 10 19-9 17Z M87 70 73 52 69 79 84 89Z', c, 5)
        s += p('m99 50-6-24 17 17 11-15 7 17 15-12 5 24Z', '#63586c', 5)
        s += p('m181 139 6-19 15 10-2 24Z', METAL, 5)
        s += p('M39 201 22 230 34 221 46 205 36 234 49 224 58 207 54 234 66 216 M190 204l-4 31 11-15 5-18 7 33 7-14-5-25 22 30-3-18-14-17', BONE, 4)
    return s


def staff_skull(level):
    s = p('m209 118 12 2-7 112-14 1Z', '#76513c', 6)
    s += p('m202 175 17 1 m-18 25 17 1', 'none', 5, BONE)
    s += group('staff_skull', skull(154, 56, .48, '#a8efaa'))
    if level >= 3:
        s += p('m198 74-11-15 17 5 m25 8 13-16-2 22', BONE, 5)
        s += p('M216 33Q202 50 216 64 233 54 223 41L223 51Z', '#99e6a4', 4)
    if level >= 5:
        s += p('m198 129 18 9 18-11-8 17-16 2Z', BONE, 5)
    return s


def necromancer(level):
    c, dark = TIERS[level-1], shade(TIERS[level-1], .55)
    skin = '#c0c5a7'
    s = shadow()
    if level >= 4:
        s += p('m77 101-18-24 6 47-13 20 22 20 m102-64 20-24-5 47 13 20-22 20', BONE_SHADE, 6)
    s += p('M90 142Q71 132 58 146L44 160 57 178 86 167Z', dark, 6)
    s += p('m91 207 25 1-7 27-30 1 0-10Z m48 0 22-1 15 27-39 2Z', '#4c3d39', 6)
    s += p('M90 126Q126 110 162 128L176 168 176 196 187 222 158 232 141 224 120 233 99 225 73 231 82 201 78 163Z', c)
    s += p('m92 150 20 17-10 51-24 9 10-31-5-30Z m60-9 17 23 2 34 10 25-23 4-15-15 6-30Z', dark, 0)
    s += p('m98 141 27 22 29-26 10 9-36 33-11-2-28-27Z', BONE_SHADE, 5)
    s += p('m86 193 83-5 4 15-88 10Z', '#514439', 5)
    s += rect(115, 192, 25, 20, BONE, 4, 4)
    s += p('m90 141 23-25 37 2 23 25-18 15-50-1Z', dark, 5)
    s += p('M78 83Q80 52 102 39L134 24 158 43Q182 64 179 96L170 137 151 151 137 146 155 116 156 77 130 59 107 72 100 107 114 143 94 143 79 122Z', c)
    s += p('m84 95 18-23 3 31 12 32-15 4-16-18Z m73-43 15 25-1 41-15 21-12 4 17-37Z', dark, 0)
    s += p('M108 80 130 66 151 81 151 112 140 133 121 132 107 112Z', skin, 5)
    s += p('m107 92 18 7-5 11-12-3Z m28 8 17-8-1 15-12 4Z', '#3a3d34', 3)
    s += p('m113 103 8 2 m18-1 8-3', 'none', 4, '#86da91')
    s += p('m128 108-4 10 10 1 m-12 6 17 0', 'none', 3)
    if level >= 2:
        s += circle(128, 169, 12, BONE, 4) + p('m123 169 10 0 m-5-5v10', 'none', 3)
    if level >= 3:
        s += shoulder(83, 145, BONE, .85) + shoulder(173, 145, BONE, .85)
        s += p('m117 47 12-8 14 10-4 15-19-1Z', BONE, 4)
        s += circle(125, 53, 3, '#34362e') + circle(136, 53, 3, '#34362e')
    if level >= 4:
        s += p('m101 177 18 8-2 30-15 7 m48-46-12 9 3 30 17 7', 'none', 6, BONE)
    if level >= 5:
        s += p('m77 146-2-31 23 21 29 14 27-12 24-25-2 33-45 22Z', BONE, 6)
        s += p('m84 157 17 8 m55 0 15-9', 'none', 5, BONE_SHADE)
    s += staff_skull(level)
    s += ellipse(204, 178, 12, 12, skin, 5)
    s += p('m47 160 12-6 10 9-3 17-17-2-8-9Z', skin, 5)
    s += p('M45 154Q32 142 42 129L50 141 56 124Q71 142 61 154Z', '#8de7a4', 4)
    return s


def sun(x, y, r, level):
    points = []
    for n in range(16):
        a = -math.pi/2+n*math.pi/8
        radius = r if n % 2 == 0 else r*.64
        points.append((x+math.cos(a)*radius, y+math.sin(a)*radius))
    d = 'M'+' '.join(f'{a:.1f},{b:.1f}' for a,b in points)+'Z'
    s = p(d, GOLD, 5)
    s += circle(x, y, r*.43, '#fff1ae', 4)
    if level >= 3:
        s += p(f'm{x} {y-r*.25} {r*.2} {r*.25}-{r*.2} {r*.25}-{r*.2}-{r*.25}Z', '#fffde5', 0)
    return s


def priest(level):
    c, dark = TIERS[level-1], shade(TIERS[level-1], .66)
    s = shadow()
    if level >= 5:
        s += circle(129, 76, 60, '#e6b85a', 6) + circle(129, 76, 48, '#fff0b9', 0)
        s += p('m128 9 0 15 M67 34l10 9 m103 0 10-10', 'none', 6, GOLD)
    s += p('M82 139Q65 135 55 150L47 172 62 183 91 159Z', '#ece4cf', 6)
    s += p('m97 205 20 0-7 29-31 2 0-10Z m43 1 20-2 16 29-37 2Z', '#825436', 6)
    s += p('M93 130Q128 118 160 133L171 165 160 187 178 217 149 227 127 218 103 229 76 218 92 184 84 160Z', '#eee7d2')
    s += p('m91 165 12 14-11 29-13 7 18-33Z m61-28 13 26-9 25 15 22-19 8-17-29Z', '#c4bda6', 0)
    s += p('m100 135 17 12-9 67-16 6-6-10Z m35-1 17-13 15 79-18 9-9-6Z', c, 5)
    s += p('m96 186 62-3 3 15-66 4Z', '#805238', 5)
    s += rect(119, 184, 24, 22, GOLD, 4, 4)
    s += p('M86 87Q86 44 128 36 169 45 174 82L175 123 160 145 148 138 151 102 128 67 102 100 104 140 87 131Z', '#eee7d2')
    s += p('M100 88Q126 72 153 91L159 113Q154 139 128 142 101 139 96 116Z', '#ffc18c', 6)
    s += p('m104 93 21-9 23 8-21 0-25 13Z', '#dd986c', 0)
    s += ellipse(113, 113, 6, 10, INK) + ellipse(144, 113, 6, 10, INK)
    s += p('m104 101 17 4 m16 0 16-5', 'none', 4)
    s += p('M86 85Q128 65 174 86L172 101Q129 84 87 101Z', c, 5)
    s += p('m124 77 10 0 5 16-11 8-10-9Z', GOLD, 4)
    if level >= 2:
        s += p('m94 215 14-2 16 5 26-3 21-5', 'none', 5, GOLD)
    if level >= 3:
        s += sun(128, 161, 14, level)
        s += p('m86 146 16 10-6 16-20-11Z m77-1 15-13 10 12-19 15Z', c, 5)
    if level >= 4:
        s += shoulder(83, 143, GOLD, .8) + shoulder(173, 145, GOLD, .8)
    s += p('m207 116 11 3-14 112-14 2Z', '#835537', 6)
    s += sun(211, 92, 21 if level < 4 else 29, level)
    s += p('m195 201 16 1-2 13-15 1Z', GOLD, 4)
    s += p('M160 146Q171 136 183 149L203 166 198 184 176 174 155 162Z', '#eee7d2', 6)
    s += p('m182 157 19 7-7 17-17-8Z', c, 5)
    s += ellipse(202, 177, 12, 12, '#ffc18c', 5)
    s += p('m30 159 26-7 26 10-2 36-28-9-24 5Z', '#8d6542', 5)
    s += p('m34 155 23 3 24-5-2 34-24-7-23 6Z', '#f5e7bb', 5)
    s += p('m57 158-2 22', 'none', 4, '#b79c69')
    s += p('m36 186 19-3 24 5-2 10-23-9-20 4Z', c, 4)
    s += ellipse(65, 194, 10, 8, '#ffc18c', 4)
    return s


def lantern_staff(level):
    s = p('m213 125 10 0-9 109-13-1Z', '#62504b', 6)
    s += p('m217 133-8-12 0-15 m10 0 17-4-1-28-17-10-18 11 1 30 18 1', 'none', 5)
    s += p('m202 77 17-10 17 8-3 10-27 2Z', BONE, 5)
    s += p('m205 91 27-1-2 28-24 2Z', '#b18add', 5)
    s += p('M218 114Q207 101 218 87L220 99 226 95Q233 110 218 114Z', '#eee1ff', 0)
    s += p('m211 89 0 30 m15-30-1 29 m-23 5 32-2', 'none', 4)
    if level >= 4:
        s += p('m199 80-8-15 20 3 m20 1 15-14-5 24', BONE, 5)
        s += p('m217 54-9-11 11-15 12 17-10 11Z', '#cfb3ff', 4)
    return s


def lich(level):
    c, dark = TIERS[level-1], shade(TIERS[level-1], .5)
    s = shadow()
    if level >= 5:
        s += p('m68 93-23-25 7 45-16 22 26 32 9-27 m115-47 22-25-7 45 13 22-27 32-6-27', BONE_SHADE, 6)
    s += p('M73 125Q54 121 43 144L30 177 51 192 77 173 96 143Z', dark, 6)
    s += p('m94 211 20 0-7 25-25 1 0-10Z m47-16 22-1 13 26-31 2Z', '#574653', 6)
    s += p('M85 115Q126 102 170 119L190 160 183 193 199 224 163 237 141 227 117 237 91 227 62 236 74 199 63 161Z', c)
    s += p('m106 137 21 19 22-21 8 43-16 47-17 7-19-10 10-46Z', '#39313e', 5)
    s += p('m73 164 23 8-10 36-17 19 10-32Z m85-63 23 32-4 28 16 30-26 8-13-24 8-32Z', dark, 0)
    s += p('m88 131 40 27 40-29 14 17-52 34-52-32Z', BONE, 6)
    s += p('m85 199 78-2 12 17-42 11-46-11Z', BONE_SHADE, 5)
    s += group('lich_head', skull(-1, -2, 1.04, '#ceb0ff'))
    s += p('M83 61 77 28 102 42 128 15 151 41 179 26 176 61Q126 73 83 61Z', BONE, 6)
    s += p('m90 55 35 5 43-7', 'none', 5, BONE_SHADE)
    s += p('m124 36 12 0 7 18-12 9-12-9Z', c, 4)
    if level >= 2:
        s += shoulder(76, 137, BONE, 1.08) + shoulder(183, 139, BONE, 1.08)
    if level >= 3:
        s += p('m76 125-7-23 27 14 m83 0 25-18-7 28', BONE, 6)
        s += group('belt_skull', skull(92, 175, .29, '#ceb0ff'))
    if level >= 4:
        s += p('m104 174 22 9 27-11 m-50 16 24 9 24-10', 'none', 7, BONE)
        s += p('m81 45-10-25 29 13 m56 0 29-17-9 30', BONE, 5)
    if level >= 5:
        s += p('m95 34-4-23 24 20 15-24 17 23 20-18-3 23-34 6Z', BONE, 5)
        s += p('m79 152-10-17 30 18 m58-1 31-23-9 25', BONE, 6)
    s += lantern_staff(level)
    s += p('M173 139Q192 126 204 145L217 166 209 184 189 174 166 157Z', c, 6)
    s += ellipse(210, 178, 13, 12, BONE, 5)
    s += p('m31 174 12-10 15 4 5 18-13 10-18-7Z', BONE, 5)
    s += p('M43 158Q29 143 40 126L45 139 55 118Q72 144 54 159Z', '#ba8bef', 4)
    s += p('m46 150-3-12 9 8-3 7Z', '#f2e5ff', 0)
    return s


def flesh_golem(enhanced):
    c = TIERS[4 if enhanced else 3]
    skin, patch = '#b7a096', '#8faaa0'
    s = shadow()
    s += p('M85 194 116 199 110 226 118 237 79 238 72 224Z M145 196 174 195 178 223 192 237 149 238 138 223Z', patch, 6)
    if enhanced:
        s += p('M80 213 109 218 113 238 74 237Z M145 213 171 214 182 238 144 237Z', '#718087', 5)
    s += p('M67 109Q43 100 29 125L18 164 26 204 53 215 73 201 83 161Z', patch)
    s += p('m29 155 20 12 4 37-20-6-9-28Z', '#687e78', 0)
    s += p('M167 116Q190 103 208 126L228 154 237 195 221 216 196 209 185 183 164 160Z', skin)
    s += p('m205 146 14 17 12 33-10 14-9-26Z', '#92786e', 0)
    if enhanced:
        body = 'M72 103Q123 80 178 108L195 146 185 198 164 225 94 224 66 205 54 157Z'
    else:
        body = 'M83 118Q126 98 168 119L183 152 175 197 157 220 101 219 79 204 69 161Z'
    s += p(body, skin)
    s += p('m83 139 26-13 22 18-4 48-33 20-15-20Z', patch, 5)
    s += p('m105 133 17 12-1 44-22 12', 'none', 4)
    s += p('m113 145 15-3 m-15 17 14-1 m-18 18 17-2', 'none', 4)
    s += p('m85 197 40 7 47-10 5 23-26 11-27-6-24 6-20-12Z', c, 6)
    s += p('m69 136 109 42-4 16-111-43Z', '#5b4e43', 6)
    s += rect(118, 153, 23, 23, METAL_LIGHT, 4, 4)
    s += p('m26 180 36 2 4 18-39 0Z m173-4 31-8 4 18-29 10Z', c, 5)
    s += group('head', p('M98 63Q116 46 146 53L166 72 168 101 154 124 116 128 96 111 89 86Z', skin) + p('m95 75 27-11 8 18-9 32-14 5-10-15Z', patch, 4) + p('m117 76 6 7 m-8 8 8 4 m-10 12 7 3', 'none', 4) + ellipse(110, 91, 7, 9, '#3c3531') + ellipse(148, 88, 8, 10, '#3c3531') + circle(110, 91, 3, '#e3c576') + circle(148, 89, 3, '#e3c576') + p('m115 111 34-4 m-24-4 2 10 m10-13 2 11', 'none', 4))
    s += p('m91 118 18 10 46-2 16-17 2 23-18 13-49-1-16-14Z', METAL, 5)
    s += p('m30 140 25 4 m-19-11-1 21 M207 163l13-2 m-8-8 3 18', 'none', 4)
    if enhanced:
        s += shoulder(64, 113, c, 1.3) + shoulder(188, 119, c, 1.15)
        s += p('m45 103-8-22 24 17 m122 3 15-21 9 26', METAL_LIGHT, 6)
        s += p('m79 177-9 26 m98-24 6 24', 'none', 6, c)
    return s


NAMES = {
    'skeleton': ('Скелет', 'Кости, меч, щит и нарастающая броня', skeleton),
    'zombie': ('Зомби', 'Тяжёлое тело, рваная ткань и грубое оружие', zombie),
    'ghoul': ('Вурдалак', 'Низкая стойка, длинные руки и когти', ghoul),
    'necromancer': ('Некромант', 'Лечение → скелеты → голем плоти', necromancer),
    'priest': ('Жрец света', 'Новый союзник · книга, солнечный посох и метка света', priest),
    'lich': ('Лич — Смотритель погоста', 'Босс · костяная корона, мантия и фонарь', lich),
}
NOTES = {
    'skeleton': ['Кости и простой меч', 'Шлем и обмотки', 'Щит и наплечник', 'Боковая броня и стальной гребень', 'Полная экипировка и усиленный меч'],
    'zombie': ['Рваная одежда и дубина', 'Повязка и защита ноги', 'Наплечник и тесак', 'Нагрудник и второй наплечник', 'Защита спины и тяжёлое снаряжение'],
    'ghoul': ['Обнажённые когти', 'Повязка и обмотки', 'Костяной наплечник', 'Стальные наручи', 'Усиленные когти и костяной венец'],
    'necromancer': ['Лечение союзника', 'Лечение · усиление характеристик', 'Добавляется призыв скелетов', 'Добавляется сборка голема', 'Более живучий и быстрый голем'],
    'priest': ['Сгусток света', 'Усиление характеристик', 'Метка света', 'Усиление метки и экипировки', 'Автоматическое Освящение'],
    'lich': ['Костяная корона и фонарь', 'Наплечники', 'Предложение: свита скелетов', 'Предложение: костяной покров', 'Предложение: погребальный звон'],
}


def svg(name, body):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
<title>{escape(name)}</title><desc>Концепт: собственные SVG paths; одежда и экипировка обозначают уровень. Production rig требует отдельной приёмки.</desc>
<g stroke="{INK}" stroke-width="7" stroke-linecap="round" stroke-linejoin="round">{body}</g></svg>\n'''


def main():
    sections = []
    for key, (name, subtitle, draw) in NAMES.items():
        cards = []
        for level in range(1, 6):
            file = f'{key}_lv{level}.svg'
            (ROOT/file).write_text(svg(f'{name} · Lv{level}', draw(level)), encoding='utf-8')
            cards.append(f'''<article class="card" style="--tier:{TIERS[level-1]}"><div class="level">Lv{level} <span>{TIER_NAMES[level-1]}</span></div><a href="{file}" target="_blank"><img src="{file}" alt="{name}, уровень {level}" width="256" height="256"></a><p>{NOTES[key][level-1]}</p></article>''')
        sections.append(f'<section id="{key}" data-entity="{key}"><h2>{name}</h2><p class="subtitle">{subtitle}</p><div class="cards">'+''.join(cards)+'</div></section>')
    flesh_cards = []
    for enhanced in (False, True):
        source_level = 5 if enhanced else 4
        file = f'flesh_golem_from_necromancer_lv{source_level}.svg'
        (ROOT/file).write_text(svg(f'Голем плоти · призыв некроманта Lv{source_level}', flesh_golem(enhanced)), encoding='utf-8')
        flesh_cards.append(f'''<article class="card" style="--tier:{TIERS[source_level-1]}"><div class="level">Некромант Lv{source_level}</div><a href="{file}" target="_blank"><img src="{file}" alt="Голем плоти от некроманта Lv{source_level}" width="256" height="256"></a><p>{'Усиленный: больше ОЗ и скорости' if enhanced else 'Базовый призыв из трёх останков'}</p></article>''')
    sections.append('<section id="flesh_golem" data-entity="flesh_golem"><h2>Голем плоти</h2><p class="subtitle">Два варианта призыва. Цвет ремней — уровень некроманта-источника.</p><div class="cards flesh">'+''.join(flesh_cards)+'</div></section>')
    options = '<option value="all">Все персонажи</option>'+''.join(f'<option value="{key}">{name}</option>' for key,(name,_,_) in NAMES.items())+'<option value="flesh_golem">Голем плоти</option>'
    html = '''<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Кладбище — концепты Summoner Tower</title>
<link rel="icon" href="data:,">
<style>
*{box-sizing:border-box}body{margin:0;background:#101521;color:#e7e8db;font:16px/1.45 system-ui,sans-serif}main{max-width:1380px;margin:auto;padding:36px 30px 50px}header{margin-bottom:30px}.eyebrow{color:#aab7c4;font-size:13px;letter-spacing:2px;text-transform:uppercase}h1{font-size:38px;margin:8px 0;color:#e8cb8b;letter-spacing:-1px}header p{max-width:950px;color:#b6c3c9;margin:8px 0}.toolbar{display:flex;flex-wrap:wrap;gap:20px;align-items:center;margin-top:22px;padding:16px;background:#192331;border-radius:12px}select{background:#233344;color:#eee;border:1px solid #4b6373;border-radius:6px;padding:8px;font:inherit}label{display:flex;align-items:center;gap:10px}.toolbar button{padding:8px 12px;border:1px solid #4b6373;border-radius:6px;background:#233344;color:#fff;cursor:pointer}section{margin:32px 0}h2{margin:0;color:#f0dcad;font-size:24px}.subtitle{color:#9eafb9;margin:4px 0 14px;font-size:14px}.cards{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:14px}.card{min-width:0;background:#1b2935;border:1px solid #354957;border-top:4px solid var(--tier);border-radius:12px;padding:13px 10px 12px;text-align:center}.level{font-weight:700;color:var(--tier);font-size:16px}.level span{display:block;color:#9eafb9;font-size:12px;font-weight:400}a{display:block;color:#a1d7f3}img{display:block;width:min(var(--actor,190px),100%);height:auto;margin:10px auto 0}.card p{color:#b9c5cb;font-size:13px;margin:8px 0 0;min-height:38px}.flesh{max-width:600px;grid-template-columns:repeat(2,minmax(0,1fr))}.flesh img{width:235px}footer{font-size:13px;color:#91a1ad;border-top:1px solid #344652;padding-top:18px}[hidden]{display:none!important}@media(max-width:650px){main{padding:22px 14px}h1{font-size:28px}.cards{grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}.card{padding:10px 6px}.level{font-size:15px}.toolbar{gap:10px;font-size:14px}h2{font-size:22px}.flesh{max-width:none}}
</style><main><header><div class="eyebrow">Summoner Tower · Concept review · 16.10.2026</div><h1>Биом II · Кладбище</h1><p>Собственные SVG-концепты: четыре обычных врага, новый союзник и босс на пяти уровнях. Кожа и кости сохраняют цвет; меняются одежда, броня и оружие.</p><p>Голем плоти показан отдельно в двух вариантах призыва. Клик по персонажу открывает исходный SVG крупно.</p><div class="toolbar"><label>Персонаж <select id="entity">OPTIONS</select></label><label>Размер <select id="size"><option value="100">100 px</option><option value="140">140 px</option><option value="190" selected>190 px</option></select></label><button id="reset">Показать всё</button></div></header>SECTIONS<footer>Ручная отрисовка SVG-кодом. Концепты для обсуждения; следующие этапы — приёмка облика, cutout parts, rig, анимации и gameplay. Окружение/портал и способности проходят отдельные превью.</footer></main>
<script>const entity=document.querySelector('#entity'),size=document.querySelector('#size');entity.onchange=()=>document.querySelectorAll('section').forEach(s=>s.hidden=entity.value!=='all'&&s.dataset.entity!==entity.value);size.onchange=()=>document.documentElement.style.setProperty('--actor',size.value+'px');document.querySelector('#reset').onclick=()=>{entity.value='all';entity.onchange()};</script></html>'''
    environment = build_environment(ROOT, {
        'skeleton': skeleton(1), 'zombie': zombie(2),
        'priest': priest(1), 'necromancer': necromancer(3),
    })
    options = options.replace('Все персонажи', 'Все концепты')
    options += '<option value="environment">Основа окружения</option><option value="decorations">Декорации</option><option value="battlefield">Пример поля</option>'
    html = html.replace('Персонаж <select', 'Раздел <select')
    html = html.replace('Окружение/портал и способности проходят отдельные превью.', 'Окружение добавлено ниже; VFX и способности проходят отдельные превью.')
    html = html.replace('</style>', '.terrain{grid-template-columns:repeat(4,minmax(0,1fr))}img.field{width:min(640px,100%);height:auto;margin:18px 0 0;border-radius:12px}@media(max-width:650px){.terrain{grid-template-columns:repeat(2,minmax(0,1fr))}}</style>')
    sheets = '<div id="enemies">'+''.join(sections[:4])+'</div><div id="specials">'+''.join(sections[4:6])+'</div>'+sections[6]+environment
    (ROOT/'index.html').write_text(html.replace('OPTIONS', options).replace('SECTIONS', sheets), encoding='utf-8')
    print('Saved 32 character concepts, 14 environment concepts, battlefield and index.html in', ROOT)


if __name__ == '__main__':
    main()
