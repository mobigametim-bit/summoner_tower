"""Build rigid Boss equipment variants from hand-written SVG paths; keep legacy art."""
from pathlib import Path
import copy
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
NS = 'http://www.w3.org/2000/svg'
ET.register_namespace('', NS)
COLORS = ['#88b96b', '#ec9b49', '#df5654', '#5295ef', '#b66dea']


def shade(color, factor):
    return '#' + ''.join(f'{min(255, round(int(color[i:i+2], 16) * factor)):02x}' for i in (1, 3, 5))


def overlay(parts, parent, name, xml, before_face=False):
    group = ET.fromstring(f'<g xmlns="{NS}" stroke="#29180f" stroke-width="7" stroke-linecap="round" stroke-linejoin="round">{xml}</g>')
    group.set('id', name)
    group.set('data-parent-part', parent)
    if before_face:
        head = parts[parent]
        at = next(i for i, child in enumerate(head) if child.get('d', '').startswith('m90 91'))
        head.insert(at, group)
    else:
        parts[parent].append(group)


def compose(level):
    root = copy.deepcopy(ET.parse(ROOT / 'art/source/boss/master.svg').getroot())
    root.find(f'{{{NS}}}title').text = f'Boss Lv{level} — hand-written SVG art review'
    parts = {g.get('id'): g for g in root.findall(f'{{{NS}}}g')}
    color = COLORS[level - 1]
    light, dark = shade(color, 1.18), shade(color, .67)
    for name, group in parts.items():
        for path in group:
            old = path.get('fill')
            if old == '#503456':
                path.set('fill', color)
            if name == 'body' and old in ('#6b4b7e', '#39263e'):
                path.set('fill', dark)
            if name.endswith('_upper') and old in ('#e3b552', '#f5d581', '#af7f37'):
                path.set('fill', {'#e3b552': color, '#f5d581': light, '#af7f37': dark}[old])

    if level >= 2:
        overlay(parts, 'arm_back_forearm', 'bracer_back', f'''
        <path d="M20 163 60 170 67 190 20 183Z" fill="{color}"/>
        <path d="m25 169 28 5" fill="none" stroke="{light}" stroke-width="5"/>
        <path d="m21 181 44 8" fill="none" stroke="#e3b552" stroke-width="5"/>
        ''')
        overlay(parts, 'arm_front_forearm', 'bracer_front', f'''
        <path d="m188 165 45-9 8 22-45 10Z" fill="{color}"/>
        <path d="m197 168 27-6" fill="none" stroke="{light}" stroke-width="5"/>
        <path d="m198 184 40-9" fill="none" stroke="#e3b552" stroke-width="5"/>
        ''')
        for parent, shape, shine in [
            ('leg_left', 'M84 207 110 205 116 228 98 237 79 228Z', 'm88 214 16-2'),
            ('leg_right', 'm140 209 25-3 12 22-16 10-24-8Z', 'm145 215 15-2'),
        ]:
            overlay(parts, parent, 'shin_' + parent, f'<path d="{shape}" fill="{color}" stroke-width="6"/><path d="{shine}" fill="none" stroke="{light}" stroke-width="5"/>')

    if level >= 3:
        overlay(parts, 'body', 'breastplate', f'''
        <path d="m82 151 22 11 48 2 28-17 8 30-15 24-37 15-41-16-19-24Z" fill="{color}"/>
        <path d="m87 159 20 12 45 1 24-15-2 16-43 25-43-24Z" fill="{light}" stroke="none"/>
        <path d="m89 179 42 26 45-25" fill="none" stroke="#e3b552" stroke-width="6"/>
        <path d="m118 174 13-8 13 8-1 16-12 8-12-9Z" fill="#e3b552" stroke-width="5"/>
        ''')
        overlay(parts, 'arm_back_upper', 'shoulder_back', f'''
        <path d="m31 95 26-8 29 10 15 21-15 22-29 5-30-17Z" fill="{color}"/>
        <path d="m37 102 22-8 22 10 9 12-27 6-27-9Z" fill="{light}" stroke="none"/>
        <path d="m32 126 26 11 25-5" fill="none" stroke="#e3b552" stroke-width="5"/>
        ''')
        overlay(parts, 'arm_front_upper', 'shoulder_front', f'''
        <path d="m168 96 25-8 28 12 15 20-15 23-24 8-32-14-10-21Z" fill="{color}"/>
        <path d="m172 103 21-8 22 11 10 14-28 6-26-11Z" fill="{light}" stroke="none"/>
        <path d="m169 133 27 11 24-8" fill="none" stroke="#e3b552" stroke-width="5"/>
        ''')

    if level >= 4:
        overlay(parts, 'head', 'open_helmet', f'''
        <path d="M78 61 88 63 92 84 85 104 89 134 78 126 71 99Z" fill="{color}" stroke-width="6"/>
        <path d="m178 62 10-5 10 37-6 32-11 10 2-28-8-24Z" fill="{color}" stroke-width="6"/>
        <path d="m82 74 2 20-6 15 M185 71l5 24-4 14" fill="none" stroke="#e3b552" stroke-width="5"/>
        ''', before_face=True)
        overlay(parts, 'arm_back_forearm', 'gauntlet_back', f'''
        <path d="m16 187 21-3 23 8 8 16-15 13-27-4-12-14Z" fill="{color}"/>
        <path d="m21 194 16-3 18 6-2 7-29-1Z" fill="{light}" stroke="none"/>
        <path d="m19 205 31 7 12-7" fill="none" stroke="#e3b552" stroke-width="5"/>
        ''')
        overlay(parts, 'arm_front_forearm', 'gauntlet_front', f'''
        <path d="m193 191 25-10 23 5 5 19-16 17-28-3-14-13Z" fill="{color}"/>
        <path d="m198 196 20-8 16 4 3 8-30 8Z" fill="{light}" stroke="none"/>
        <path d="m201 213 25 4 15-13" fill="none" stroke="#e3b552" stroke-width="5"/>
        ''')

    if level >= 5:
        for parent, shape in [
            ('arm_back_upper', 'm27 99 15-10 18 2 1 19-18 3Z'),
            ('arm_front_upper', 'm197 91 20 1 15 14-17 8-19-5Z'),
        ]:
            overlay(parts, parent, 'royal_' + parent, f'<path d="{shape}" fill="#e3b552" stroke-width="6"/>')
        overlay(parts, 'body', 'waist_armor', f'''
        <path d="m91 194 38 15 39-15-3 16-34 14-34-12Z" fill="#e3b552" stroke-width="6"/>
        <path d="m123 201 8-5 9 6-1 13-9 6-8-6Z" fill="{color}" stroke-width="5"/>
        ''')
        overlay(parts, 'head', 'crown_gem', f'''
        <path d="m130 36 12 15-12 15-12-15Z" fill="{color}" stroke-width="5"/>
        <path d="m130 42-6 9 6 8Z" fill="{light}" stroke="none"/>
        ''')
        for parent, shape in [
            ('arm_back_forearm', 'm21 191 14 3-2 13-13-3Z'),
            ('arm_front_forearm', 'm219 188 14 3 1 14-14 3Z'),
        ]:
            overlay(parts, parent, 'knuckles_' + parent, f'<path d="{shape}" fill="#e3b552" stroke-width="5"/>')

    for level_group in parts.values():
        # All equipment stays attached to an existing cutout group/pivot.
        assert level_group.get('data-pivot-x') and level_group.get('data-pivot-y')
    return root


def build_equipment():
    import json
    global COLORS
    COLORS = ['#88b96b'] * 5  # Runtime accent shader supplies the five tier colors.
    folder = HERE / 'equipment'
    folder.mkdir(exist_ok=True)
    manifest = json.loads((HERE / 'rig_manifest.json').read_text(encoding='utf-8'))
    textures = {Path(part['file']).stem: [] for part in manifest['parts']}
    seen = {name: {} for name in textures}
    for tier in range(1, 6):
        master = compose(tier)
        for group in master.findall(f'{{{NS}}}g'):
            name = group.get('id')
            part_svg = ET.Element(f'{{{NS}}}svg', {'width': '256', 'height': '256', 'viewBox': '0 0 256 256'})
            part_svg.append(copy.deepcopy(group))
            encoded = ET.tostring(part_svg, encoding='unicode')
            if encoded not in seen[name]:
                filename = f'{name}_lv{tier}.svg'
                (folder / filename).write_text(encoded + '\n', encoding='utf-8')
                seen[name][encoded] = 'res://art/source/boss/equipment/' + filename
            textures[name].append(seen[name][encoded])
    mapping = {
        'arm_back_upper': 'Skeleton2D/Root/Body/BackUpperArm/Sprite',
        'arm_back_forearm': 'Skeleton2D/Root/Body/BackUpperArm/BackForearm/Sprite',
        'leg_left': 'Skeleton2D/Root/Body/LeftLeg/Sprite',
        'leg_right': 'Skeleton2D/Root/Body/RightLeg/Sprite',
        'body': 'Skeleton2D/Root/Body/Sprite',
        'arm_front_upper': 'Skeleton2D/Root/Body/FrontUpperArm/Sprite',
        'arm_front_forearm': 'Skeleton2D/Root/Body/FrontUpperArm/FrontForearm/Sprite',
        'head': 'Skeleton2D/Root/Body/Head/Sprite',
    }
    result = {'canvas': [256, 256], 'bones': 9, 'parts': []}
    for part in manifest['parts']:
        name = Path(part['file']).stem
        result['parts'].append({
            'part': name, 'node': mapping[name], 'pivot': part['pivot'],
            'sprite_offset': part['sprite_offset'], 'z_index': part['z_index'],
            'tier_textures': textures[name]
        })
    (folder / 'manifest.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'unique_textures': sum(len(x) for x in seen.values()), 'parts': 8, 'bones': 9}))


if __name__ == '__main__':
    build_equipment()
