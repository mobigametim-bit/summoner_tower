"""Выделяет принятую SVG-экипировку в жёсткие части с полным исходным холстом.

Сцены и прежние части не перезаписываются. Зелёные акценты перекрашивает локальный
материал Godot, поэтому уровни могут переиспользовать нейтральные формы.
"""
from pathlib import Path
import copy
import json
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
NS = 'http://www.w3.org/2000/svg'
ET.register_namespace('', NS)
COLORS = ['#88b96b', '#ec9b49', '#df5654', '#5295ef', '#b66dea']
manifest = {'version': 1, 'canvas': [256, 256], 'coordinate_workflow': 'Untrimmed canvas; offset=-parent pivot; absolute z matches original part.', 'entities': {}}


def build(entity, slots):
    rig = json.loads((ROOT / f'art/source/{entity}/rig_manifest.json').read_text(encoding='utf-8'))
    parts = {Path(p['file']).stem: p for p in rig['parts']}
    bones = {p['bone']: p for p in rig['parts']}
    destination = ROOT / f'art/source/{entity}/equipment'
    destination.mkdir(exist_ok=True)
    records = []
    written = set()

    def bone_path(bone):
        return 'Skeleton2D/Root' if bone == 'Root' else bone_path(bones[bone]['parent_bone']) + '/' + bone

    for name, parent, variants, replacement in slots:
        part = parts[parent]
        textures = []
        for specification in variants:
            if specification is None:
                textures.append(None)
                continue
            if specification == 'original':
                textures.append(f'res://art/source/{entity}/{part["file"]}')
                continue
            filename, tier, groups = specification
            path = destination / f'{filename}.svg'
            if filename not in written:
                preview = ET.parse(HERE / f'{entity}_lv{tier}.svg').getroot()
                lookup = {g.get('id'): g for g in preview.iter(f'{{{NS}}}g')}
                root = ET.Element(f'{{{NS}}}svg', {'width': '256', 'height': '256', 'viewBox': '0 0 256 256'})
                ET.SubElement(root, f'{{{NS}}}title').text = f'{entity} · {filename} · rigid equipment part'
                for group in groups:
                    item = copy.deepcopy(lookup[f'{entity}_lv{tier}_{group}'])
                    for node in item.iter():
                        if 'id' in node.attrib:
                            node.set('id', node.get('id').removeprefix(f'{entity}_lv{tier}_'))
                        for attribute in ('fill', 'stroke'):
                            if node.get(attribute) == COLORS[tier-1]:
                                node.set(attribute, COLORS[0])
                    root.append(item)
                path.write_text(ET.tostring(root, encoding='unicode') + '\n', encoding='utf-8')
                written.add(filename)
            textures.append(f'res://art/source/{entity}/equipment/{filename}.svg')
        records.append({'node': bone_path(part['bone']) + '/' + ('Sprite' if replacement else name), 'parent_part': parent, 'offset': [-v for v in part['pivot']], 'z_index': part['z_index'], 'replacement': replacement, 'textures': textures})
    manifest['entities'][entity] = {'scene': rig['visual_scene'], 'bones': rig['bone_count'], 'parts': records, 'texture_count': len(written)}


def v(file, tier, *groups):
    return (file, tier, list(groups))


body_light = v('body_armor_light', 2, 'metal_pauldron')
body_heavy = v('body_armor_heavy', 4, 'metal_pauldron', 'breastplate')
build('goblin', [
    ('BodyArmor', 'body', [None, body_light, body_light, body_heavy, body_heavy], False),
    ('Shield', 'arm_back', [None, None, v('shield_wood', 3, 'shield'), v('shield_rimmed', 4, 'shield'), v('shield_metal', 5, 'shield')], False),
    ('Helmet', 'head', [None, None, None, None, v('open_helmet', 5, 'open_helmet')], False),
    ('Weapon', 'dagger', ['original'] + [v(f'weapon_lv{tier}', tier, 'dagger') for tier in range(2, 6)], True),
])
pauldron = v('shoulder_armor', 2, 'reinforced_pauldron')
bracer_back = v('bracer_back', 3, 'metal_bracer_back')
bracer_front = v('bracer_front', 3, 'metal_bracer_front')
chest = v('breastplate', 4, 'breastplate')
build('orc', [
    ('ShoulderArmor', 'arm_back', [None, pauldron, pauldron, pauldron, pauldron], False),
    ('Bracer', 'arm_back', [None, None, bracer_back, bracer_back, bracer_back], False),
    ('Bracer', 'arm_front', [None, None, bracer_front, bracer_front, bracer_front], False),
    ('Shield', 'arm_back', [None, None, None, v('shield_round', 4, 'round_shield'), v('shield_reinforced', 5, 'round_shield')], False),
    ('Breastplate', 'body', [None, None, None, chest, chest], False),
    ('Helmet', 'head', [None, None, None, None, v('open_helmet', 5, 'open_helmet')], False),
    ('Weapon', 'axe', ['original'] + [v(f'weapon_lv{tier}', tier, 'axe') for tier in range(2, 6)], True),
])
golem_slots = []
for side in ('back', 'front'):
    parent = f'arm_{side}_forearm'
    golem_slots.append(('FistArmor', parent, [None] + [v(f'fist_{side}_lv{tier}', tier, f'fist_armor_{parent}') for tier in range(2, 6)], False))
    parent = f'arm_{side}_upper'
    plate = v(f'shoulder_{side}_stone', 3, f'shoulder_plate_{side}')
    reinforced = v(f'shoulder_{side}_reinforced', 5, f'shoulder_plate_{side}', f'shoulder_reinforcement_{parent}')
    golem_slots.append(('ShoulderArmor', parent, [None, None, plate, plate, reinforced], False))
chest = v('breastplate', 4, 'stone_breastplate')
golem_slots += [
    ('Breastplate', 'body', [None, None, None, chest, chest], False),
    ('BrowPlate', 'head', [None, None, None, None, v('brow_plate', 5, 'brow_plate')], False),
]
build('golem', golem_slots)
(ROOT / 'art/source/enemy_equipment_manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({key: {'parts': len(value['parts']), 'textures': value['texture_count'], 'bones': value['bones']} for key, value in manifest['entities'].items()}))
