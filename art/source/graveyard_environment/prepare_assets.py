"""Promote our accepted SVG concepts at runtime sizes; no external art or generators."""
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'assets/environment/graveyard'
ET.register_namespace('', 'http://www.w3.org/2000/svg')
DECORATIONS = ['dead_tree', 'headstone', 'grave_cross', 'crypt', 'fence',
               'remains', 'candles', 'lantern', 'flowers', 'coffin']


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, origin in [('ground', 'graveyard_ground'), ('road', 'graveyard_road')]:
        (OUT / f'{name}.svg').write_text((ROOT / f'art/source/{origin}/master.svg').read_text(encoding='utf-8'), encoding='utf-8')
    for name in ['pedestal', 'portal'] + DECORATIONS:
        svg = ET.parse(ROOT / f'art/concepts/graveyard/env_{name}.svg').getroot()
        size = 140 if name == 'pedestal' else (128 if name == 'portal' else 64)
        svg.set('width', str(size))
        svg.set('height', str(size))
        # Full common canvas retained; Sprite2D origin remains its center.
        (OUT / f'{name}.svg').write_text(ET.tostring(svg, encoding='unicode') + '\n', encoding='utf-8')
    print(f'Prepared {len(DECORATIONS) + 4} own SVG textures: {OUT}')


if __name__ == '__main__':
    main()
