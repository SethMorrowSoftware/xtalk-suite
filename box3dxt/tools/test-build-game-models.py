#!/usr/bin/env python3
"""Fixture test for tools/build-game-models.py --check (root CLAUDE.md:
fixture before gate). The gate compares what the game UNPACKS, not the
deflate bytes, because zlib builds pack the same text differently (a CI
runner failed the byte comparison on 2026-11-26). Proven here in memory,
on the real block: repacked at another level it still matches, and one
model's text changed by a byte it does not.
"""
import base64
import gzip
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
NS = {'__name__': 'build_game_models', '__file__': os.path.join(HERE, 'build-game-models.py')}
exec(compile(open(NS['__file__']).read(), NS['__file__'], 'exec'), NS)


def repack(block, change):
    lines, out, data, at = block.split('\n'), [], [], None
    for line in lines:
        t = line.strip()
        if t.startswith('put "') and t.endswith('" after tData'):
            data.append(t[5:-13])
            if at is None:
                at = len(out)
                out.append(None)
            continue
        if data:
            raw = change(gzip.decompress(base64.b64decode(''.join(data))))
            packed = base64.b64encode(gzip.compress(raw, 1, mtime=0)).decode('ascii')
            out[at] = '         put "%s" after tData' % packed
            data, at = [], None
        out.append(line)
    return '\n'.join(out)


def main():
    made = NS['block']()
    fails = 0
    other = repack(made, lambda raw: raw)
    if other == made:
        print('  FAIL the fixture did not repack anything'); fails += 1
    if NS['unpacked'](other) != NS['unpacked'](made):
        print('  FAIL the same models packed at another level read as different'); fails += 1
    changed = repack(made, lambda raw: raw + b' ')
    if NS['unpacked'](changed) == NS['unpacked'](made):
        print('  FAIL a model whose text changed reads as the same'); fails += 1
    if fails:
        print('test-build-game-models: FAILED (%d)' % fails)
        return 1
    print('test-build-game-models: OK (repacked models match; a changed model is refused)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
