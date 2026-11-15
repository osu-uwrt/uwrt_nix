#!/usr/bin/env python3
"""Regenerate deps/system-keys.json from the pinned rosdistro's rosdep rules.

Keeps every key that has a plain `nixos:` package list. pip-only nixos rules are
left out (nix can't install those); add them to deps/team-keys.json if we need one.
"""
import json
import sys
from pathlib import Path

import yaml


def main():
    if len(sys.argv) != 3:
        sys.exit('usage: update-system-keys.py <rosdistro source> <out.json>')
    rosdistro, out = Path(sys.argv[1]), Path(sys.argv[2])

    keys = {}
    skipped = []
    for name in ('base.yaml', 'python.yaml'):
        rules = yaml.safe_load((rosdistro / 'rosdep' / name).read_text())
        for key, rule in rules.items():
            nixos = rule.get('nixos') if isinstance(rule, dict) else None
            if nixos is None:
                continue
            if isinstance(nixos, list):
                keys[key] = nixos
            else:
                skipped.append(key)

    out.write_text(json.dumps(dict(sorted(keys.items())), indent=1) + '\n')
    print(f'{len(keys)} keys -> {out}')
    if skipped:
        print(f'skipped (not a plain package list): {" ".join(sorted(skipped))}')


if __name__ == '__main__':
    main()
