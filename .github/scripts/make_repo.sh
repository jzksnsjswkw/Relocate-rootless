#!/bin/bash
#
# Builds the APT repository index from the packages in the release.
#
# A Cydia/Sileo source is a directory with a `Packages` file in it. That file is a
# list of stanzas, one per package, carrying the fields the client shows and the
# URL it downloads from — nothing more. The whole of it is generated here so the
# index cannot drift from what was actually published.
#
# The debs themselves are not copied in: they live on the release page, and the
# `Filename` field points there. A source that carried its own copies would grow a
# git history the size of every build ever made, for files already served
# elsewhere.
set -euo pipefail

# Where the index is published, and where the debs are served from.
PAGES_URL="${PAGES_URL:-https://jzksnsjswkw.github.io/repo}"
RELEASES_URL="${RELEASES_URL:-https://github.com/jzksnsjswkw/Relocate-rootless/releases/download}"
TAG="${1:?usage: make_repo.sh <tag> [deb...]}"
shift

# The package page the client renders. Kept beside the index so the whole source
# is one branch, and referenced absolutely because a client fetches it directly.
DEPICTION_JSON="${DEPICTION_JSON:-$PAGES_URL/depiction/relocate.json}"

# Packages this source mirrors rather than publishes. libSandyXpc is a runtime
# dependency of Pusher, which shares this source — and its upstream release is a
# separate project that no default source carries, so a client installing Pusher
# would stop on an unresolved dependency. Serving it from here is what makes the
# source self-contained.
#
# These are the upstream release's own files, unchanged: rebuilding a dependency
# would put a second build of one library on the device, and the upstream release
# is what its author tests.
MIRRORED_DEBS=()
if [ -d "${MIRROR_DIR:-packages/mirrored}" ]; then
    while IFS= read -r -d '' file; do
        MIRRORED_DEBS+=("$file")
    done < <(find "${MIRROR_DIR:-packages/mirrored}" -name '*.deb' -print0)
fi

OUT="${OUT_DIR:-repo}"
mkdir -p "$OUT"

# Packages this project does not own, carried over from the previous index.
#
# The source on Pages is shared between projects, so a rebuild from one release's
# debs would erase every other package. The previous Packages file is read here
# and any stanza whose package name this run does not produce is written back
# verbatim — URLs, checksums and all — because nothing about it has changed.
PREVIOUS_INDEX="${PREVIOUS_INDEX:-}"

# The debs to index. Every release publishes two builds and both belong in the
# index; older releases stay on their own release pages and are not repeated here,
# because a client shows the newest version it finds and the rest is noise.
#
# The `${arr[@]+...}` form is not decoration: this script runs under `set -u`, and
# on bash 3.2 — which is what macOS still ships — expanding an empty array counts
# as an unbound variable and aborts the run. With no mirrored packages that is the
# normal case, so the guard has to be there.
if [ "$#" -gt 0 ]; then
    DEBS=("$@")
else
    DEBS=(packages/*.deb)
fi
if [ "${#MIRRORED_DEBS[@]}" -gt 0 ]; then
    DEBS+=(${MIRRORED_DEBS[@]+"${MIRRORED_DEBS[@]}"})
fi

: > "$OUT/Packages"

for deb in "${DEBS[@]}"; do
    [ -f "$deb" ] || continue

    # `dpkg-deb -f` exits 0 with empty output for a field that is not there, so
    # `field X || fallback` never falls back. Callers must test the value.
    field() { dpkg-deb -f "$deb" "$1" 2>/dev/null || true; }
    field_or() { local v; v=$(field "$1"); echo "${v:-$2}"; }

    name=$(field Package)
    version=$(field Version)
    arch=$(field Architecture)
    [ -n "$name" ] || continue

    # GitHub rewrites `~` to `.` in uploaded asset names, so the URL and the local
    # filename differ. The index has to carry the name the server actually uses.
    filename=$(basename "$deb" | tr '~' '.')
    # A mirrored deb is served from the source itself, because its upstream
    # release belongs to another project and this index is the only thing that
    # lists it. A package this repository publishes keeps pointing at its own
    # release page, where the file was uploaded as part of the build.
    case "$deb" in
        "${MIRROR_DIR:-packages/mirrored}"/*) deb_url="$PAGES_URL/debs/$filename" ;;
        *) deb_url="$RELEASES_URL/$TAG/$filename" ;;
    esac
    size=$(stat -f%z "$deb" 2>/dev/null || stat -c%s "$deb")
    md5=$(md5 -q "$deb" 2>/dev/null || md5sum "$deb" | cut -d' ' -f1)
    sha256=$(shasum -a 256 "$deb" 2>/dev/null | cut -d' ' -f1 || sha256sum "$deb" | cut -d' ' -f1)

    # Two builds are published for every release — roothide (arm64e) and rootless
    # (arm64) — and they are the same package at the same version, differing only
    # in where they install. A client keyed on the package name alone would show
    # one entry for the two and pick whichever it saw last, so each carries a
    # suffix and a `Provides` the plain name: Sileo then lists them as their own
    # rows, and anything depending on `com.jzksnsjswkw.relocate` still resolves.
    # The deb already carries the scheme suffix in its `Package:` field (the
    # Makefile adds it), so the index uses the name as-is. Appending a second
    # suffix here produced `com.jzksnsjswkw.relocate-roothide-roothide`, which apt
    # would treat as yet another package.
    pkg_name="$name"
    display_name=""
    provides=""
    # The display name sticks to Relocate's own packages. A mirrored dependency
    # keeps whatever name its control carries — it is not this project's to rename.
    case "$name" in
        com.jzksnsjswkw.relocate*)
            case "$arch" in
                iphoneos-arm64e) display_name="Relocate-roothide" ;;
                iphoneos-arm64) display_name="Relocate-rootless" ;;
            esac
            ;;
        *) display_name=$(field Name) ;;
    esac
    case "$name" in
        *-roothide|*-rootless) provides="Provides: ${name%-*}" ;;
    esac

    {
        echo "Package: $pkg_name"
        # The name Sileo lists. Without it the row shows the package identifier,
        # which is an implementation detail the reader has no use for.
        [ -n "$display_name" ] && echo "Name: $display_name"
        echo "Version: $version"
        [ -n "$provides" ] && echo "$provides"
        echo "Architecture: $arch"
        echo "Section: $(field_or Section Tweaks)"
        echo "Priority: optional"
        echo "Maintainer: $(field_or Maintainer jzksnsjswkw)"
        echo "Installed-Size: $(field_or Installed-Size 0)"
        # `firmware` is the virtual package every jailbroken device provides; the
        # constraint is what stops a client on iOS 14 from installing a build that
        # cannot run there.
        # The firmware floor belongs in the package's own control, where apt reads
        # it before downloading; this fallback is only for a control that forgot.
        echo "Depends: $(field_or Depends 'firmware (>= 15.0), mobilesubstrate')"
        # The icon and depiction are optional fields carried straight through from
        # the package's own control. They are what the client shows on the package
        # page, and a stanza that omits them gets a grey placeholder.
        # The icon is rewritten per project. The control files all point at the
        # source's shared icon.png, which is what made every row wear the same
        # picture; the index is where a per-project one can be assigned, because
        # the project is known from the package name.
        case "$name" in
            com.jzksnsjswkw.relocate*) icon="$PAGES_URL/relocate.png" ;;
            com.jzksnsjswkw.pusher*)   icon="$PAGES_URL/pusher.png" ;;
            *) icon=$(field Icon) ;;
        esac
        [ -n "$icon" ] && echo "Icon: $icon"
        depiction=$(field Depiction)
        [ -n "$depiction" ] && echo "Depiction: $depiction"
        author=$(field Author)
        [ -n "$author" ] && echo "Author: $author"
        # A rich package page — the description tabs, screenshots and the version
        # list — is a JSON document the client fetches and renders; the `Description`
        # field below is only the one-line summary some clients still show. The
        # path is absolute because the client resolves it against nothing.
        # Only for packages this project publishes. A mirrored dependency's page
        # is not ours to write, and pointing libSandyXpc at Relocate's depiction
        # showed the wrong screenshots on its row.
        case "$name" in
            com.jzksnsjswkw.relocate*)
                [ -n "$DEPICTION_JSON" ] && echo "Sileodepiction: $DEPICTION_JSON"
                ;;
        esac
        echo "Filename: $deb_url"
        echo "Size: $size"
        echo "MD5sum: $md5"
        echo "SHA256: $sha256"
        # The description goes on the field's own line, and any continuation lines
        # are indented by one space. A description printed as a bare line — which
        # is what a missing field name produces — makes APT reject the whole index.
        description=$(field Description)
        if [ -n "$description" ]; then
            # `dpkg-deb -f` keeps the control file's continuation prefix, so the
            # lines already start with one space. Re-adding a space unconditionally
            # would leave two, and a client strips only one — the paragraph marker
            # ` .` would then render as the literal text " .".
            printf '%s\n' "$description" \
                | awk 'NR==1 { print "Description: " $0 } NR>1 { sub(/^ /, ""); print " " $0 }'
        else
            echo "Description: Per-app and global GPS location override"
        fi
        echo ""
    } >> "$OUT/Packages"
done

# What this run produced, so the carry-over below knows which stanzas are stale.
NEW_NAMES=$(grep '^Package: ' "$OUT/Packages" | sed 's|^Package: ||' | sort)

if [ -n "$PREVIOUS_INDEX" ] && [ -f "$PREVIOUS_INDEX" ]; then
    # Stanzas are separated by blank lines; each starts with `Package:`.
    awk -v RS='' 'NR>0 { print $0 "\n" }' "$PREVIOUS_INDEX" | {
        current=""
        while IFS= read -r line; do
            if [ -z "$line" ]; then
                if [ -n "$current" ]; then
                    name=$(printf '%s\n' "$current" | sed -n 's|^Package: ||p' | head -1)
                    if [ -n "$name" ] && ! printf '%s\n' "$NEW_NAMES" | grep -qx "$name"; then
                        # The Icon line is rewritten on the way through. A carried
                        # stanza still names whatever icon its own build wrote, and
                        # for packages built before icons were split per project
                        # that is the shared icon.png.
                        case "$name" in
                            com.jzksnsjswkw.relocate*) carried_icon="$PAGES_URL/relocate.png" ;;
                            com.jzksnsjswkw.pusher*)   carried_icon="$PAGES_URL/pusher.png" ;;
                            *) carried_icon="" ;;
                        esac
                        if [ -n "$carried_icon" ]; then
                            printf '%s\n' "$current" \
                                | sed "s|^Icon: .*|Icon: $carried_icon|" >> "$OUT/Packages"
                        else
                            printf '%s\n' "$current" >> "$OUT/Packages"
                        fi
                        printf '\n' >> "$OUT/Packages"
                    fi
                fi
                current=""
            else
                current="$current$line
"
            fi
        done
    }
    carried=$(( $(grep -c '^Package: ' "$OUT/Packages") - $(printf '%s\n' "$NEW_NAMES" | wc -l | tr -d ' ') ))
    echo "Carried over $carried package(s) from the previous index"
fi

# Mirrored debs are copied into the published tree, because their Filename points
# at this source. Publishing them to the Pages branch is what makes the dependency
# resolvable without the user adding a second source.
if [ "${#MIRRORED_DEBS[@]}" -gt 0 ]; then
    mkdir -p "$OUT/debs"
    for deb in ${MIRRORED_DEBS[@]+"${MIRRORED_DEBS[@]}"}; do
        cp -f "$deb" "$OUT/debs/$(basename "$deb" | tr '~' '.')"
    done
fi

gzip -9 -k -f "$OUT/Packages"
if command -v bzip2 >/dev/null; then
    bzip2 -9 -k -f "$OUT/Packages"
fi

# The source's own metadata: what Sileo lists it as, and the picture beside it.
# `Label` is the name shown; without it the client falls back to the hostname.
# `Icon` is fetched from the source URL, so the avatar is committed to the branch
# rather than linked to GitHub's CDN — a source that depends on another host for
# its own icon disappears when that host moves.
cat > "$OUT/Release" <<RELEASE
Origin: jzksnsjswkw
Label: jzksnsjswkw
Suite: stable
Version: 1.0
Codename: ios
Architectures: iphoneos-arm64e iphoneos-arm64
Components: main
Description: Per-app and global GPS location override for iOS
Icon: file://CydiaIcon@2x.png
RELEASE

# The source's icon. The clients look for a file named `CydiaIcon.png` in the
# source root — a name, not a field: there is no `Icon:` key in the Release format,
# and a file called anything else is never fetched.
# Clients pick the scale that matches the screen, so all three are published.
for name in CydiaIcon CydiaIcon@2x CydiaIcon@3x; do
    src=".github/scripts/$name.png"
    if [ ! -f "$src" ]; then
        echo "error: $src is missing — the source will list without an icon" >&2
        exit 1
    fi
    cp "$src" "$OUT/$name.png"
done

# The package page's images. The JSON points at this source, so they are copied in
# rather than linked to an outside host, for the same reason the source icon is.
DEPICTION_DIR="${DEPICTION_DIR:-.github/scripts/depiction}"
# Required, not optional: without the document the package page is a blank tab in
# every client, and without the screenshots it is a page with empty frames. A
# missing file used to be skipped silently, which is how a broken source shipped
# looking fine.
for required in relocate.json; do
    if [ ! -f "$DEPICTION_DIR/$required" ]; then
        echo "error: $DEPICTION_DIR/$required is missing — the package page needs it" >&2
        exit 1
    fi
done
if [ -d "$DEPICTION_DIR" ]; then
    mkdir -p "$OUT/depiction"
    rsync -a --exclude banner.png "$DEPICTION_DIR/" "$OUT/depiction/"
fi

# Package icons.
#
# Served from here rather than from inside the deb because a client shows the icon
# before anything is installed — a `file://` path only resolves afterwards, and to
# a path that differs by packaging scheme.
#
# One file per project, because this source carries more than one: a single
# icon.png had every row wearing Relocate's icon, including Pusher's. A package
# without its own entry falls back to icon.png, so a newly added project still
# gets a picture rather than a placeholder.
for name in icon.png relocate.png pusher.png; do
    if [ -f ".github/scripts/$name" ]; then
        cp ".github/scripts/$name" "$OUT/$name"
    fi
done

# The fallback must exist — a missing icon.png is a whole source of grey squares.
if [ ! -f "$OUT/icon.png" ]; then
    echo "error: .github/scripts/icon.png is missing — package rows will show placeholders" >&2
    exit 1
fi

# The landing page. GitHub Pages serves index.html for a directory request, which
# is what makes https://.../repo/ a readable page instead of a login prompt for a
# directory listing.
#
# Rendered here rather than fetched by the browser: a page that reads Packages over
# fetch shows "loading" first and nothing at all without JavaScript. The index is
# already parsed in this script, so the rows are written once and the page is
# static.
if [ -f .github/scripts/index.html ]; then
    ROWS=$(mktemp)
    count=0
    # One row per project, not per build: Relocate ships roothide and rootless and
    # listing both would read as four plugins rather than two.
    awk -v RS='' '
        {
            pkg=""; name=""; desc=""; ver=""; arch=""
            n = split($0, lines, "\n")
            for (i = 1; i <= n; i++) {
                line = lines[i]
                if (line ~ /^Package: /)          pkg  = substr(line, 10)
                else if (line ~ /^Name: /)        name = substr(line, 7)
                else if (line ~ /^Version: /)     ver  = substr(line, 10)
                else if (line ~ /^Architecture: /) arch = substr(line, 15)
                else if (line ~ /^Description: /) desc = substr(line, 14)
            }
            if (pkg == "") next

            base = pkg
            sub(/-(roothide|rootless)$/, "", base)
            display = name
            sub(/-(roothide|rootless)$/, "", display)
            if (display == "") display = base
            flavour = (arch ~ /arm64e/) ? "roothide" : "rootless"

            if (base in seen) {
                if (index(archs[base], flavour) == 0) archs[base] = archs[base] " / " flavour
                next
            }
            seen[base] = 1
            archs[base] = flavour
            order[++count] = base
            names[base] = display
            versions[base] = ver
            descs[base] = desc
        }
        END {
            for (i = 1; i <= count; i++) {
                b = order[i]
                printf "    <li><p class=\"name\">%s</p><p class=\"desc\">%s</p><p class=\"meta\">%s \xc2\xb7 %s</p></li>\n", \
                    names[b], descs[b], versions[b], archs[b]
            }
        }
    ' "$OUT/Packages" > "$ROWS"

    # The project count is the number of rows, not of packages.
    total=$(grep -c '<li>' "$ROWS" || echo 0)

    # Substitution without sed: the replacement text carries slashes, quotes and
    # non-ASCII, and every sed invocation of that needs an escape fought over.
    awk -v rows="$ROWS" -v total="$total" '
        /<!--PACKAGE_COUNT-->/ { sub(/<!--PACKAGE_COUNT-->/, total) }
        /<!--PACKAGE_ROWS-->/  { while ((getline l < rows) > 0) print l; next }
        { print }
    ' .github/scripts/index.html > "$OUT/index.html"

    rm -f "$ROWS"
else
    echo "warning: .github/scripts/index.html is missing — the source URL will show a file listing" >&2
fi

echo "Indexed $(grep -c '^Package: ' "$OUT/Packages") package(s) into $OUT/"
ls -la "$OUT"
