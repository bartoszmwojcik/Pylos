#!/usr/bin/env bash
# Build the two release files of Pylos (E07-S02, D23, D24):
#
#   pylos_<version>_amd64.deb            for Ubuntu 24.04 amd64
#   pylos-web-<version>-linux-amd64.tar.gz
#
# Usage: packaging/build-packages.sh PYLOS_WEB_BINARY VERSION OUT_DIR
#
# Run it from the repository root: it copies web/ and README.md from there.
# Both files hold only the pylos-web server and its web files (D24). The .deb
# installs /usr/bin/pylos-web and /usr/share/pylos/web, the last folder
# pylos-web looks in when no WEB_DIR is given (D26). The archive keeps
# pylos-web and web/ side by side, the second folder it looks in. There is no
# systemd service: the server is started by hand (D24).
#
# The .deb's Depends line is computed from the binary's real shared libraries
# with dpkg-shlibdeps (part of dpkg-dev), not written by hand, so it stays
# right when the dependencies change (A07). Why each choice was made:
# docs/adr/0028-release-packages.md.
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "usage: $0 PYLOS_WEB_BINARY VERSION OUT_DIR" >&2
  exit 2
fi
bin=$1
version=$2
out=$3

case "$version" in
  [0-9]*) ;;
  *) echo "$0: VERSION must start with a digit (got '$version'; drop the leading v)" >&2; exit 2 ;;
esac
[ -x "$bin" ] || { echo "$0: $bin is not an executable" >&2; exit 2; }
[ -f web/index.html ] || { echo "$0: run from the repository root (web/index.html not found)" >&2; exit 2; }

mkdir -p "$out"
out=$(cd "$out" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# --- The archive: pylos-web-<version>/{pylos-web, web/, README.md} --------
tarname="pylos-web-$version"
mkdir -p "$work/tar/$tarname"
install -m 0755 "$bin" "$work/tar/$tarname/pylos-web"
cp -r web "$work/tar/$tarname/web"
cp README.md "$work/tar/$tarname/README.md"
tar -C "$work/tar" --owner=0 --group=0 --numeric-owner -czf "$out/$tarname-linux-amd64.tar.gz" "$tarname"

# --- The Debian package ----------------------------------------------------
pkg="$work/deb"
mkdir -p "$pkg/DEBIAN" "$pkg/usr/bin" "$pkg/usr/share/pylos" "$pkg/usr/share/doc/pylos"
install -m 0755 "$bin" "$pkg/usr/bin/pylos-web"
cp -r web "$pkg/usr/share/pylos/web"
cp README.md "$pkg/usr/share/doc/pylos/README.md"
# Files 0644, folders 0755, whatever the checkout's umask was.
find "$pkg/usr/share" -type d -exec chmod 0755 {} +
find "$pkg/usr/share" -type f -exec chmod 0644 {} +

# dpkg-shlibdeps reads debian/control from the current folder, so it runs in
# a scratch folder with a minimal one. It prints "shlibs:Depends=libc6 (>= …), …".
mkdir -p "$work/shlibs/debian"
printf 'Source: pylos\n\nPackage: pylos\nArchitecture: amd64\n' > "$work/shlibs/debian/control"
depends=$(cd "$work/shlibs" && dpkg-shlibdeps -O "$pkg/usr/bin/pylos-web" | sed -n 's/^shlibs:Depends=//p')
[ -n "$depends" ] || { echo "$0: dpkg-shlibdeps found no dependencies" >&2; exit 1; }

size=$(du -sk "$pkg/usr" | cut -f1)
cat > "$pkg/DEBIAN/control" <<CONTROL
Package: pylos
Version: $version
Architecture: amd64
Maintainer: Pylos project <pylos@invalid>
Installed-Size: $size
Depends: $depends
Section: games
Priority: optional
Homepage: https://github.com/bartoszmwojcik/Pylos
Description: Pylos board game with bots and a 3D board in the browser
 Play Pylos against a computer opponent, or watch two bots play each other,
 on a 3D board in your web browser. Start the server with pylos-web and open
 http://localhost:8080. It listens on 127.0.0.1 only unless --lan is given.
CONTROL

dpkg-deb --root-owner-group --build "$pkg" "$out/pylos_${version}_amd64.deb" >/dev/null

echo "Depends: $depends"
ls -l "$out"
