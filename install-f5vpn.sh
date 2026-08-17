#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEB_FILE="${SCRIPT_DIR}/linux_f5vpn.x86_64.deb"

if [[ ! -f "$DEB_FILE" ]]; then
    echo "Error: $DEB_FILE not found" >&2
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    echo "Error: must be run as root" >&2
    exit 1
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

echo "Extracting $DEB_FILE..."
ar x --output="$TMPDIR" "$DEB_FILE"

echo "Installing files to /opt/f5/vpn/..."
mkdir -p /opt/f5/vpn
tar xzf "$TMPDIR/data.tar.gz" -C /

echo "Setting permissions on svpn (SUID root)..."
chown root /opt/f5/vpn/svpn
chmod 4755 /opt/f5/vpn/svpn

echo "Creating Qt platform wrapper script..."
mv /opt/f5/vpn/f5vpn /opt/f5/vpn/f5vpn-bin
setcap cap_kill+ep /opt/f5/vpn/f5vpn-bin
cat > /opt/f5/vpn/f5vpn << 'WRAPPER'
#!/bin/bash
export QT_QPA_PLATFORM=xcb
exec /opt/f5/vpn/f5vpn-bin "$@"
WRAPPER
chmod +x /opt/f5/vpn/f5vpn

echo "Creating runtime directory..."
mkdir -p /usr/local/lib/F5Networks/SSLVPN/var/run

echo "Installing desktop integration..."
cp /opt/f5/vpn/com.f5.f5vpn.desktop /usr/share/applications/
cp /opt/f5/vpn/com.f5.f5vpn.service /usr/share/dbus-1/services/

for size in 16 24 32 48 64 96 128 256 512 1024; do
    dir="/usr/share/icons/hicolor/${size}x${size}/apps"
    mkdir -p "$dir"
    cp /opt/f5/vpn/logos/${size}x${size}.png "$dir/f5vpn.png"
done

echo "Installing compatible libxml2 for bundled Qt5WebKit..."
LIBXML2_DEB_URL="http://archive.ubuntu.com/ubuntu/pool/main/libx/libxml2/libxml2_2.9.4+dfsg1-6.1ubuntu1.9_amd64.deb"
curl -sLo "$TMPDIR/libxml2-old.deb" "$LIBXML2_DEB_URL"
ar x --output="$TMPDIR/libxml2" "$TMPDIR/libxml2-old.deb"
tar xJf "$TMPDIR/libxml2/data.tar.xz" -C "$TMPDIR/libxml2" --wildcards '*/libxml2.so.2*'
LIBXML2_FILE="$(find "$TMPDIR/libxml2" -name 'libxml2.so.2.*' -not -name 'libxml2.so.2' -print -quit)"
LIBXML2_SONAME="$(basename "$LIBXML2_FILE")"
cp "$LIBXML2_FILE" /opt/f5/vpn/lib/
ln -sf "$LIBXML2_SONAME" /opt/f5/vpn/lib/libxml2.so.2
echo "Installed /opt/f5/vpn/lib/$LIBXML2_SONAME"

echo "Installing compatible ICU 60 for f5vpn binary..."
ICU60_DEB_URL="http://archive.ubuntu.com/ubuntu/pool/main/i/icu/libicu60_60.2-3ubuntu3_amd64.deb"
curl -sLo "$TMPDIR/libicu60.deb" "$ICU60_DEB_URL"
ar x --output="$TMPDIR/libicu60" "$TMPDIR/libicu60.deb"
tar xJf "$TMPDIR/libicu60/data.tar.xz" -C "$TMPDIR/libicu60" --wildcards '*/lib*.so.60*'
for lib in libicuuc.so.60.2 libicudata.so.60.2 libicui18n.so.60.2; do
    cp "$TMPDIR/libicu60/usr/lib/x86_64-linux-gnu/$lib" /opt/f5/vpn/lib/
    SONAME="${lib%.2}"
    ln -sf "$lib" /opt/f5/vpn/lib/"$SONAME"
    echo "Installed /opt/f5/vpn/lib/$lib"
done

echo "Done! You can now launch F5 VPN from your app menu or run /opt/f5/vpn/f5vpn"
