"""Turn our accepted graveyard vector concepts into full-canvas rigid cutout parts.

Only semantic grouping and hidden joint overlap are added. Original concept files
are never rewritten; no raster generators or external images are involved.
"""
from pathlib import Path
from copy import deepcopy
import ast
import html
import importlib.util
import json
import re
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[3]
CONCEPT = ROOT / 'art/concepts/graveyard'
OUT = Path(__file__).resolve().parent
NS = 'http://www.w3.org/2000/svg'
ET.register_namespace('', NS)
sys.path.insert(0, str(CONCEPT))
spec = importlib.util.spec_from_file_location('accepted_graveyard', CONCEPT / 'build_concepts.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
source = (CONCEPT / 'build_concepts.py').read_text(encoding='utf-8')
segments = {}


class TagChunks(ast.NodeTransformer):
    def visit_FunctionDef(self, node):
        if node.name not in ['skeleton', 'zombie', 'ghoul', 'necromancer', 'lich', 'flesh_golem']:
            return node
        for child in ast.walk(node):
            target = child.target if isinstance(child, ast.AugAssign) else (child.targets[0] if isinstance(child, ast.Assign) else None)
            if isinstance(target, ast.Name) and target.id == 's':
                segments[child.lineno] = ast.get_source_segment(source, child.value)
                child.value = ast.Call(func=ast.Name(id='_tag', ctx=ast.Load()), args=[ast.Constant(child.lineno), child.value], keywords=[])
        return node


tree = ast.fix_missing_locations(TagChunks().visit(ast.parse(source)))
scope = dict(module.__dict__)
scope['_tag'] = lambda line, value: f'<g data-line="{line}">{value}</g>'
exec(compile(tree, str(CONCEPT / 'build_concepts.py'), 'exec'), scope)

PROFILES = {
 'skeleton': {'title':'Скелет','levels':[1,2,3,4,5],'body':[129,177],'head':[129,134],'back_arm':[92,141],'front_arm':[164,141],'leg_left':[110,196],'leg_right':[154,196],'weapon':[206,182],'walk':.76,'abilities':{'bone_shield':5}},
 'zombie': {'title':'Зомби','levels':[1,2,3,4,5],'body':[128,181],'head':[130,140],'back_arm':[78,147],'front_arm':[173,150],'leg_left':[108,205],'leg_right':[155,205],'weapon':[211,183],'walk':1.12,'abilities':{'regenerate':5}},
 'ghoul': {'title':'Вурдалак','levels':[1,2,3,4,5],'body':[128,173],'head':[130,140],'back_arm':[87,148],'front_arm':[160,147],'leg_left':[111,198],'leg_right':[155,192],'walk':.56,'abilities':{'dash':5}},
 'necromancer': {'title':'Некромант','levels':[1,2,3,4,5],'body':[128,180],'head':[130,139],'back_arm':[91,143],'front_arm':[162,147],'leg_left':[104,207],'leg_right':[152,207],'weapon':[204,178],'walk':1.0,'abilities':{'heal':1,'summon_skeletons':3,'assemble_flesh':4}},
 'flesh_golem': {'title':'Голем плоти','levels':[4,5],'body':[128,174],'head':[130,124],'back_arm':[70,121],'front_arm':[171,123],'leg_left':[103,199],'leg_right':[157,199],'walk':1.2,'abilities':{}},
 'lich': {'title':'Лич','levels':[1,2,3,4,5],'body':[128,179],'head':[130,137],'back_arm':[78,137],'front_arm':[173,143],'leg_left':[104,211],'leg_right':[153,211],'weapon':[210,178],'walk':1.12,'abilities':{'retinue':3,'bone_cover':4,'grave_bell':5}},
}
PART_ORDER = ['back_accessory','leg_left','leg_right','back_arm','body','weapon','front_arm','head']


def classify(entity, text):
    """Assign the original semantic source chunks to the joint that carries them."""
    s = text.replace('"', "'")
    if s == 'shadow()': return 'shadow'
    if entity == 'skeleton':
        if "'legs'" in s or "p('m86 219" in s: return 'legs'
        if "'back_arm'" in s or 'shoulder(80,' in s or "p('M35 147" in s or "p('m41 153" in s or 'circle(54,' in s: return 'back_arm'
        if "'front_arm'" in s or "p('m188 166" in s or 'shoulder(172,' in s or 'ellipse(203,' in s: return 'front_arm'
        if s.startswith('skull(') or any(t in s for t in ["p('M80 65","p('m88 58","p('m127 32","p('m87 43"]): return 'head'
        if "p('m88 149" in s: return 'arms'
        if s.startswith('sword('): return 'weapon'
    elif entity == 'zombie':
        if any(t in s for t in ["p('m46 80","p('m43 96"]): return 'back_accessory'
        if any(t in s for t in ["p('M77 144","p('m43 172",'shoulder(76,']): return 'back_arm'
        if "p('m94 204" in s: return 'legs'
        if 'rect(93, 212' in s: return 'leg_left'
        if any(t in s for t in ["p('M171 145","p('m192 158",'shoulder(178,']): return 'front_arm'
        if "group('head'" in s or any(t in s for t in ["p('m78 72","p('m139 69"]): return 'head'
        if s.startswith('weapon +'): return 'weapon_hand'
    elif entity == 'ghoul':
        if any(t in s for t in ["p('M81 112","p('m77 130"]): return 'back_accessory'
        if "p('m101 196" in s or "p('m81 219" in s: return 'legs'
        if "p('M85 143" in s or 'shoulder(82,' in s: return 'back_arm'
        if "p('M158 142" in s or "p('m181 139" in s: return 'front_arm'
        if any(t in s for t in ["p('m42 184","p('m43 207","p('m40 176","p('M39 201"]): return 'arms'
        if "group('head'" in s or any(t in s for t in ["p('m89 65","p('m151 67","p('m99 50"]): return 'head'
    elif entity == 'necromancer':
        if "p('m77 101" in s: return 'back_accessory'
        if "p('M90 142" in s or "p('m47 160" in s or "p('M45 154" in s: return 'back_arm'
        if "p('m91 207" in s: return 'legs'
        if s.startswith('staff_skull('): return 'weapon'
        if 'ellipse(204,' in s: return 'front_arm'
        if s.startswith('shoulder(83,'): return 'arms'
        if any(t in s for t in ["p('M78 83","p('m84 95","p('M108 80","p('m107 92","p('m113 103","p('m128 108","p('m117 47",'circle(125, 53']): return 'head'
    elif entity == 'lich':
        if "p('m68 93" in s: return 'back_accessory'
        if any(t in s for t in ["p('M73 125","p('m31 174","p('M43 158","p('m46 150"]): return 'back_arm'
        if "p('m94 211" in s: return 'legs'
        if s.startswith('lantern_staff('): return 'weapon'
        if "p('M173 139" in s or 'ellipse(210,' in s: return 'front_arm'
        if s.startswith('shoulder(76,'): return 'arms'
        if "group('lich_head'" in s or any(t in s for t in ["p('M83 61","p('m90 55","p('m124 36","p('m81 45","p('m95 34"]): return 'head'
    elif entity == 'flesh_golem':
        if any(t in s for t in ["p('M85 194","p('M80 213","p('m79 177"]): return 'legs'
        if "p('M67 109" in s or "p('m29 155" in s: return 'back_arm'
        if "p('M167 116" in s or "p('m205 146" in s: return 'front_arm'
        if any(t in s for t in ["p('m26 180","p('m30 140",'shoulder(64,',"p('m45 103"]): return 'arms'
        if "group('head'" in s: return 'head'
    return 'body'


def absolute_subpaths(d):
    """Small SVG path normalizer for splitting the two pre-existing limbs.

    Preserve exact bezier control points, including relative moveto after close.
    """
    tokens = re.findall(r'[a-zA-Z]|[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?',d)
    arity = {'M':2,'L':2,'H':1,'V':1,'C':6,'S':4,'Q':4,'T':2,'A':7}
    result=[]; commands=[]; coords=[]; pos=complex(0,0); start=pos; cmd=None; i=0
    while i < len(tokens):
        if tokens[i].isalpha():
            cmd=tokens[i]; i+=1
            if cmd.upper() == 'Z':
                commands.append('Z'); pos=start; cmd=None; continue
        upper=cmd.upper(); n=arity[upper]; nums=[float(t) for t in tokens[i:i+n]]; i+=n
        if upper == 'M' and commands:
            result.append((' '.join(commands),coords)); commands=[]; coords=[]
        relative=cmd.islower()
        if upper == 'H':
            pos=complex(nums[0]+(pos.real if relative else 0),pos.imag); upper='L'; nums=[pos.real,pos.imag]
        elif upper == 'V':
            pos=complex(pos.real,nums[0]+(pos.imag if relative else 0)); upper='L'; nums=[pos.real,pos.imag]
        else:
            indices=[n-2] if upper == 'A' else range(0,n,2)
            for j in indices:
                if relative: nums[j]+=pos.real; nums[j+1]+=pos.imag
                coords.append(nums[j])
            pos=complex(nums[-2],nums[-1])
        if upper == 'M': start=pos; cmd='l' if relative else 'L'
        commands.append(upper+' '+' '.join(f'{a:g}' for a in nums))
    if commands: result.append((' '.join(commands),coords))
    return result


def split_side(node):
    left=deepcopy(node); right=deepcopy(node)
    if node.tag.endswith('g'):
        transform=node.get('transform','')
        if transform.startswith('translate('):
            x=float(re.findall(r'[-\d.]+',transform)[0])
            return (deepcopy(node),None) if x < 128 else (None,deepcopy(node))
        left[:]=[]; right[:]=[]
        for child in node:
            a,b=split_side(child)
            if a is not None:left.append(a)
            if b is not None:right.append(b)
        return (left if len(left) else None,right if len(right) else None)
    if node.tag.endswith('path'):
        a=[];b=[]
        for d,xs in absolute_subpaths(node.get('d')):
            (a if (min(xs)+max(xs))*.5 < 128 else b).append(d)
        left.set('d',' '.join(a));right.set('d',' '.join(b))
        return (left if a else None,right if b else None)
    x=float(node.get('cx',node.get('x','128')))
    return (left,None) if x < 128 else (None,right)


def svg(nodes,title):
    root=ET.Element(f'{{{NS}}}svg',{'width':'256','height':'256','viewBox':'0 0 256 256'})
    ET.SubElement(root,f'{{{NS}}}title').text=title
    g=ET.SubElement(root,f'{{{NS}}}g',{'stroke':'#29180f','stroke-width':'7','stroke-linecap':'round','stroke-linejoin':'round'})
    for n in nodes:g.append(deepcopy(n))
    return ET.tostring(root,encoding='unicode')+'\n'


def main():
    profiles={}
    for key, data in PROFILES.items():
        variants={part:[] for part in PART_ORDER}
        levels=data['levels']
        for level in levels:
            shapes=scope[key](level>=5 if key=='flesh_golem' else level)
            root=ET.fromstring(f'<svg xmlns="{NS}">{shapes}</svg>')
            parts={part:[] for part in PART_ORDER}; shadow=[]
            for chunk in root:
                text=segments[int(chunk.get('data-line'))]
                part=classify(key,text)
                for node in chunk:
                    if part=='shadow':shadow.append(node)
                    elif part in ['arms','legs']:
                        a,b=split_side(node)
                        if a is not None:parts['back_arm' if part=='arms' else 'leg_left'].append(a)
                        if b is not None:parts['front_arm' if part=='arms' else 'leg_right'].append(b)
                    elif part=='weapon_hand':
                        parts['front_arm' if node.tag.endswith('ellipse') else 'weapon'].append(node)
                    else:parts[part].append(node)
            if key=='necromancer':
                # Accepted concept has the staff hand detached from the robe.
                # Add the hidden sleeve/shoulder overlap required by cutout motion.
                arm=ET.fromstring(f'<path xmlns="{NS}" d="M156 143Q172 135 183 149L207 167 204 186 182 176 156 160Z" fill="{module.TIERS[level-1]}" stroke-width="6"/>')
                parts['front_arm'].insert(0,arm)
            destination=ROOT/f'art/source/{key}'
            target=destination/'parts'/f'lv{level}';target.mkdir(parents=True,exist_ok=True)
            assembled=list(shadow)
            for part in PART_ORDER:
                if parts[part]:
                    path=target/f'{part}.svg'
                    path.write_text(svg(parts[part],f'{key} Lv{level} · {part}'),encoding='utf-8')
                    variants[part].append('res://'+path.relative_to(ROOT).as_posix())
                    assembled.extend(parts[part])
                else:variants[part].append(None)
            (destination/f'master_lv{level}.svg').write_text(svg(assembled,f'{key} Lv{level} · cutout assembly'),encoding='utf-8')
            if level==levels[0]:(destination/'master.svg').write_text(svg(assembled,f'{key} · cutout master'),encoding='utf-8')
        bones={name:coords for name,coords in data.items() if name in PART_ORDER and isinstance(coords,list)}
        hierarchy={'root':{'parent':'Skeleton2D','position':[-128,-128]}}
        for name,point in bones.items():
            parent='root' if name=='body' else ('front_arm' if name=='weapon' else 'body')
            anchor=[0,0] if parent=='root' else bones[parent]
            hierarchy[name]={'parent':parent,'position':[point[i]-anchor[i] for i in range(2)],'source_pivot':point,'sprite_offset':[-x for x in point],'rotation_origin':'bone origin'}
        manifest={'entity':key,'canvas':[256,256],'origin':[128,128],'baseline':239,'pivots':bones,'bones':hierarchy,'runtime_texture_size':[128,128],'sprite_scale':2,'part_order':PART_ORDER,'levels':levels,'textures':variants}
        (destination/'rig_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        profile=dict(data);profile['parts']=variants;profile['scene']='res://scenes/visuals/'+''.join(x.title() for x in key.split('_'))+'Visual.tscn'
        profiles[key]=profile
    (OUT/'rig_spec.json').write_text(json.dumps(profiles,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    masks=ROOT/'assets/vfx/undead';masks.mkdir(parents=True,exist_ok=True)
    icons={
      'bone': '<path d="M9 12q-7 1-5 7 1 4 6 3l12 0q5 1 6-3 2-6-5-7-2-5-6-1-5-4-8 1Z" fill="white"/>',
      'plus': '<path d="M12 3h8v9h9v8h-9v9h-8v-9H3v-8h9Z" fill="white"/>',
      'wisp': '<path d="M17 2Q3 11 7 22 9 31 18 29 31 24 25 14L21 20Q16 19 17 2Z" fill="white"/>',
      'slash': '<path d="M1 28 24 2 31 2 10 29Z" fill="white"/>',
      'beam': '<path d="M10 0h12l8 32H2Z" fill="white" opacity=".15"/><path d="M13 0h6l4 32H9Z" fill="white" opacity=".85"/>',
      'bell': '<path d="M13 3h6v4q8 2 8 13l3 5H2l3-5q0-11 8-13Z" fill="white"/><path d="M12 28h8q-1 5-4 4t-4-4Z" fill="white"/>',
      'rune': '<path d="m16 2 12 14-12 14L4 16Z m0 7-6 7 6 7 6-7Z" fill="white" fill-rule="evenodd"/>',
      'stone': '<path d="m7 4 17 2 6 14-10 9-15-6-3-11Z" fill="white"/>',
      'spark': '<path d="m16 0 5 11 11 5-11 5-5 11-5-11L0 16l11-5Z" fill="white"/>',
      'skull': '<path d="M5 6Q16-2 27 6l3 13-6 5v6H8v-6l-6-5Z" fill="white"/><path d="m7 12 7 2-1 7-6-2Z m12 2 7-2v7l-6 2Z" fill="#303030"/>',
    }
    for name,body in icons.items():
        (masks/f'{name}.svg').write_text(f'<svg xmlns="{NS}" width="32" height="32" viewBox="0 0 32 32">{body}</svg>\n',encoding='utf-8')
    (masks/'shadow.svg').write_text(f'<svg xmlns="{NS}" width="180" height="24" viewBox="0 0 180 24"><ellipse cx="90" cy="12" rx="82" ry="10" fill="#0b1520" opacity=".35"/></svg>\n',encoding='utf-8')
    print(json.dumps({'entities':len(profiles),'levels':sum(len(v['levels']) for v in profiles.values()),'masks':len(icons),'parts':sum(sum(x is not None for x in arr) for p in profiles.values() for arr in p['parts'].values())}))


if __name__=='__main__':main()
