#!/usr/bin/env python3
"""Wrap the ROS parts of a ~/.bashrc in the uwrt guard, so nix shells don't get apt ROS.

The guard skips them inside a riptide shell (UWRT_NIX_SHELL set) and for full Nix users
(~/.uwrt/use_nix exists). Top-level statements come from bash itself: a line is a statement
boundary when everything before it passes `bash -n`. Statements that mention ROS are wrapped,
consecutive ones (with only comments or blank lines between) in one block. Everything else,
like GPG_TTY or cargo, stays outside.

A file that's already partly guarded gets the rest wrapped. Line endings (LF or CRLF) and a
missing final newline are kept, so --unpatch gives back the original bytes.

usage: patch-bashrc.py [--check | --unpatch] [--dry-run] FILE
  --check    exit 0 if FILE has no ROS statement outside a guard, else 1
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
                 r'|osu-uwrt/\S*(install|setup\.(ba)?sh)|install/(local_)?setup\.(ba|z)?sh|\brviz')


def parses(text):
    # bash -n only warns about a heredoc cut off by the end of input, so check for that too
    r = subprocess.run([BASH, '-n'], input=text, text=True, capture_output=True)
    return r.returncode == 0 and 'here-document' not in r.stderr


def split_lines(text):
    """Lines with their own endings, split on \\n only (str.splitlines also splits on \\x0c etc)."""
    return [l for l in re.split(r'(?<=\n)', text) if l]


def bare(line):
    return line.rstrip('\r\n')


def statements(lines):
    """Split lines into top-level statements: [(start, end)], end exclusive."""
    out, start = [], 0
    for i in range(1, len(lines) + 1):
        # cheap filter first: a continued line can't end a statement
        if bare(lines[i - 1]).endswith('\\'):
            continue
        if parses(''.join(lines[:i])):
            out.append((start, i))
            start = i
    if start != len(lines):
        sys.exit('patch-bashrc: the file doesn\'t parse with bash -n, not touching it')
    return out


def kind(stmt):
    """n: comments/blank, g: an existing guard, r: ros, o: anything else."""
    if bare(stmt[0]) in (BEGIN, GUARD):
        return 'g'
    text = ''.join(stmt)
    if all(not s.strip() or s.lstrip().startswith('#') for s in text.splitlines()):
        return 'n'
    return 'r' if ROS.search(text) else 'o'


def classify(lines):
    return [(s, e, kind(lines[s:e])) for s, e in statements(lines)]


def patch(lines):
    stmts = classify(lines)
    # guard lines always end in \n: `then\r` isn't a keyword to bash
    nl = '\n'

    # blocks: from a ros statement to the last ros statement before the next other one
    blocks, i = [], 0
    while i < len(stmts):
        if stmts[i][2] != 'r':
            i += 1
            continue
        j = last = i
        while j < len(stmts) and stmts[j][2] in 'rn':
            if stmts[j][2] == 'r':
                last = j
            j += 1
        blocks.append((stmts[i][0], stmts[last][1]))
        i = j

    out, pos = [], 0
    for s, e in blocks:
        out += lines[pos:s] + [BEGIN + nl, GUARD + nl] + lines[s:e]
        if out[-1].endswith('\n'):
            out.append(END + nl)
        else:
            # no final newline: give it one before the guard ends and leave END without one,
            # unpatch takes it back off
            out[-1] += nl
            out.append(END)
        pos = e
    return out + lines[pos:], len(blocks)


def unpatch(lines):
    out = [l for l in lines if bare(l) not in (BEGIN, GUARD, END)]
    if lines and lines[-1] == END and out:
        out[-1] = bare(out[-1])
    return out


def check(lines):
    """No ros statement outside a guard."""
    bad = [f'line {s + 1}: {bare(lines[s]).strip()}' for s, e, k in classify(lines) if k == 'r']
    return (not bad), ('; '.join(bad) or 'no ros outside the uwrt guard')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('file', type=Path)
    ap.add_argument('--check', action='store_true')
    ap.add_argument('--unpatch', action='store_true')
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()

    # bytes in and out, so line endings survive
    lines = split_lines(a.file.read_bytes().decode())
    if a.check:
        ok, why = check(lines)
        print(f'{a.file}: {why}')
        sys.exit(0 if ok else 1)

    if a.unpatch:
        new, msg = unpatch(lines), 'removed the uwrt guard'
    else:
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
    a.file.write_bytes(''.join(new).encode())
    print(f'{a.file}: {msg}, backup at {backup}')


if __name__ == '__main__':
    main()
