#!/bin/bash
set -e

# Optional: allow BOARD_TYPE to be passed in, but script works even without it
BOARD_TYPE="${BOARD_TYPE:-}"

# We only really care that there *is* a Wi-Fi iface; BOARD_TYPE is only for info
echo "[INFO] Running Wi-Fi setup helper (BOARD_TYPE='${BOARD_TYPE}')"

if ! command -v nmcli >/dev/null 2>&1; then
    echo "[ERR] nmcli (NetworkManager) is not installed. Aborting Wi-Fi setup."
    exit 1
fi

if ! command -v whiptail >/dev/null 2>&1; then
    echo "[ERR] whiptail is not installed. Aborting Wi-Fi setup."
    exit 1
fi

# Ask user if they really want to run it
if ! whiptail --title "Wi-Fi setup" --yesno \
"Do you want to configure onboard Wi-Fi (wlan0) now?

This is for management/home network, not wfb0." \
10 70; then
    echo "[INFO] Wi-Fi setup cancelled by user."
    exit 0
fi

# --- Ask SSID ---
WIFI_SSID=$(whiptail --inputbox "Enter Wi-Fi SSID:" 10 60 3>&1 1>&2 2>&3)
if [ $? -ne 0 ] || [ -z "$WIFI_SSID" ]; then
    echo "[INFO] Wi-Fi SSID not provided, skipping Wi-Fi setup."
    exit 0
fi

# --- Ask password (can be empty for open networks) ---
WIFI_PASS=$(whiptail --passwordbox "Enter Wi-Fi password (leave empty for open network):" 10 60 3>&1 1>&2 2>&3)
[ $? -ne 0 ] && WIFI_PASS=""

# Detect first Wi-Fi device (usually wlan0)
WIFI_IFACE=$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="wifi"{print $1; exit}')

if [ -z "$WIFI_IFACE" ]; then
    echo "[ERR] No Wi-Fi interface detected for management (TYPE=wifi). Skipping Wi-Fi setup."
    exit 1
fi

echo "[INFO] Using Wi-Fi interface: $WIFI_IFACE"

# Remove old connection for this iface if exists
EXISTING_WIFI_CON=$(nmcli -t -f NAME,DEVICE con show | grep ":${WIFI_IFACE}" | cut -d: -f1)
if [ -n "$EXISTING_WIFI_CON" ]; then
    echo "[INFO] Removing existing Wi-Fi connection: $EXISTING_WIFI_CON"
    sudo nmcli con delete "$EXISTING_WIFI_CON" || true
fi

# Create new connection (DHCP by default)
if [ -n "$WIFI_PASS" ]; then
    echo "[INFO] Creating WPA/WPA2 Wi-Fi connection..."
    sudo nmcli dev wifi connect "$WIFI_SSID" password "$WIFI_PASS" ifname "$WIFI_IFACE" name "wifi-${WIFI_IFACE}" || \
        echo "[WARN] nmcli Wi-Fi connection failed."
else
    echo "[INFO] Creating OPEN Wi-Fi connection..."
    sudo nmcli dev wifi connect "$WIFI_SSID" ifname "$WIFI_IFACE" name "wifi-${WIFI_IFACE}" || \
        echo "[WARN] nmcli Wi-Fi connection failed."
fi

# Optional static IP on Wi-Fi
if whiptail --title "Wi-Fi IP mode" --yesno \
"Use STATIC IP on Wi-Fi interface ${WIFI_IFACE}?

Yes → static IP
No  → DHCP (automatic)" \
10 70; then

    WIFI_IP=$(whiptail --inputbox \
"Enter IPv4 address with prefix (e.g. 192.168.1.50/24):" \
10 70 "192.168.1.50/24" 3>&1 1>&2 2>&3)

    WIFI_GW=$(whiptail --inputbox \
"Enter IPv4 gateway (e.g. 192.168.1.1):" \
10 70 "192.168.1.1" 3>&1 1>&2 2>&3)

    if [ -n "$WIFI_IP" ]; then
        echo "[INFO] Setting static IP ${WIFI_IP}, GW ${WIFI_GW} on wifi-${WIFI_IFACE}"
        sudo nmcli con mod "wifi-${WIFI_IFACE}" \
            ipv4.addresses "$WIFI_IP" \
            ipv4.gateway "$WIFI_GW" \
            ipv4.method manual \
            ipv6.method ignore
    else
        echo "[WARN] No IP entered, keeping DHCP on Wi-Fi."
    fi
else
    echo "[INFO] Using DHCP on Wi-Fi (auto)."
    sudo nmcli con mod "wifi-${WIFI_IFACE}" \
        ipv4.method auto \
        ipv6.method ignore
fi

echo "[OK] Wi-Fi configuration finished."