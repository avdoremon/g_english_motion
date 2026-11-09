#!/usr/bin/env python3
"""Adds the Wave 1 mode tags to content items. Additive and idempotent.

  memoryFlip, catchIt  items with an image and >= 2 valid distractors
  balloonPop           items with an image and >= 2 other words of the same
                       grade at edit distance <= 2 (case-insensitive)

Never removes a tag. Writes JSON with the files' existing formatting (2-space
indent, UTF-8, trailing newline kept as found) and key order, so only `modes` arrays change.

  python3 tools/tag_modes.py [--check] [--root assets/content]

--check writes nothing and exits 1 when a write would change any file.
"""
import argparse
import glob
import json
import os
import sys

MAX_POP_DISTANCE = 2
MIN_NEIGHBOURS = 2


def lev(a, b):
    """Levenshtein edit distance."""
    if a == b:
        return 0
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def _dump(data, newline=True):
    return json.dumps(data, indent=2, ensure_ascii=False) + ('\n' if newline else '')


def _wanted(it, grade_words, all_ids):
    """Tags `it` qualifies for, in canonical order."""
    out = []
    if not it.get('image'):
        return out
    valid = [d for d in it.get('distractorIds', []) if d != it['id'] and d in all_ids]
    if len(valid) >= 2:
        out += ['memoryFlip', 'catchIt']
    me = it['word'].lower()
    near = {w for w in grade_words if w != me and lev(me, w) <= MAX_POP_DISTANCE}
    if len(near) >= MIN_NEIGHBOURS:
        out.append('balloonPop')
    return out


def run(root, check):
    paths = sorted(glob.glob(os.path.join(root, '**', '*.json'), recursive=True))
    docs = []
    for p in paths:
        with open(p, encoding='utf-8', newline='') as f:
            text = f.read()
        data = json.loads(text)
        newline = text.endswith('\n')  # some files have none; keep as is
        if _dump(data, newline) != text:
            print(f'{p}: formatting is not canonical; refusing to rewrite',
                  file=sys.stderr)
            return 2
        docs.append((p, data, newline))
    all_ids = {it['id'] for _, d, _n in docs for it in d['items']}
    words = {}
    for _, d, _n in docs:
        words.setdefault(d['grade'], set()).update(it['word'].lower() for it in d['items'])
    dirty = 0
    for p, d, newline in docs:
        changed = False
        for it in d['items']:
            for tag in _wanted(it, words[d['grade']], all_ids):
                if tag not in it['modes']:
                    it['modes'].append(tag)
                    changed = True
        if not changed:
            continue
        dirty += 1
        if check:
            print(f'{p}: needs tagging', file=sys.stderr)
        else:
            with open(p, 'w', encoding='utf-8', newline='') as f:
                f.write(_dump(d, newline))
    return 1 if (check and dirty) else 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--check', action='store_true')
    default_root = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                '..', 'assets', 'content')
    ap.add_argument('--root', default=default_root)
    args = ap.parse_args(argv)
    return run(args.root, args.check)


if __name__ == '__main__':
    sys.exit(main())
