"""Split our approved crypt concept into the existing three-part tower workflow."""
from copy import deepcopy
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
NS = 'http://www.w3.org/2000/svg'
ET.register_namespace('', NS)


def svg(parts):
    root = ET.Element(f'{{{NS}}}svg', {'width':'256','height':'256','viewBox':'0 0 256 256'})
    ET.SubElement(root, f'{{{NS}}}title').text = 'Summoner Tower — Graveyard crypt cutout'
    for group in parts:
        root.append(deepcopy(group))
    return ET.tostring(root, encoding='unicode') + '\n'


def main():
    original = ET.parse(ROOT / 'art/concepts/graveyard_towers/crypt.svg').getroot()
    shapes = list(original.find(f'{{{NS}}}g'))
    # Shadow and foundation stay on the ground; the three last paths before
    # the foundation form the crystal. Keep the full canvas and hidden overlap.
    groups = []
    for name, indexes in [('base', [0, len(shapes)-1]),
                          ('body', range(1, len(shapes)-4)),
                          ('crystal', range(len(shapes)-4, len(shapes)-1))]:
        attrs = dict(original.find(f'{{{NS}}}g').attrib)
        # Last visible foundation stroke ends at y=254, matching TowerHealth's
        # existing bottom anchor and keeping summon-price alignment unchanged.
        attrs.update({'id':name,'transform':'translate(0 7)'})
        group = ET.Element(f'{{{NS}}}g', attrs)
        for i in indexes:
            group.append(deepcopy(shapes[i]))
        groups.append(group)
    (OUT / 'parts').mkdir(parents=True, exist_ok=True)
    for group in groups:
        (OUT / 'parts' / f'{group.get("id")}.svg').write_text(svg([group]),encoding='utf-8')
    (OUT / 'master.svg').write_text(svg(groups),encoding='utf-8')
    print('Prepared crypt master.svg and base/body/crystal cutout parts.')


if __name__ == '__main__':
    main()
