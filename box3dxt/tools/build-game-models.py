#!/usr/bin/env python3
"""build-game-models.py - carry Orb Island's 3D models into the game script.

Orb Island is ONE paste-and-run file that must also play in a web page,
where a stack has no folder of files beside it. Its models therefore
travel inside the script: this tool reads the source models in
examples/models/ (Kenney's CC0 glTF binaries and their shared palette
picture, see examples/models/README.md), turns each into OBJ text with a
material (.mtl) text, gzips and base64s them, and writes them into the
game between the GAME MODELS markers as one function, oiModelData.

Why bake the colours: Kenney's models colour themselves by pointing each
triangle at a cell of one palette picture (colormap.png). render3dxt can
texture a model, but in a web page there is no picture file to load, and
a texture lookup per pixel costs more than a flat colour. So each
triangle takes the colour of its palette cell, near colours are merged,
and the model becomes a few flat materials, lit per vertex like the rest
of the island.

Why fit each model to a box: the game draws a model in place of a
physics shape (b3kSetLook), whose centre is the body's. Each entry names
the box the model must fill, so the picture and the shape agree without
any offset in the game.

Standard library only (the PNG and glTF readers are below), so the gate
runs wherever python3 does.

    python3 tools/build-game-models.py          # rewrite the block
    python3 tools/build-game-models.py --check  # the gate: the block matches
"""
import base64
import gzip
import json
import os
import struct
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'examples', 'models')
GAME = os.path.join(ROOT, 'examples', 'box3dxt-orb-island.livecodescript')
BEGIN = '-- BEGIN GAME MODELS'
END = '-- END GAME MODELS'

# name: (source file, the box it fills as w,h,d metres, centred on the
# origin, or None to keep its size; "uniform" keeps its proportions, fitting
# the box's height), and optionally a dict of choices:
#   palette  the palette picture its kit paints with (each Kenney kit has
#            its own colormap.png; the default is the Platformer kit's)
#   turn     degrees about y it is turned first (a wall long in x made to
#            stand long in z)
#   ground   a height: triangles wholly at or below it are left out (a
#            City Builder tile's square of ground under its trees, which
#            the island's own grass replaces)
MODELS = [
    ('flag', 'flag.glb', (None, 2.4, None), 'uniform'),
    ('platform', 'platform.glb', (3.0, 0.6, 3.0), 'box'),
    ('crumble', 'platform-falling.glb', (2.4, 0.5, 2.4), 'box'),
    ('cloud', 'cloud.glb', (7.0, 3.2, 5.0), 'box'),
    ('plate', 'platform.glb', (2.2, 0.24, 2.2), 'box'),
    ('gate', 'brick.glb', (5.0, 3.2, 0.6), 'box'),
    ('trees', 'grass-trees-tall.glb', (3.8, 4.2, 3.8), 'box', {'ground': 0.065}),
    ('grove', 'grass-trees.glb', (3.6, 3.4, 3.6), 'box', {'ground': 0.065}),
    ('tuft', 'grass.glb', (0.9, 0.55, 0.9), 'box'),
    ('isle', 'platform-grass-large-round.glb', (12.0, 1.0, 12.0), 'box'),
    ('roundtop', 'platform-grass-large-round.glb', (3.4, 0.4, 3.4), 'box'),
    ('lift', 'platform-medium.glb', (2.6, 0.4, 2.6), 'box'),
    ('wall-x', 'wall-high.glb', (5.6, 3.2, 0.6), 'box', {'palette': 'colormap-fps.png'}),
    ('wall-z', 'wall-high.glb', (0.6, 3.2, 5.6), 'box', {'palette': 'colormap-fps.png', 'turn': 90}),
]
# a model drawn as moving parts with its own animations (b3kAddLookPart and
# b3kPoseLookPart): name, source, the height it fits (centred, like a
# shape), frames a second the animations are sampled at
PARTED = [
    ('character', 'character.glb', 1.6, 30),
]
MERGE = 26          # colours nearer than this (RGB distance) become one
PLACES = 3          # decimals kept in the OBJ text
CHUNK = 760         # base64 characters a script line


# ---------------------------------------------------------------- PNG

def read_png(path):
    """8-bit RGB or RGBA, not interlaced: what colormap.png is."""
    data = open(path, 'rb').read()
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise SystemExit('build-game-models: %s is not a PNG' % path)
    pos, idat, width = 8, b'', 0
    while pos < len(data):
        length, kind = struct.unpack('>I4s', data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        if kind == b'IHDR':
            width, height, depth, ctype, _, _, inter = struct.unpack('>IIBBBBB', body)
            if depth != 8 or ctype not in (2, 6) or inter:
                raise SystemExit('build-game-models: %s: only 8-bit RGB(A), not interlaced' % path)
            bpp = 3 if ctype == 2 else 4
        elif kind == b'IDAT':
            idat += body
        pos += 12 + length
    raw = zlib.decompress(idat)
    stride = width * bpp
    rows, prev, at = [], bytearray(stride), 0
    for _ in range(height):
        ftype = raw[at]
        line = bytearray(raw[at + 1:at + 1 + stride])
        at += 1 + stride
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if ftype == 1:
                line[i] = (line[i] + a) & 255
            elif ftype == 2:
                line[i] = (line[i] + b) & 255
            elif ftype == 3:
                line[i] = (line[i] + (a + b) // 2) & 255
            elif ftype == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        rows.append(line)
        prev = line
    return width, height, lambda x, y: tuple(rows[y][x * bpp:x * bpp + 3])


# ---------------------------------------------------------------- glTF

FMT = {5120: 'b', 5121: 'B', 5122: 'h', 5123: 'H', 5125: 'I', 5126: 'f'}
COUNT = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


def read_glb(path):
    data = open(path, 'rb').read()
    if data[:4] != b'glTF':
        raise SystemExit('build-game-models: %s is not a binary glTF' % path)
    pos, doc, blob = 12, None, b''
    while pos < len(data):
        length, kind = struct.unpack_from('<II', data, pos)
        chunk = data[pos + 8:pos + 8 + length]
        if kind == 0x4E4F534A:
            doc = json.loads(chunk)
        elif kind == 0x004E4942:
            blob = chunk
        pos += 8 + length
    return doc, blob


def accessor(doc, blob, index):
    acc = doc['accessors'][index]
    view = doc['bufferViews'][acc['bufferView']]
    n, f = COUNT[acc['type']], FMT[acc['componentType']]
    size = struct.calcsize(f)
    stride = view.get('byteStride', size * n)
    base = view.get('byteOffset', 0) + acc.get('byteOffset', 0)
    return [struct.unpack_from('<' + f * n, blob, base + k * stride) for k in range(acc['count'])]


def matmul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def node_matrix(node):
    if 'matrix' in node:
        m = node['matrix']
        return [[m[c * 4 + r] for c in range(4)] for r in range(4)]
    x, y, z, w = node.get('rotation', [0, 0, 0, 1])
    sx, sy, sz = node.get('scale', [1, 1, 1])
    tx, ty, tz = node.get('translation', [0, 0, 0])
    r = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
         [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
         [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
    return [[r[0][0] * sx, r[0][1] * sy, r[0][2] * sz, tx],
            [r[1][0] * sx, r[1][1] * sy, r[1][2] * sz, ty],
            [r[2][0] * sx, r[2][1] * sy, r[2][2] * sz, tz],
            [0, 0, 0, 1]]


def triangles(path, palette):
    """[(three (x,y,z), three (nx,ny,nz), rgb)] in the model's own space."""
    doc, blob = read_glb(path)
    width, height, pixel = palette
    parent = {}
    for i, node in enumerate(doc['nodes']):
        for child in node.get('children', []):
            parent[child] = i
    out = []
    for i, node in enumerate(doc['nodes']):
        if 'mesh' not in node:
            continue
        m, j = node_matrix(node), i
        while j in parent:
            j = parent[j]
            m = matmul(node_matrix(doc['nodes'][j]), m)
        for prim in doc['meshes'][node['mesh']]['primitives']:
            pts = accessor(doc, blob, prim['attributes']['POSITION'])
            nrm = accessor(doc, blob, prim['attributes']['NORMAL'])
            uvs = accessor(doc, blob, prim['attributes']['TEXCOORD_0'])
            idx = [v[0] for v in accessor(doc, blob, prim['indices'])]
            for t in range(0, len(idx), 3):
                tri = idx[t:t + 3]
                u = sum(uvs[k][0] for k in tri) / 3
                v = sum(uvs[k][1] for k in tri) / 3
                rgb = pixel(min(width - 1, max(0, int(u * width))), min(height - 1, max(0, int(v * height))))
                ps, ns = [], []
                for k in tri:
                    x, y, z = pts[k]
                    ps.append(tuple(m[r][0] * x + m[r][1] * y + m[r][2] * z + m[r][3] for r in range(3)))
                    a, b, c = nrm[k]
                    n = [m[r][0] * a + m[r][1] * b + m[r][2] * c for r in range(3)]
                    length = sum(q * q for q in n) ** 0.5 or 1.0
                    ns.append(tuple(q / length for q in n))
                out.append((ps, ns, rgb))
    return out


def chosen(tris, choice):
    """The triangles with a MODELS entry's turn and ground applied."""
    import math
    out = tris
    if 'ground' in choice:
        out = [t for t in out if max(p[1] for p in t[0]) > choice['ground']]
    if choice.get('turn'):
        a = math.radians(choice['turn'])
        c, s = math.cos(a), math.sin(a)

        def turn(v):
            return (v[0] * c + v[2] * s, v[1], -v[0] * s + v[2] * c)
        out = [([turn(p) for p in t[0]], [turn(n) for n in t[1]], t[2]) for t in out]
    return out


# ---------------------------------------------------------------- OBJ

def num(value):
    text = ('%.' + str(PLACES) + 'f') % value
    text = text.rstrip('0').rstrip('.')
    return '0' if text in ('-0', '') else text


def build(fit, mode, tris):
    lo = [min(p[a] for t in tris for p in t[0]) for a in range(3)]
    hi = [max(p[a] for t in tris for p in t[0]) for a in range(3)]
    span = [max(1e-6, hi[a] - lo[a]) for a in range(3)]
    mid = [(lo[a] + hi[a]) / 2 for a in range(3)]
    if isinstance(mode, tuple):
        # a part: a set scale about its own origin, which it turns about
        scale = [mode[1]] * 3
        mid = [0.0, 0.0, 0.0]
    elif mode == 'uniform':
        k = fit[1] / span[1]
        scale = [k, k, k]
    else:
        scale = [fit[a] / span[a] for a in range(3)]
    # colours, most used first, each merged into the first near one
    use = {}
    for t in tris:
        use[t[2]] = use.get(t[2], 0) + 1
    keep = []
    for rgb in sorted(use, key=lambda c: (-use[c], c)):
        if not any(sum((rgb[i] - k[i]) ** 2 for i in range(3)) ** 0.5 < MERGE for k in keep):
            keep.append(rgb)

    def nearest(rgb):
        return min(range(len(keep)), key=lambda i: (sum((rgb[j] - keep[i][j]) ** 2 for j in range(3)), i))

    verts, vindex, norms, nindex, faces = [], {}, [], {}, {}
    for ps, ns, rgb in tris:
        corner = []
        for p, n in zip(ps, ns):
            # non-uniform scaling bends normals by the inverse scale
            n = [n[a] / scale[a] for a in range(3)]
            length = sum(q * q for q in n) ** 0.5 or 1.0
            vk = ' '.join(num((p[a] - mid[a]) * scale[a]) for a in range(3))
            nk = ' '.join(num(round(q / length, 2)) for q in n)
            if vk not in vindex:
                vindex[vk] = len(verts) + 1
                verts.append(vk)
            if nk not in nindex:
                nindex[nk] = len(norms) + 1
                norms.append(nk)
            corner.append('%d//%d' % (vindex[vk], nindex[nk]))
        faces.setdefault(nearest(rgb), []).append(' '.join(corner))
    # fast_obj reads a material file only when the model names one; the
    # text given beside the model is what render3dxt hands it
    obj = ['mtllib model.mtl'] + ['v ' + v for v in verts] + ['vn ' + n for n in norms]
    mtl = []
    for slot in sorted(faces):
        obj.append('usemtl c%d' % slot)
        obj += ['f ' + f for f in faces[slot]]
        mtl.append('newmtl c%d' % slot)
        mtl.append('Kd %s %s %s' % tuple(num(c / 255.0) for c in keep[slot]))
    return '\n'.join(obj) + '\n', '\n'.join(mtl) + '\n'


# ------------------------------------------------------- parts and poses

def mat_trs(t, r, s):
    return node_matrix({'translation': t, 'rotation': r, 'scale': s})


def quat_of(m):
    """A rotation matrix (3 x 3, no scale) as a quaternion (x, y, z, w)."""
    tr = m[0][0] + m[1][1] + m[2][2]
    if tr > 0:
        k = (tr + 1.0) ** 0.5 * 2
        return ((m[2][1] - m[1][2]) / k, (m[0][2] - m[2][0]) / k, (m[1][0] - m[0][1]) / k, 0.25 * k)
    if m[0][0] > m[1][1] and m[0][0] > m[2][2]:
        k = (1.0 + m[0][0] - m[1][1] - m[2][2]) ** 0.5 * 2
        return (0.25 * k, (m[0][1] + m[1][0]) / k, (m[0][2] + m[2][0]) / k, (m[2][1] - m[1][2]) / k)
    if m[1][1] > m[2][2]:
        k = (1.0 + m[1][1] - m[0][0] - m[2][2]) ** 0.5 * 2
        return ((m[0][1] + m[1][0]) / k, 0.25 * k, (m[1][2] + m[2][1]) / k, (m[0][2] - m[2][0]) / k)
    k = (1.0 + m[2][2] - m[0][0] - m[1][1]) ** 0.5 * 2
    return ((m[0][2] + m[2][0]) / k, (m[1][2] + m[2][1]) / k, 0.25 * k, (m[1][0] - m[0][1]) / k)


def euler_of(q):
    """Degrees about x, then y, then z: the Kit's b3kQuatEuler, inverted."""
    import math
    x, y, z, w = q
    rx = math.atan2(2 * (w * x + y * z), 1 - 2 * (x * x + y * y))
    ry = math.asin(max(-1.0, min(1.0, 2 * (w * y - z * x))))
    rz = math.atan2(2 * (w * z + x * y), 1 - 2 * (y * y + z * z))
    return [math.degrees(a) for a in (rx, ry, rz)]


def sample(times, values, at, path):
    if at <= times[0]:
        return list(values[0])
    for i in range(1, len(times)):
        if at <= times[i]:
            f = (at - times[i - 1]) / ((times[i] - times[i - 1]) or 1)
            a, b = values[i - 1], values[i]
            if path == 'rotation':
                dot = sum(a[k] * b[k] for k in range(4))
                if dot < 0:
                    b = [-v for v in b]
                v = [a[k] + (b[k] - a[k]) * f for k in range(4)]
                n = sum(c * c for c in v) ** 0.5 or 1.0
                return [c / n for c in v]
            return [a[k] + (b[k] - a[k]) * f for k in range(len(a))]
    return list(values[-1])


def parted(source, height, fps, palette):
    """{part: (obj, mtl)} and the animation text."""
    doc, blob = read_glb(os.path.join(SRC, source))
    nodes = doc['nodes']
    parent = {}
    for i, node in enumerate(nodes):
        for child in node.get('children', []):
            parent[child] = i
    rest = {i: (n.get('translation', [0, 0, 0]), n.get('rotation', [0, 0, 0, 1]), n.get('scale', [1, 1, 1]))
            for i, n in enumerate(nodes)}

    def worlds(local):
        out = {}
        for i in range(len(nodes)):
            m, j = mat_trs(*local[i]), i
            while j in parent:
                j = parent[j]
                m = matmul(mat_trs(*local[j]), m)
            out[i] = m
        return out

    # each part's triangles in its own frame; the rest pose's bounds fit it
    width, hgt, pixel = palette
    parts, rest_world = {}, worlds(rest)
    lo, hi = [1e9] * 3, [-1e9] * 3
    for i, node in enumerate(nodes):
        if 'mesh' not in node:
            continue
        tris = []
        for prim in doc['meshes'][node['mesh']]['primitives']:
            pts = accessor(doc, blob, prim['attributes']['POSITION'])
            nrm = accessor(doc, blob, prim['attributes']['NORMAL'])
            uvs = accessor(doc, blob, prim['attributes']['TEXCOORD_0'])
            idx = [v[0] for v in accessor(doc, blob, prim['indices'])]
            for t in range(0, len(idx), 3):
                tri = idx[t:t + 3]
                u = sum(uvs[k][0] for k in tri) / 3
                v = sum(uvs[k][1] for k in tri) / 3
                rgb = pixel(min(width - 1, max(0, int(u * width))), min(hgt - 1, max(0, int(v * hgt))))
                tris.append(([tuple(pts[k]) for k in tri], [tuple(nrm[k]) for k in tri], rgb))
                m = rest_world[i]
                for k in tri:
                    x, y, z = pts[k]
                    for a in range(3):
                        w = m[a][0] * x + m[a][1] * y + m[a][2] * z + m[a][3]
                        lo[a], hi[a] = min(lo[a], w), max(hi[a], w)
        parts[i] = tris
    k = height / (hi[1] - lo[1])
    mid = [(lo[a] + hi[a]) / 2 for a in range(3)]
    models = {}
    for i, tris in parts.items():
        models[nodes[i]['name']] = build(None, ('scale', k), tris)
    # the animations, sampled; each part's pose in the look's space
    lines = []
    for anim in doc.get('animations', []):
        chans = []
        for c in anim['channels']:
            smp = anim['samplers'][c['sampler']]
            times = [t[0] for t in accessor(doc, blob, smp['input'])]
            values = accessor(doc, blob, smp['output'])
            chans.append((c['target']['node'], c['target']['path'], times, values))
        length = max(ch[2][-1] for ch in chans)
        frames = max(2, int(round(length * fps)) + 1)
        last = {}
        lines.append('anim %s %d %s' % (anim['name'], frames, num(length)))
        for f in range(frames):
            at = length * f / (frames - 1)
            local = {i: list(map(list, rest[i])) for i in rest}
            for node, path, times, values in chans:
                slot = {'translation': 0, 'rotation': 1, 'scale': 2}[path]
                local[node][slot] = sample(times, values, at, path)
            world = worlds(local)
            for i in parts:
                m = world[i]
                sc = [sum(m[r][c] ** 2 for r in range(3)) ** 0.5 for c in range(3)]
                rot = [[m[r][c] / (sc[c] or 1) for c in range(3)] for r in range(3)]
                eu = euler_of(quat_of(rot))
                # unwrap: each angle the nearest to the last frame's
                prev = last.get(i)
                if prev:
                    eu = [e + 360 * round((p - e) / 360) for e, p in zip(eu, prev)]
                last[i] = eu
                pos = [(m[a][3] - mid[a]) * k for a in range(3)]
                lines.append('%d %s %s' % (f + 1, nodes[i]['name'],
                                           ','.join(num(v) for v in pos + eu + sc)))
    return models, '\n'.join(lines) + '\n'


def packed(text):
    # mtime 0: the same model always packs to the same bytes
    return base64.b64encode(gzip.compress(text.encode('ascii'), 9, mtime=0)).decode('ascii')


def block():
    palettes, cache, lines = {}, {}, []

    def palette_of(name):
        if name not in palettes:
            palettes[name] = read_png(os.path.join(SRC, name))
        return palettes[name]
    palette = palette_of('colormap.png')
    lines.append(BEGIN + ': generated by box3dxt/tools/build-game-models.py from')
    lines.append('-- box3dxt/examples/models/ (Kenney, kenney.nl, CC0); rerun the tool, never edit here.')
    lines.append('-- oiModelData(name) is a model\'s OBJ text ("<name>.obj") or its materials')
    lines.append('-- ("<name>.mtl"), gzipped and base64ed: oiModel unpacks them.')
    lines.append('private function oiModelData pName')
    lines.append('   local tData')
    lines.append('   put empty into tData')
    lines.append('   switch pName')
    for entry in MODELS:
        name, source, fit, mode = entry[:4]
        choice = entry[4] if len(entry) > 4 else {}
        key = (source, choice.get('palette', 'colormap.png'))
        if key not in cache:
            cache[key] = triangles(os.path.join(SRC, source), palette_of(key[1]))
        obj, mtl = build(fit, mode, chosen(cache[key], choice))
        for suffix, text in (('obj', obj), ('mtl', mtl)):
            data = packed(text)
            lines.append('      case "%s.%s"' % (name, suffix))
            for at in range(0, len(data), CHUNK):
                lines.append('         put "%s" after tData' % data[at:at + CHUNK])
            lines.append('         break')
    for name, source, height, fps in PARTED:
        models, anim = parted(source, height, fps, palette)
        texts = []
        for part in sorted(models):
            texts.append(('%s-%s.obj' % (name, part), models[part][0]))
            texts.append(('%s-%s.mtl' % (name, part), models[part][1]))
        texts.append(('%s.parts' % name, '\n'.join(sorted(models)) + '\n'))
        texts.append(('%s.anim' % name, anim))
        for key, text in texts:
            data = packed(text)
            lines.append('      case "%s"' % key)
            for at in range(0, len(data), CHUNK):
                lines.append('         put "%s" after tData' % data[at:at + CHUNK])
            lines.append('         break')
    lines.append('   end switch')
    lines.append('   return tData')
    lines.append('end oiModelData')
    lines.append(END)
    return '\n'.join(lines) + '\n'


def main():
    check = '--check' in sys.argv[1:]
    game = open(GAME, encoding='ascii').read()
    a, b = game.find(BEGIN), game.find(END)
    if a < 0 or b < a:
        raise SystemExit('build-game-models: no "%s" ... "%s" block in %s' % (BEGIN, END, GAME))
    b = game.index('\n', b) + 1
    want = game[:a] + block() + game[b:]
    if want == game:
        print('build-game-models: OK (%d model(s) and %d in parts carried, each matching examples/models/)' % (len(MODELS), len(PARTED)))
        return 0
    if check:
        print('build-game-models: STALE: the GAME MODELS block in %s is not what examples/models/ makes;'
              ' run python3 tools/build-game-models.py' % os.path.relpath(GAME, ROOT))
        return 1
    open(GAME, 'w', encoding='ascii', newline='\n').write(want)
    print('build-game-models: wrote %d model(s) into %s' % (len(MODELS), os.path.relpath(GAME, ROOT)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
