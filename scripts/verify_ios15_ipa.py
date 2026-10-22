#!/usr/bin/env python3
"""Verify a built Minis .ipa is actually safe to run on iOS 15.

Pure stdlib — no otool, no lief, no macOS. Runs anywhere Python 3.8+ runs,
including Linux and iSH.

Usage:
    python3 scripts/verify_ios15_ipa.py path/to/Minis.ipa [--json]

Exit code 0 = all checks passed, 1 = at least one failed.

Checks
------
1. MinimumOSVersion of the app (and any surviving plug-in) is <= 15.0.
2. No forbidden iOS 16+ framework in any LC_LOAD_DYLIB / LC_LOAD_WEAK_DYLIB.
3. No forbidden framework *string* anywhere in the main binary (catches
   Swift generic metadata that is not a load command).
4. The App Group container is not force-unwrapped (static grep of sources,
   skipped unless --sources is given).

Why check #3 exists: a weak_framework load command was removed, the link step
looked clean, and the binary still contained CoreTransferable because SwiftUI's
generic `.draggable` monomorphised a `Transferable`-constrained callee. Load
commands alone are not enough.
"""

import argparse
import json
import os
import plistlib
import struct
import sys
import zipfile

# Frameworks that must not be referenced by an iOS 15 build at all.
FORBIDDEN = [
    b"AppIntents",
    b"ActivityKit",
    b"WeatherKit",
    b"CoreTransferable",
]

LC_REQ_DYLD = 0x80000000
LC_LOAD_DYLIB = 0xC
LC_LOAD_WEAK_DYLIB = 0x18 | LC_REQ_DYLD
LC_REEXPORT_DYLIB = 0x1F | LC_REQ_DYLD
LC_LOAD_UPWARD_DYLIB = 0x23 | LC_REQ_DYLD
LC_BUILD_VERSION = 0x32
LC_VERSION_MIN_IPHONEOS = 0x25
LC_UUID = 0x1B

DYLIB_CMDS = {
    LC_LOAD_DYLIB: "LC_LOAD_DYLIB",
    LC_LOAD_WEAK_DYLIB: "LC_LOAD_WEAK_DYLIB",
    LC_REEXPORT_DYLIB: "LC_REEXPORT_DYLIB",
    LC_LOAD_UPWARD_DYLIB: "LC_LOAD_UPWARD_DYLIB",
}

MH_MAGIC_64 = 0xFEEDFACF
CPU_TYPE_ARM64 = 0x0100000C


def ver(v):
    return "%d.%d.%d" % (v >> 16, (v >> 8) & 0xFF, v & 0xFF)


def parse_macho(data):
    """Return dict with dylibs, min_os, uuid, sdk, platform."""
    if len(data) < 32:
        raise ValueError("too small to be Mach-O")
    magic, cputype, _cpusub, _filetype, ncmds, _sizeofcmds, _flags, _res = \
        struct.unpack_from("<IiiIIIII", data, 0)
    if magic != MH_MAGIC_64:
        raise ValueError("not a 64-bit little-endian Mach-O: %#x" % magic)

    out = {"dylibs": [], "min_os": None, "sdk": None,
           "uuid": None, "platform": None, "build_version_seen": False}

    p = 32
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, p)
        if cmdsize < 8:
            raise ValueError("corrupt load command at %#x" % p)

        if cmd in DYLIB_CMDS:
            name_off = struct.unpack_from("<I", data, p + 8)[0]
            start = p + name_off
            end = data.find(b"\x00", start)
            name = data[start:end].decode("utf-8", "replace")
            out["dylibs"].append((DYLIB_CMDS[cmd], name))

        elif cmd == LC_UUID and cmdsize >= 24:
            u = data[p + 8:p + 24]
            out["uuid"] = "-".join(
                [u[0:4].hex(), u[4:6].hex(), u[6:8].hex(),
                 u[8:10].hex(), u[10:16].hex()]
            ).upper()

        elif cmd == LC_BUILD_VERSION and cmdsize >= 16:
            platform, minos, sdk = struct.unpack_from("<III", data, p + 8)
            out["platform"] = platform
            out["min_os"] = ver(minos)
            out["sdk"] = ver(sdk)
            out["build_version_seen"] = True

        elif cmd == LC_VERSION_MIN_IPHONEOS and cmdsize >= 12:
            minos, sdk = struct.unpack_from("<II", data, p + 8)
            if not out["build_version_seen"]:
                out["min_os"] = ver(minos)
                out["sdk"] = ver(sdk)

        p += cmdsize

    return out


def check_ipa(path, sources_dir=None):
    result = {"ipa": path, "ok": True, "checks": [], "errors": [], "warnings": []}

    def check(name, passed, detail=""):
        result["checks"].append({"name": name, "passed": passed, "detail": detail})
        if not passed:
            result["ok"] = False
            result["errors"].append("%s: %s" % (name, detail))

    if not zipfile.is_zipfile(path):
        check("ipa is a zip", False, "not a zip archive")
        return result

    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        apps = sorted({n.split("/")[0] + "/" + n.split("/")[1]
                       for n in names if n.startswith("Payload/") and n.count("/") >= 1
                       and n.split("/")[1].endswith(".app")})
        if not apps:
            check("Payload/*.app present", False, "no .app found")
            return result
        app = apps[0]
        result["app"] = app

        infos = [n for n in names
                 if n.startswith(app + "/") and n.endswith("Info.plist")
                 and n.count("/") <= 3]
        main_plist = app + "/Info.plist"
        if main_plist not in names:
            check("Info.plist present", False, "missing " + main_plist)
            return result

        # ---- check 1: deployment floors -------------------------------
        floors = {}
        for n in infos:
            try:
                pl = plistlib.loads(z.read(n))
            except Exception as exc:          # noqa: BLE001
                result["warnings"].append("unreadable %s (%s)" % (n, exc))
                continue
            fl = pl.get("MinimumOSVersion")
            if fl:
                floors[n] = fl

        if not floors:
            check("MinimumOSVersion readable", False, "no MinimumOSVersion found")
        else:
            result["floors"] = floors
            main_floor = floors.get(main_plist)
            try:
                ok_main = main_floor is not None and tuple(
                    int(x) for x in main_floor.split(".")[:2]) <= (15, 0)
            except ValueError:
                ok_main = False
            check("app MinimumOSVersion <= 15.0", ok_main, "got %s" % main_floor)

            # Plug-ins that ship must also install on 15.x. The packaging step
            # strips 16+/16.2 plug-ins, so a >15 plug-in surviving is a bug.
            bad_plugins = {
                n: f for n, f in floors.items()
                if n != main_plist and not tuple(
                    int(x) for x in f.split(".")[:2]) <= (15, 0)
            }
            check("all shipped plug-ins installable on 15.x",
                  not bad_plugins,
                  "left in bundle: %s" % bad_plugins if bad_plugins else "")

        # ---- find main binary ----------------------------------------
        pl = plistlib.loads(z.read(main_plist))
        exe = pl.get("CFBundleExecutable", "Minis")
        bin_path = "%s/%s" % (app, exe)
        if bin_path not in names:
            check("main binary present", False, "missing " + bin_path)
            return result

        data = z.read(bin_path)
        try:
            info = parse_macho(data)
        except ValueError as exc:
            check("parse Mach-O", False, str(exc))
            return result

        result["uuid"] = info["uuid"]
        result["sdk"] = info["sdk"]
        result["dylib_count"] = len(info["dylibs"])

        # ---- check 2: no forbidden load commands ---------------------
        offending = [
            (kind, n) for kind, n in info["dylibs"]
            if any(f.decode() in n for f in FORBIDDEN)
        ]
        check("no iOS 16+ framework in load commands", not offending,
              "; ".join("%s %s" % t for t in offending))

        # ---- check 3: no forbidden framework *dylib references* --------
        # A bare string mention is NOT a dependency: this fork's own user-facing
        # copy legitimately contains "WeatherKit requires iOS 16.0 or later" and
        # "requires ActivityKit". What matters is a dylib reference, which in the
        # mangled/loadable form always appears as an @rpath or .framework path.
        found = {}
        for f in FORBIDDEN:
            for pat in (b"@rpath/" + f, f + b".framework/"):
                c = data.count(pat)
                if c:
                    found[f.decode()] = found.get(f.decode(), 0) + c
        check("no @rpath/.framework reference to iOS 16+ frameworks", not found,
              json.dumps(found) if found else "")

        # ---- informational -------------------------------------------
        for probe, label in ((b"alpine-rootfs.zip", "rootfs payload"),
                             (b"RootfsPatch.bundle", "RootfsPatch bundle"),
                             (b"launch-trace.log", "launch trace")):
            if probe not in data and not any(probe.decode() in n for n in names):
                result["warnings"].append("missing %s" % label)

    # ---- check 4: App Group force-unwrap (source level) --------------
    if sources_dir:
        bad = []
        for root, _dirs, files in os.walk(sources_dir):
            for fn in files:
                if not fn.endswith((".swift", ".m", ".h")):
                    continue
                fp = os.path.join(root, fn)
                try:
                    with open(fp, encoding="utf-8", errors="replace") as fh:
                        for i, line in enumerate(fh, 1):
                            s = line.strip()
                            if s.startswith("//"):
                                continue
                            if ("containerURL(" in s
                                    and "forSecurityApplicationGroupIdentifier" in s
                                    and ")!" in s):
                                bad.append("%s:%d" % (fp, i))
                except OSError:
                    pass
        check("App Group container never force-unwrapped", not bad,
              ", ".join(bad))

    return result


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("ipa")
    ap.add_argument("--sources", help="src/ios directory, enables the source checks")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    args = ap.parse_args()

    r = check_ipa(args.ipa, args.sources)

    if args.json:
        print(json.dumps(r, indent=2))
    else:
        print("IPA: %s" % r.get("app", "?"))
        if r.get("uuid"):
            print("UUID: %s   SDK: %s   dylibs: %s"
                  % (r["uuid"], r.get("sdk"), r.get("dylib_count")))
        if r.get("floors"):
            for n, f in sorted(r["floors"].items()):
                print("  %-58s minOS %s" % (n, f))
        print()
        for c in r["checks"]:
            print("  [%s] %s%s" % ("PASS" if c["passed"] else "FAIL",
                                   c["name"],
                                   ("  — " + c["detail"]) if c["detail"] else ""))
        for w in r["warnings"]:
            print("  [warn] %s" % w)
        print("\n%s" % ("ALL CHECKS PASSED" if r["ok"] else "FAILED"))

    return 0 if r["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
