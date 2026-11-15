#!/usr/bin/env python3
"""Wrap the ROS parts of a ~/.bashrc in the uwrt guard, so nix shells don't get apt ROS.

The guard skips them inside a riptide shell (UWRT_NIX_SHELL set) and for full Nix users
(~/.uwrt/use_nix exists). Top-level statements come from bash itself: a line is a statement
boundary when everything before it passes `bash -n`. Statements that mention ROS are wrapped,
consecutive ones (with only comments or blank lines between) in one block. Everything else,
like GPG_TTY or cargo, stays outside.

usage: patch-bashrc.py [--check | --unpatch] [--dry-run] FILE
  --check    exit 0 if FILE is guarded and sources no ROS outside the guard, else 1
  --unpatch  remove the guard lines again
"""
import argparse
import difflib
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

BASH = os.environ.get('UWRT_BASH', 'bash')
BEGIN = '# >>> uwrt nix guard >>> (uwrt setup --patch-bashrc; apt ros only outside nix shells)'
GUARD = 'if [ -z "${UWRT_NIX_SHELL:-}" ] && [ ! -f ~/.uwrt/use_nix ]; then'
END = 'fi # <<< uwrt nix guard <<<'

ROS = re.compile(r'/opt/ros|\bros2\b|\bcolcon\b|\bROS_|\bRMW_|\bZENOH|\brmw|dds_scripts|config_rmw|UWRT_|_uwrt_'
                 r'|osu-uwrt/\S*(install|setup\.(ba)?sh)|\brviz')


def parses(text):
    return subprocess.run([BASH, '-n'], input=text, text=True, capture_output=True).returncode == 0


def statements(lines):
    """Split lines into top-level statements: [(start, end)], end exclusive."""
    out, start = [], 0
    for i in range(1, len(lines) + 1):
        # cheap filter first: a continued line can't end a statement
        if lines[i - 1].rstrip('\n').endswith('\\'):
            continue
        if parses(''.join(lines[:i])):
            out.append((start, i))
            start = i
    if start != len(lines):
        sys.exit('patch-bashrc: the file doesn\'t parse with bash -n, not touching it')
    return out


def neutral(text):
    return all(not s.strip() or s.lstrip().startswith('#') for s in text.splitlines())


def patch(lines):
    stmts = statements(lines)
    kind = []
    for s, e in stmts:
        text = ''.join(lines[s:e])
        kind.append('n' if neutral(text) else 'r' if ROS.search(text) else 'o')

    # blocks: from a ros statement to the last ros statement before the next other one
    blocks, i = [], 0
    while i < len(stmts):
        if kind[i] != 'r':
            i += 1
            continue
        j = last = i
        while j < len(stmts) and kind[j] != 'o':
            if kind[j] == 'r':
                last = j
            j += 1
        blocks.append((stmts[i][0], stmts[last][1]))
        i = j

    out, pos = [], 0
    for s, e in blocks:
        out += lines[pos:s] + [BEGIN + '\n', GUARD + '\n'] + lines[s:e]
        if out[-1] and not out[-1].endswith('\n'):
            out[-1] += '\n'
        out.append(END + '\n')
        pos = e
    return out + lines[pos:], len(blocks)


def unpatch(lines):
    return [l for l in lines if l.rstrip('\n') not in (BEGIN, GUARD, END)]


def check(lines):
    """Guarded, and no ros statement outside a guard."""
    if not any(l.rstrip('\n') == BEGIN for l in lines):
        return False, 'no uwrt guard'
    depth, bad = 0, []
    for n, l in enumerate(lines, 1):
        t = l.rstrip('\n')
        if t == GUARD:
            depth += 1
        elif t == END:
            depth -= 1
        elif depth == 0 and not l.lstrip().startswith('#') and re.search(r'/opt/ros|install/(local_)?setup\.bash', l):
            bad.append(f'line {n}: {t.strip()}')
    return (not bad), ('; '.join(bad) or 'guarded')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('file', type=Path)
    ap.add_argument('--check', action='store_true')
    ap.add_argument('--unpatch', action='store_true')
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()

    lines = a.file.read_text().splitlines(keepends=True)
    if a.check:
        ok, why = check(lines)
        print(f'{a.file}: {why}')
        sys.exit(0 if ok else 1)

    if a.unpatch:
        new, msg = unpatch(lines), 'removed the uwrt guard'
    else:
        if any(l.rstrip('\n') == BEGIN for l in lines):
            print(f'{a.file}: already guarded (--unpatch first to redo it)')
            return
        new, n = patch(lines)
        msg = f'guarded {n} ros block(s)'
    if new == lines:
        print(f'{a.file}: nothing to do')
        return
    sys.stdout.writelines(difflib.unified_diff(lines, new, str(a.file), str(a.file) + ' (patched)'))
    if not parses(''.join(new)):
        sys.exit('patch-bashrc: the result doesn\'t parse, not writing it')
    if a.dry_run:
        print(f'(dry run) would have {msg}')
        return
    backup = a.file.with_name(f'{a.file.name}.uwrt-backup-{time.strftime("%Y%m%d-%H%M%S")}')
    shutil.copy2(a.file, backup)
    a.file.write_text(''.join(new))
    print(f'{a.file}: {msg}, backup at {backup}')


if __name__ == '__main__':
    main()
