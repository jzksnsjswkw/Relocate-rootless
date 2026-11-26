#!/usr/bin/env python3
"""Builds an APT index from a release's debs, carrying other projects forward.

Why a parser rather than line editing: a Packages file is RFC822, and the fields
that matter here — Description in particular — carry continuation lines whose
indentation is significant. Anything that rewrites a stanza by pattern-matching
lines will eventually mangle one, and a mangled Description makes apt reject the
whole index. python-debian's Deb822 parses and re-emits a stanza losslessly, so a
carried stanza comes back byte-identical to what went in.

Usage:
    make_index.py --tag v1.3.0 --out repo [--previous Packages] [--debs ...]

Layout produced in --out:
    Packages, Packages.gz, Packages.bz2, Packages.xz, Packages.zst
    Release            (with the checksums of the above)
    index.html         (the landing page, rendered here)
    CydiaIcon*.png, icon.png, relocate.png, pusher.png
    debs/              (mirrored dependencies)
"""

import argparse
import bz2
import gzip
import hashlib
import io
import lzma
import os
import shutil
import subprocess
import sys
from pathlib import Path

try:
    from debian.deb822 import Deb822
except ImportError:
    sys.exit("python-debian is required: pip install python-debian")


# Where the source is published, and where its debs are served from.
PAGES_URL = os.environ.get("PAGES_URL", "https://jzksnsjswkw.github.io/repo")

# This project's own packages, and the icons they are listed under.
#
# A client shows the icon named in a deb's own control when the package is
# installed, but the Icon field here is what the source listing uses — so a
# project that ships two builds, or shares a fallback filename, needs its icon
# decided by name rather than inherited.
PROJECT_ICONS = {
    "com.jzksnsjswkw.relocate-rootless": "relocate.png",
    "com.jzksnsjswkw.pusher-rootless": "pusher.png",
    "com.jzksnsjswkw.pusher-roothide": "pusher.png",
}

# Packages this project used to publish under. A carried stanza with one of these
# names is a leftover: keeping it would list a package that cannot be installed
# beside the one that replaced it.
OBSOLETE = {
    "com.jzksnsjswkw.relocate",
    "com.jzksnsjswkw.relocate-roothide",
}

DEPICTION = {
    "relocate": {"packages": ("com.jzksnsjswkw.relocate-rootless",),
                 "json": "depiction/relocate.json"},
    "pusher": {"packages": ("com.jzksnsjswkw.pusher-rootless",
                            "com.jzksnsjswkw.pusher-roothide"),
               "json": "depiction/pusher.json"},
}


def read_control(deb):
    """The deb's control fields, as a dict."""
    raw = subprocess.run(["dpkg-deb", "-f", deb], capture_output=True, check=True).stdout
    return Deb822(raw.decode("utf-8"))


def stanza_for(deb, tag):
    """The index stanza for one deb.

    Built from the deb's own control rather than copied, so the index cannot drift
    from what was actually published — the checksums and size in particular have to
    come from the file, not from a previous index.
    """
    control = read_control(deb)
    name = control["Package"]

    stanza = Deb822()
    stanza["Package"] = name

    # The row a client shows. Without it the row is the package identifier.
    display = control.get("Name") or name
    stanza["Name"] = display
    stanza["Version"] = control["Version"]
    stanza["Architecture"] = control["Architecture"]
    stanza["Section"] = control.get("Section", "Tweaks")
    stanza["Priority"] = "optional"
    stanza["Maintainer"] = control.get("Maintainer", "jzksnsjswkw")
    stanza["Installed-Size"] = control.get("Installed-Size", "0")
    stanza["Depends"] = control.get("Depends", "firmware (>= 15.0), mobilesubstrate")

    icon = PROJECT_ICONS.get(name, control.get("Icon", ""))
    if icon:
        if not icon.startswith("http"):
            icon = f"{PAGES_URL}/{icon}"
        stanza["Icon"] = icon

    depiction = control.get("Depiction")
    if depiction:
        stanza["Depiction"] = depiction

    author = control.get("Author")
    if author:
        stanza["Author"] = author

    for project in DEPICTION.values():
        if name in project["packages"]:
            stanza["Sileodepiction"] = f"{PAGES_URL}/{project['json']}"

    filename = os.path.basename(deb)
    stanza["Filename"] = (
        f"https://github.com/jzksnsjswkw/Relocate-rootless/releases/download/"
        f"{tag}/{filename}"
    )
    data = Path(deb).read_bytes()
    stanza["Size"] = str(len(data))
    stanza["MD5sum"] = hashlib.md5(data).hexdigest()
    stanza["SHA256"] = hashlib.sha256(data).hexdigest()

    description = control.get("Description", "Per-app and global GPS location override")
    stanza["Description"] = description

    return stanza


def mirrored_stanza(deb):
    """A dependency this source serves itself.

    Its Filename points at this source rather than at an upstream release, because
    a client installing the package that depends on it has only added this source —
    an unresolved dependency here stops the install half way.
    """
    control = read_control(deb)
    stanza = Deb822()
    for field in ("Package", "Version", "Architecture", "Maintainer", "Author",
                  "Section", "Description", "Depends", "Installed-Size", "Tag"):
        if control.get(field) is not None:
            stanza[field] = control[field]
    if control.get("Name"):
        stanza["Name"] = control["Name"]

    filename = os.path.basename(deb).replace("~", ".")
    stanza["Filename"] = f"{PAGES_URL}/debs/{filename}"

    data = Path(deb).read_bytes()
    stanza["Size"] = str(len(data))
    stanza["MD5sum"] = hashlib.md5(data).hexdigest()
    stanza["SHA256"] = hashlib.sha256(data).hexdigest()
    return stanza


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", required=True, help="release tag the debs belong to")
    ap.add_argument("--out", default="repo", help="directory to write the index into")
    ap.add_argument("--previous", help="current Packages file, to carry others forward")
    ap.add_argument("--debs", nargs="*", default=[], help="this release's debs")
    args = ap.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    published = []
    seen = set()
    for deb in args.debs:
        stanza = stanza_for(deb, args.tag)
        key = (stanza["Package"], stanza["Architecture"])
        if key in seen:
            continue
        seen.add(key)
        published.append(stanza)

    # Packages this run did not produce. The Pages branch is shared with other
    # projects, so dropping them would erase a source the user has already added;
    # an obsolete name of ours is the exception, because it would list a package
    # that cannot be installed beside its replacement.
    carried = []
    if args.previous and Path(args.previous).exists():
        raw = Path(args.previous).read_text(encoding="utf-8")
        for block in [b for b in raw.split("\n\n") if b.strip()]:
            stanza = Deb822(block)
            name = stanza.get("Package")
            if not name:
                continue
            if name in OBSOLETE:
                print(f"Dropped obsolete {name} from the previous index")
                continue
            if (name, stanza.get("Architecture")) in seen:
                continue
            if name in PROJECT_ICONS:
                stanza["Icon"] = f"{PAGES_URL}/{PROJECT_ICONS[name]}"
            carried.append(stanza)

    # One file, stanzas in a stable order: ours first, then the rest as they were.
    with open(out / "Packages", "wb") as fd:
        for stanza in published + carried:
            stanza.dump(fd, encoding="utf-8")
            fd.write(b"\n")

    # The compressed copies. Release lists a checksum for each, and a client may
    # fetch any of them — zst is what recent apt prefers, gz is the floor.
    index = (out / "Packages").read_bytes()
    artefacts = {
        "Packages": index,
        "Packages.gz": gzip.compress(index, 9),
        "Packages.bz2": bz2.compress(index, 9),
        "Packages.xz": lzma.compress(index, preset=9),
    }
    for name, data in artefacts.items():
        if name != "Packages":
            (out / name).write_bytes(data)

    # zst is what recent apt asks for first. Written only if zstd is present, and
    # only listed in Release when it is — a checksum for a file that does not exist
    # makes a client fail to fetch the index at all.
    if shutil.which("zstd"):
        zst = subprocess.run(["zstd", "-19", "-q", "-f",
                              "-o", str(out / "Packages.zst")],
                             input=index, capture_output=True)
        if zst.returncode == 0:
            artefacts["Packages.zst"] = (out / "Packages.zst").read_bytes()
        else:
            print("warning: zstd failed; Packages.zst not written", file=sys.stderr)
    else:
        print("note: zstd not installed; Packages.zst not written", file=sys.stderr)

    # Release: what the source is called, and the checksums of its index files.
    release = [
        "Origin: jzksnsjswkw",
        "Label: jzksnsjswkw",
        "Suite: stable",
        "Version: 1.0",
        "Codename: ios",
        "Architectures: iphoneos-arm64 iphoneos-arm64e",
        "Components: main",
        "Description: Per-app and global GPS location override for iOS",
        "Icon: file://CydiaIcon@2x.png",
    ]
    for digest, label in (("md5", "MD5Sum"), ("sha1", "SHA1"), ("sha256", "SHA256")):
        release.append(f"{label}:")
        for name in sorted(artefacts):
            data = artefacts[name]
            h = {"md5": hashlib.md5, "sha1": hashlib.sha1, "sha256": hashlib.sha256}[digest]
            release.append(f" {h(data).hexdigest()} {len(data)} {name}")
    (out / "Release").write_text("\n".join(release) + "\n", encoding="utf-8")

    # The source's icon. These are the maintainer's files, copied as-is: a build has
    # no business generating them, and doing so once replaced the maintained icon
    # with the tweak's.
    scripts = Path(__file__).parent
    for name in ("CydiaIcon.png", "CydiaIcon@2x.png", "CydiaIcon@3x.png"):
        src = scripts / name
        if not src.exists():
            sys.exit(f"error: {src} is missing — the source will list without an icon")
        shutil.copy2(src, out / name)

    for name in ("icon.png", "relocate.png", "pusher.png"):
        src = scripts / name
        if src.exists():
            shutil.copy2(src, out / name)

    # Mirrored dependencies. Copied into the tree because their Filename points here.
    mirrored = sorted(Path("packages/mirrored").glob("*.deb")) \
        if Path("packages/mirrored").is_dir() else []
    if mirrored:
        (out / "debs").mkdir(exist_ok=True)
        for deb in mirrored:
            shutil.copy2(deb, out / "debs" / deb.name.replace("~", "."))

    # The package pages. Served from here so the JSON and its images travel with
    # the source rather than depending on another host.
    if (scripts / "depiction").is_dir():
        target = out / "depiction"
        if target.exists():
            shutil.rmtree(target)
        shutil.copytree(scripts / "depiction", target,
                        ignore=shutil.ignore_patterns("CydiaIcon*", "icon.png"))

    # The landing page, with its package list rendered in. Fetching the index from
    # the browser would show a loading state first and nothing with JavaScript off.
    template = scripts / "index.html"
    if template.exists():
        rows = []
        for project in DEPICTION:
            matches = [s for s in published + carried
                       if s.get("Package", "").startswith(f"com.jzksnsjswkw.{project}")]
            if not matches:
                continue
            archs = []
            for s in matches:
                flavour = "roothide" if "arm64e" in s["Architecture"] else "rootless"
                if flavour not in archs:
                    archs.append(flavour)
            rows.append(
                '    <li><p class="name">{}</p>'
                '<p class="desc">{}</p>'
                '<p class="meta">{} · {}</p></li>'.format(
                    matches[0]["Name"],
                    matches[0]["Description"].split("\n")[0],
                    matches[0]["Version"],
                    " / ".join(archs),
                )
            )
        # Anything not in DEPICTION is still a package the source carries, and
        # leaving it off the page would misrepresent what is installable.
        listed = set()
        for stanza in published + carried:
            name = stanza.get("Package", "")
            if any(name.startswith(f"com.jzksnsjswkw.{p}") for p in DEPICTION):
                continue
            # One row per package: the two builds of a mirrored dependency differ
            # only by architecture, and listing both reads as two plugins.
            if name in listed:
                continue
            listed.add(name)
            rows.append(
                '    <li><p class="name">{}</p>'
                '<p class="desc">{}</p>'
                '<p class="meta">{}</p></li>'.format(
                    stanza.get("Name", name),
                    stanza.get("Description", "").split("\n")[0],
                    stanza.get("Version", ""),
                )
            )

        html = template.read_text(encoding="utf-8")
        html = html.replace("<!--PACKAGE_COUNT-->", str(len(rows)))
        html = html.replace("<!--PACKAGE_ROWS-->", "\n".join(rows))
        (out / "index.html").write_text(html, encoding="utf-8")
    else:
        print("warning: index.html template missing; the source URL will list files",
              file=sys.stderr)

    print(f"Indexed {len(published) + len(carried)} package(s) into {out}/")
    print(f"  {len(published)} from this release, {len(carried)} carried forward")


if __name__ == "__main__":
    main()
