"""Hand-authored rigid SVG cutout parts; no raster/image generation."""
from pathlib import Path
import json
import math
import shutil
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
INK = '#29180f'
GOLD = '#e6b85a'
COLORS = ['#88b96b', '#ec9b49', '#df5654', '#5295ef', '#b66dea']
NAMES = ['Зелёный', 'Оранжевый', 'Красный', 'Синий', 'Фиолетовый']
PARTS = [
    ('halo', 'Head', None, (128, 137)),
    ('back_arm', 'Body', 'BackArm', (88, 148)),
    ('leg_left', 'Body', 'LeftLeg', (110, 207)),
    ('leg_right', 'Body', 'RightLeg', (146, 207)),
    ('body', 'Root', 'Body', (128, 175)),
    ('staff', 'FrontArm', 'Staff', (202, 177)),
    ('front_arm', 'Body', 'FrontArm', (162, 147)),
    ('head', 'Body', 'Head', (128, 137)),
]


def path(d, fill='none', width=None, stroke=None):
    attrs = f'd="{d}" fill="{fill}"'
    if width is not None:
        attrs += ' stroke="none"' if width == 0 else f' stroke-width="{width}"'
    if stroke:
        attrs += f' stroke="{stroke}"'
    return f'<path {attrs}/>'


def ellipse(x, y, rx, ry, fill, width=0):
    return (f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{fill}" '
            f'stroke="{INK if width else "none"}" stroke-width="{width}"/>')


def sun(x, y, radius, tier):
    points = []
    for index in range(16):
        angle = -math.pi / 2 + index * math.pi / 8
        r = radius if index % 2 == 0 else radius * .64
        points.append(f'{x + math.cos(angle)*r:.1f},{y + math.sin(angle)*r:.1f}')
    content = path('M' + ' '.join(points) + 'Z', GOLD, 5)
    content += ellipse(x, y, radius * .43, radius * .43, '#fff1ae', 4)
    if tier >= 3:
        content += path(f'M{x} {y-radius*.25}l{radius*.2} {radius*.25}-{radius*.2} {radius*.25}-{radius*.2}-{radius*.25}Z', '#fffde5', 0)
    return content


def shoulder(x, y, color):
    return (f'<g transform="translate({x} {y}) scale(.8)">'
            + path('M-18-9Q1-21 19-6L23 11 5 20-22 10Z', '#87959d', 5)
            + path('m-14-5 14-7 14 8-12 5Z', '#b5c0bd', 0)
            + path('m-17 11 20 4 14-5', 'none', 5, color) + '</g>')


def shapes(tier):
    c = COLORS[tier-1]
    parts = {}
    # Hidden shoulder and wrist continue behind robe and book, rather than butt joints.
    parts['back_arm'] = (
        path('M91 137Q76 131 64 144L51 162Q47 173 55 185L60 198 73 197 75 183 69 167 94 158Z', '#ece4cf', 6)
        + path('m30 159 26-7 26 10-2 36-28-9-24 5Z', '#8d6542', 5)
        + path('m34 155 23 3 24-5-2 34-24-7-23 6Z', '#f5e7bb', 5)
        + path('m57 158-2 22', 'none', 4, '#b79c69')
        + path('m36 186 19-3 24 5-2 10-23-9-20 4Z', c, 4)
        + ellipse(65, 194, 10, 8, '#ffc18c', 4))
    # Rounded hip caps stay hidden under the robe during cutout rotations.
    parts['leg_left'] = (path('M98 198Q108 192 118 201L117 214 110 234 79 236 79 226 91 209Z', '#825436', 6)
                         + path('m84 227 22-2-2 6-21 1Z', '#a46e45', 0))
    parts['leg_right'] = (path('M138 199Q149 190 160 200L163 212 176 233 139 235 137 220Z', '#825436', 6)
                          + path('m145 225 20-1 5 6-25 1Z', '#a46e45', 0))
    body = path('M93 130Q128 118 160 133L171 165 160 187 178 217 149 227 127 218 103 229 76 218 92 184 84 160Z', '#eee7d2')
    body += path('m91 165 12 14-11 29-13 7 18-33Z m61-28 13 26-9 25 15 22-19 8-17-29Z', '#c4bda6', 0)
    body += path('m100 135 17 12-9 67-16 6-6-10Z m35-1 17-13 15 79-18 9-9-6Z', c, 5)
    body += path('m96 186 62-3 3 15-66 4Z', '#805238', 5)
    body += '<rect x="119" y="184" width="24" height="22" rx="4" fill="#e6b85a" stroke-width="4"/>'
    if tier >= 2:
        body += path('m94 215 14-2 16 5 26-3 21-5', 'none', 5, GOLD)
    if tier >= 3:
        body += sun(128, 161, 14, tier)
        body += path('m86 146 16 10-6 16-20-11Z m77-1 15-13 10 12-19 15Z', c, 5)
    if tier >= 4:
        body += shoulder(83, 143, GOLD) + shoulder(173, 145, GOLD)
    parts['body'] = body
    parts['staff'] = (path('m207 116 11 3-14 112-14 2Z', '#835537', 6)
                      + sun(211, 92, 21 if tier < 4 else 29, tier)
                      + path('m195 201 16 1-2 13-15 1Z', GOLD, 4))
    parts['front_arm'] = (
        path('M151 143Q162 130 176 140L187 152 203 166 198 184 176 174 155 162Q149 155 151 143Z', '#eee7d2', 6)
        + path('m182 157 19 7-7 17-17-8Z', c, 5)
        + ellipse(202, 177, 12, 12, '#ffc18c', 5))
    head = path('M86 87Q86 44 128 36 169 45 174 82L175 123 160 145 148 138 151 102 128 67 102 100 104 140 87 131Z', '#eee7d2')
    head += path('M100 88Q126 72 153 91L159 113Q154 139 128 142 101 139 96 116Z', '#ffc18c', 6)
    head += path('m104 93 21-9 23 8-21 0-25 13Z', '#dd986c', 0)
    head += ellipse(113, 113, 6, 10, INK) + ellipse(144, 113, 6, 10, INK)
    head += path('m104 101 17 4 m16 0 16-5', 'none', 4)
    head += path('M86 85Q128 65 174 86L172 101Q129 84 87 101Z', c, 5)
    head += path('m124 77 10 0 5 16-11 8-10-9Z', GOLD, 4)
    parts['head'] = head
    if tier == 5:
        parts['halo'] = (ellipse(129, 76, 60, 60, GOLD, 6)
                         + ellipse(129, 76, 48, 48, '#fff0b9')
                         + path('m128 9 0 15 M67 34l10 9 m103 0 10-10', 'none', 6, GOLD))
    return parts


def group(name, content, pivot):
    return (f'<g id="{name}" stroke="{INK}" stroke-width="7" stroke-linecap="round" '
            f'stroke-linejoin="round" data-pivot-x="{pivot[0]}" data-pivot-y="{pivot[1]}">'
            + content + '</g>')


def svg(title, content):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">\n'
            f'<title>{title}</title>\n{content}\n</svg>\n')


def build():
    HERE.mkdir(parents=True, exist_ok=True)
    manifest = {'version': 1, 'entity': 'Priest', 'stage': 'art_accepted', 'canvas': [256, 256],
                'actor_origin': [128, 128], 'feet_baseline_y': 239, 'gameplay_canvas_size': 100,
                'outline': {'color': INK, 'width': 7}, 'bones_including_root': 8,
                'release_point_canvas': [211, 92], 'parts': [], 'levels': {}}
    for z, (name, parent, bone, pivot) in enumerate(PARTS):
        manifest['parts'].append({'name': name, 'bone': bone, 'parent_bone': parent,
                                  'pivot': list(pivot), 'sprite_offset': [-pivot[0], -pivot[1]],
                                  'z_index': z, 'full_canvas': True})
    # Share textures only when both shapes and palette are exactly identical.
    shared = {}
    for tier in range(1, 6):
        parts = shapes(tier)
        refs = {}
        assembled = []
        for name, parent, bone, pivot in PARTS:
            if name not in parts:
                refs[name] = None
                continue
            content = group(name, parts[name], pivot)
            key = (name, content)
            if key not in shared:
                relative = f'parts/{name}.svg' if tier == 1 or name == 'halo' else f'parts/lv{tier}/{name}.svg'
                target = HERE / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(svg(f'Жрец света — {name} — Lv{tier}', content), encoding='utf-8')
                shared[key] = relative
            refs[name] = shared[key]
            assembled.append(content)
        manifest['levels'][str(tier)] = {'color': COLORS[tier-1], 'name': NAMES[tier-1], 'parts': refs}
        master = 'master.svg' if tier == 1 else f'master_lv{tier}.svg'
        (HERE / master).write_text(svg(f'Жрец света — Lv{tier}', '\n'.join(assembled)), encoding='utf-8')
    (HERE / 'rig_manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    # Validate exact assembly order and the standalone documents after writing.
    for file in HERE.rglob('*.svg'):
        node = ET.parse(file).getroot()
        assert node.attrib['viewBox'] == '0 0 256 256', file
    for tier in range(1, 6):
        master = ET.parse(HERE / ('master.svg' if tier == 1 else f'master_lv{tier}.svg')).getroot()
        groups = [node for node in master if node.tag.endswith('}g')]
        for node in groups:
            source = ET.parse(HERE / manifest['levels'][str(tier)]['parts'][node.attrib['id']]).getroot()
            assert ET.tostring(node).strip() == ET.tostring(list(source)[1]).strip()
    print(json.dumps({'levels': 5, 'unique_part_textures': len(shared), 'bones_planned': 8}, ensure_ascii=False))


def preview():
    target = ROOT / 'build/web/preview/priest-art'
    target.mkdir(parents=True, exist_ok=True)
    (target / '.gdignore').touch()
    for name in ['master.svg', 'master_lv2.svg', 'master_lv3.svg', 'master_lv4.svg', 'master_lv5.svg', 'rig_manifest.json']:
        shutil.copy2(HERE / name, target / name)
    shutil.copytree(HERE / 'parts', target / 'parts', dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns('*.import'))
    reference = target / 'reference'
    reference.mkdir(exist_ok=True)
    for tier in range(1, 6):
        shutil.copy2(ROOT / f'art/concepts/graveyard/priest_lv{tier}.svg', reference / f'priest_lv{tier}.svg')
    shutil.copy2(ROOT / 'assets/environment/graveyard/pedestal.svg', reference / 'pedestal.svg')
    page = (HERE / 'review.html').read_text(encoding='utf-8')
    page = page.replace('../../concepts/graveyard/', 'reference/')
    page = page.replace('../../../assets/environment/graveyard/', 'reference/')
    (target / 'index.html').write_text(page, encoding='utf-8')


if __name__ == '__main__':
    build()
    preview()
