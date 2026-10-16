"""Static review of one hand-authored tile; existing art is only embedded for scale."""
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'build/web/preview/graveyard-ground'
NS = 'http://www.w3.org/2000/svg'
ET.register_namespace('', NS)


def tag(name, **attrs):
    return ET.Element(f'{{{NS}}}{name}', {key.replace('_', '-'): str(value) for key, value in attrs.items()})


def source(path, name, size):
    node = ET.parse(ROOT / path).getroot()
    node.set('id', name)
    node.set('width', str(size))
    node.set('height', str(size))
    return node


def build_field(actors):
    svg = tag('svg', width=720, height=1080, viewBox='0 0 720 1080')
    defs = ET.SubElement(svg, f'{{{NS}}}defs')
    ground = tag('pattern', id='ground', width=120, height=120, patternUnits='userSpaceOnUse')
    ground.append(source('art/source/graveyard_ground/master.svg', 'tile', 120))
    defs.append(ground)
    svg.append(tag('rect', width=720, height=1080, fill='url(#ground)'))
    if actors:
        road = tag('pattern', id='road', width=64, height=64, patternUnits='userSpaceOnUse')
        road.append(source('assets/environment/paved_road.svg', 'paving', 64))
        defs.append(road)
        route = 'M660 60H420V180H180V420H540V780H300V1020'
        svg.append(tag('path', d=route, fill='none', stroke='#4a5148', stroke_width=84,
                       stroke_linecap='round', stroke_linejoin='round'))
        svg.append(tag('path', d=route, fill='none', stroke='url(#road)', stroke_width=74,
                       stroke_linecap='round', stroke_linejoin='round'))
        assets = {
            'pedestal': ('assets/environment/pedestal.svg', 120),
            'portal': ('assets/environment/portal.svg', 112),
            'tower': ('art/source/tower/master.svg', 112),
            'archer': ('art/source/archer/master.svg', 100),
            'mage': ('art/source/mage/master.svg', 100),
            'frost': ('art/source/frost_mage/master.svg', 100),
            'goblin': ('art/source/goblin/master.svg', 62),
            'orc': ('art/source/orc/master.svg', 77),
        }
        for name, (path, size) in assets.items():
            defs.append(source(path, name, size))
        def place(name, x, y):
            size = assets[name][1]
            svg.append(tag('use', href=f'#{name}', x=x-size/2, y=y-size/2))
        for col, row in [(2,0),(4,1),(0,1),(0,2),(0,3),(2,4),(3,5),(5,5),(1,7),(3,8)]:
            place('pedestal', col*120+60, row*120+60)
        for name, col, row in [('archer',4,1),('mage',0,2),('frost',3,5),('archer',3,8)]:
            place(name, col*120+60, row*120+60-22)
        place('portal', 660, 60)
        place('tower', 300, 1020)
        for name, x, y in [('goblin',420,180),('orc',180,320),('goblin',540,580)]:
            place(name, x, y)
    return ET.tostring(svg, encoding='unicode') + '\n'


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, path in [('tile.svg', 'art/source/graveyard_ground/master.svg'),
                       ('reference.svg', 'art/concepts/graveyard/env_ground.svg')]:
        (OUT / name).write_text((ROOT / path).read_text(encoding='utf-8'), encoding='utf-8')
    (OUT / 'field.svg').write_text(build_field(True), encoding='utf-8')
    (OUT / 'repeat.svg').write_text(build_field(False), encoding='utf-8')
    (OUT / 'index.html').write_text((Path(__file__).parent / 'review.html').read_text(encoding='utf-8'), encoding='utf-8')
    (OUT / '.gdignore').touch()
    print(f'Ground preview: {OUT / "index.html"}')


if __name__ == '__main__':
    main()
