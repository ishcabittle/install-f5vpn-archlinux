#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEB_FILE="${SCRIPT_DIR}/linux_f5vpn.x86_64.deb"

F5EPI_DEB="${SCRIPT_DIR}/linux_f5epi.x86_64.deb"
LIBXML2_DEB="${SCRIPT_DIR}/libxml2-old.deb"
ICU60_DEB="${SCRIPT_DIR}/libicu60.deb"

for f in "$DEB_FILE" "$F5EPI_DEB" "$LIBXML2_DEB" "$ICU60_DEB"; do
    if [[ ! -f "$f" ]]; then
        echo "Error: $f not found" >&2
        exit 1
    fi
done

if [[ $EUID -ne 0 ]]; then
    echo "Error: must be run as root" >&2
    exit 1
fi

TMPDIR="${SCRIPT_DIR}/tmp"
#trap 'rm -rf "$TMPDIR"' EXIT

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

echo "Extracting $F5EPI_DEB..."
mkdir -p "$TMPDIR/f5epi"
ar x --output="$TMPDIR/f5epi" "$F5EPI_DEB"

echo "Installing f5epi files to /opt/f5/epi/..."
mkdir -p /opt/f5/epi
tar xzf "$TMPDIR/f5epi/data.tar.gz" -C /

echo "Creating f5epi Qt platform wrapper script..."
mv /opt/f5/epi/f5epi /opt/f5/epi/f5epi-bin
cat > /opt/f5/epi/f5epi << 'WRAPPER'
#!/bin/bash
export QT_QPA_PLATFORM=xcb
export LD_LIBRARY_PATH="/opt/f5/epi/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec /opt/f5/epi/f5epi-bin "$@"
WRAPPER
chmod +x /opt/f5/epi/f5epi

echo "Installing compatible libxml2 for bundled Qt5WebKit..."
mkdir -p "$TMPDIR/libxml2"
ar x --output="$TMPDIR/libxml2" "$LIBXML2_DEB"
tar xJf "$TMPDIR/libxml2/data.tar.xz" -C "$TMPDIR/libxml2" --wildcards '*/libxml2.so.2*'
LIBXML2_FILE="$(find "$TMPDIR/libxml2" -name 'libxml2.so.2.*' -not -name 'libxml2.so.2' -print -quit)"
LIBXML2_SONAME="$(basename "$LIBXML2_FILE")"
cp "$LIBXML2_FILE" /opt/f5/vpn/lib/
ln -sf "$LIBXML2_SONAME" /opt/f5/vpn/lib/libxml2.so.2
echo "Installed /opt/f5/vpn/lib/$LIBXML2_SONAME"

echo "Installing compatible ICU 60 for f5vpn binary..."
mkdir -p "$TMPDIR/libicu60"
ar x --output="$TMPDIR/libicu60" "$ICU60_DEB"
tar xJf "$TMPDIR/libicu60/data.tar.xz" -C "$TMPDIR/libicu60" --wildcards '*/lib*.so.60*'
for lib in libicuuc.so.60.2 libicudata.so.60.2 libicui18n.so.60.2; do
    cp "$TMPDIR/libicu60/usr/lib/x86_64-linux-gnu/$lib" /opt/f5/vpn/lib/
    SONAME="${lib%.2}"
    ln -sf "$lib" /opt/f5/vpn/lib/"$SONAME"
    echo "Installed /opt/f5/vpn/lib/$lib"
done

echo "Done! You can now launch F5 VPN from your app menu or run /opt/f5/vpn/f5vpn"
