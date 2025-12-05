#!/bin/bash
set -e

if [ "$(id -u)" != "0" ]; then
    echo "Run as root: sudo $0 [NICs...]"
    exit 1
fi

nics="$*"
auto_nics=0

# Resolve repo root (this script is expected to be in wfb-ng/scripts/)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

wfb_nics() {
    for i in $(find /sys/class/net/ -maxdepth 1 -type l | sort); do
        if udevadm info "$i" | grep -qE 'ID_NET_DRIVER=(rtl88xxau_wfb|rtl88x2eu)'; then
            echo "$(basename "$i")"
        fi
    done
}

if [ -z "$nics" ]; then
    nics="$(wfb_nics)"
    auto_nics=1
fi

if [ -z "$nics" ]; then
    echo "No supported wifi adapters found, please connect them and setup drivers first"
    exit 1
fi

apt update
apt -y install \
    python3-all python3-all-dev libpcap-dev libsodium-dev libevent-dev \
    python3-pip python3-pyroute2 python3-msgpack python3-twisted \
    python3-serial python3-jinja2 iw virtualenv debhelper dh-python \
    fakeroot build-essential libgstrtspserver-1.0-dev socat git \
    catch2

# Build from existing repo directory
cd "$REPO_ROOT"
make clean || true
make deb CFLAGS="-march=native"

echo "[INFO] Installing built .deb packages via dpkg..."
if ls deb_dist/*.deb >/dev/null 2>&1; then
    dpkg -i deb_dist/*.deb || true
    # Resolve missing dependencies
    apt-get -f install -y
else
    echo "[ERR] No .deb found in deb_dist/. Build may have failed."
    exit 1
fi

#chmod a+rx "$REPO_ROOT"/deb_dist
#chmod a+r  "$REPO_ROOT"/deb_dist/*.deb
# Install generated debs
#apt -y install "$REPO_ROOT"/deb_dist/*.deb

# Basic config – you can trim/adjust this if your main script already does most of it
(
    cd /etc
    wfb_keygen
)

if [ $auto_nics -eq 0 ]; then
    echo "WFB_NICS=\"$nics\"" > /etc/default/wifibroadcast
fi

echo "WFB-ng built from source and installed successfully."