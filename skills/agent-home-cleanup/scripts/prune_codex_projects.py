#!/usr/bin/env python3
"""
Remove [projects."<path>"] trust blocks for temp directories that no longer exist.

Exists because Codex records a trust entry for every directory it is run in, including
throwaway temp workspaces (e.g. /private/var/folders/.../T/<tool>-workspace-XXXX/repo),
so config.toml grows forever. Run from the agent-home-cleanup skill after the user
approves; only blocks whose body is just `trust_level = ...` are removed.

@example
    python3 prune_codex_projects.py            # dry run: count + sample
    python3 prune_codex_projects.py --apply    # rewrite atomically, backup in /tmp
"""
import os
import re
import shutil
import sys
import tempfile
import time

CFG = os.path.expanduser(os.environ.get("CODEX_HOME", "~/.codex") + "/config.toml")
TEMP_PREFIXES = ("/private/var/folders/", "/var/folders/", "/tmp/", "/private/tmp/")
HEADER = re.compile(r'^\[projects\."(?P<path>[^"]+)"\]\s*$')
TABLE = re.compile(r"^\[")


def main() -> int:
    apply = "--apply" in sys.argv
    before = os.stat(CFG).st_mtime
    lines = open(CFG, encoding="utf-8").read().splitlines(keepends=True)

    out, removed, i = [], [], 0
    while i < len(lines):
        m = HEADER.match(lines[i])
        if not m:
            out.append(lines[i])
            i += 1
            continue
        # A table runs until the next "[...]" header
        j = i + 1
        while j < len(lines) and not TABLE.match(lines[j]):
            j += 1
        body = [l.strip() for l in lines[i + 1 : j] if l.strip()]
        path = m.group("path")
        stale = path.startswith(TEMP_PREFIXES) and not os.path.exists(path)
        if stale and all(l.startswith("trust_level") for l in body):
            removed.append(path)
        else:
            out.extend(lines[i:j])
        i = j

    print(f"stale temp [projects] blocks: {len(removed)}")
    for p in removed[:5]:
        print(f"  {p}")
    if not apply or not removed:
        if removed:
            print("(dry run - pass --apply to rewrite)")
        return 0

    # Codex rewrites config.toml itself; bail out if it changed underneath us
    if os.stat(CFG).st_mtime != before:
        print("config.toml changed while processing; aborting", file=sys.stderr)
        return 1
    backup = shutil.copy2(CFG, f"/tmp/codex-config.toml.{time.strftime('%Y%m%d-%H%M%S')}")
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(CFG), prefix=".config.toml.")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write("".join(out))
    os.chmod(tmp, os.stat(CFG).st_mode & 0o777)
    os.replace(tmp, CFG)
    print(f"rewrote {CFG} (backup: {backup})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
