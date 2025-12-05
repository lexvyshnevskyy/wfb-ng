#!/bin/bash
set -e

nics="$*"
auto_nics=0
release=master

if [ $(id -u) != "0" ]
then
    echo "Root access is required. Run: sudo $0 $*"
    exit 1
fi

err_handler()
{
    echo "--------------------------------------------------------------------------------"
    echo "WFB-ng setup failed"
    exit 1
}

wfb_nics()
{
    for i in $(find /sys/class/net/ -maxdepth 1 -type l | sort)
    do
        if udevadm info $i | grep -qE 'ID_NET_DRIVER=(rtl88xxau_wfb|rtl88x2eu)'
        then
            echo $(basename $i)
        fi
    done
}

if [ -z "$nics" ]
then
    nics="$(wfb_nics)"
    auto_nics=1
fi

if [ -z "$nics" ]
then
    echo "No supported wifi adapters found, please connect them and setup drivers first"
    echo "For 8812au: https://github.com/svpcom/rtl8812au"
    echo "For 8812eu: https://github.com/svpcom/rtl8812eu"
    exit 1
fi

trap err_handler ERR

# Try to install prebuilt packages from wfb-ng apt repository

curl -s https://apt.wfb-ng.org/public.asc | gpg --dearmor --yes -o /usr/share/keyrings/wfb-ng.gpg
echo "deb [signed-by=/usr/share/keyrings/wfb-ng.gpg] https://apt.wfb-ng.org/ $(lsb_release -cs) $release" > /etc/apt/sources.list.d/wfb-ng.list

if ! apt update
then
    rm -f /etc/apt/sources.list.d/wfb-ng.list /usr/share/keyrings/wfb-ng.gpg
    apt update
fi

if ! apt -y install wfb-ng
then
    # Install required packages for wfb-ng source build

    apt -y install python3-all python3-all-dev libpcap-dev libsodium-dev libevent-dev python3-pip python3-pyroute2 python3-msgpack \
       python3-twisted python3-serial python3-jinja2 iw virtualenv debhelper dh-python fakeroot build-essential \
       libgstrtspserver-1.0-dev socat git catch2

    tmpdir="$(mktemp -d)"
    git clone -b $release --depth 1 https://github.com/svpcom/wfb-ng.git "$tmpdir"

    (cd "$tmpdir" && make deb CFLAGS="-march=native" && apt -y install ./deb_dist/*.deb)
    rm -rf "$tmpdir"
fi

# Create key and copy to right location
(cd /etc && wfb_keygen)

if [ $auto_nics -eq 0 ]
then
    echo "Saving WFB_NICS=\"$nics\" to /etc/default/wifibroadcast"
    echo "WFB_NICS=\"$nics\"" > /etc/default/wifibroadcast
else
    echo "Using wifi autodetection"
fi

if [ -f /etc/dhcpcd.conf ]; then
    echo "denyinterfaces $nics" >> /etc/dhcpcd.conf
fi
