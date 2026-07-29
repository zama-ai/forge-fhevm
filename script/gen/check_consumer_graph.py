#!/usr/bin/env python3
"""Assert that inheriting FhevmTest does not drag extra packages into a consumer's build.

Foundry remappings are project-global: a consumer cannot have two versions of the same
package. So every import reachable from FhevmTest.sol becomes a hard constraint on every
downstream repo. This walks that graph and fails if it reaches anything outside ALLOWED.

This is the gate that keeps the vendored, OpenZeppelin-importing host contracts out of
consumer builds — they stay in the repo for bytecode generation and our own tests, but
FhevmTest must reach them only through generated blobs and interfaces.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ENTRYPOINT = "src/FhevmTest.sol"

# Packages a consumer must already have to use this library at all.
ALLOWED = {"forge-std", "@encrypted-types"}

IMPORT_RE = re.compile(r'import\s+(?:[^"\';]*?\s+from\s*)?["\']([^"\']+)["\']')


def load_remappings() -> dict:
    with open(os.path.join(ROOT, "remappings.txt")) as fh:
        return dict(line.strip().split("=", 1) for line in fh if line.strip())


def package_of(path: str) -> str:
    """dependencies/@openzeppelin-contracts-5.1.0/... -> @openzeppelin-contracts"""
    name = path.split("/")[1]
    return re.sub(r"-\d+(\.\d+)*$", "", name)


def main() -> int:
    remap = load_remappings()

    used_remappings = set()

    def resolve(imp: str, cur: str):
        for key in sorted(remap, key=len, reverse=True):
            if imp.startswith(key):
                used_remappings.add(key)
                return os.path.normpath(remap[key] + imp[len(key):])
        if imp.startswith("."):
            return os.path.normpath(os.path.join(os.path.dirname(cur), imp))
        return None

    seen, violations = set(), []

    def walk(path: str, importer: str) -> None:
        if path in seen:
            return
        seen.add(path)
        full = os.path.join(ROOT, path)
        if not os.path.exists(full):
            violations.append((path, importer, "unresolved import"))
            return
        if path.startswith("dependencies/"):
            pkg = package_of(path)
            if pkg not in ALLOWED:
                violations.append((path, importer, f"package '{pkg}' not allowed"))
                return
        with open(full) as fh:
            src = fh.read()
        for m in IMPORT_RE.finditer(src):
            target = resolve(m.group(1), path)
            if target:
                walk(target, path)

    walk(ENTRYPOINT, "<root>")

    packages = sorted({package_of(p) for p in seen if p.startswith("dependencies/")})
    print(f"{ENTRYPOINT} reaches {len(seen)} files across packages: {', '.join(packages) or '(none)'}")
    # Anything listed here is a remapping every consumer must also define, so keep it minimal.
    print(f"remappings a consumer must provide: {', '.join(sorted(used_remappings))}")

    if violations:
        print(f"\nFAIL: {len(violations)} disallowed import(s) in the consumer compile graph:\n")
        for path, importer, why in violations:
            print(f"  {path}\n      imported by {importer}\n      {why}\n")
        print("Consumers cannot pick their own version of these packages while FhevmTest")
        print("imports them. Route the dependency through src/generated/ instead.")
        return 1

    print("OK: consumer compile graph is clean.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
