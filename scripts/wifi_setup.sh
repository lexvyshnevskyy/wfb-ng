#!/bin/bash
export LC_ALL=C.UTF-8
export LANG=C.UTF-8
export LANGUAGE=C.UTF-8
set -e

###############################################################################
# Helper functions
###############################################################################

choose_eth_iface() {
    local IFACES
    IFACES=$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="ethernet"{print $1}')

    if [ -z "$IFACES" ]; then
        whiptail --title "Ethernet setup" --msgbox "No Ethernet interfaces (TYPE=ethernet) found." 10 60
        return 1
    fi

    local MENU_ITEMS=()
    for i in $IFACES; do
        MENU_ITEMS+=("$i" "Ethernet device")
    done

    ETH_IFACE=$(
      whiptail --title "Select Ethernet interface" --menu \
"Select which Ethernet interface to configure:" 15 70 5 \
"${MENU_ITEMS[@]}" \
3>&1 1>&2 2>&3
    )

    if [ $? -ne 0 ] || [ -z "$ETH_IFACE" ]; then
        return 1
    fi
    echo "$ETH_IFACE"
}

configure_eth_iface() {
    local IFACE="$1"

    # Verify interface exists and is ethernet
    if ! nmcli -t -f DEVICE,TYPE device | grep -q "^${IFACE}:ethernet$"; then
        whiptail --title "Ethernet setup" --msgbox \
"Interface '${IFACE}' is not detected as an Ethernet device.

Check cabling/driver and try again." 12 70
        return 1
    fi

    # Ask DHCP vs Static
    local USE_DHCP
    if whiptail --title "Ethernet IP mode" --yesno \
"Configure static IP on Ethernet interface ${IFACE}?

Yes  → Static IP
No   → DHCP (automatic)" \
10 70; then

        local IP_ADDR GW_ADDR
        IP_ADDR=$(whiptail --inputbox \
"Enter IPv4 address with prefix (e.g. 192.168.30.10/24):" \
10 70 "192.168.30.10/24" 3>&1 1>&2 2>&3)

        GW_ADDR=$(whiptail --inputbox \
"Enter IPv4 gateway (e.g. 192.168.30.1):" \
10 70 "192.168.30.1" 3>&1 1>&2 2>&3)

        if [ -z "$IP_ADDR" ]; then
            echo "[WARN] No IP entered, falling back to DHCP on Ethernet."
            USE_DHCP=1
        else
            USE_DHCP=0
        fi
    else
        USE_DHCP=1
    fi

    # Remove existing connection profiles bound to this interface
    local EXISTING_CON
    EXISTING_CON=$(nmcli -t -f NAME,DEVICE con show | grep ":${IFACE}" | cut -d: -f1 || true)

    if [ -n "$EXISTING_CON" ]; then
        echo "[INFO] Removing existing connection(s) for ${IFACE}: ${EXISTING_CON}"
        while read -r C; do
            [ -n "$C" ] && sudo nmcli con delete "$C" || true
        done <<< "$EXISTING_CON"
    fi

    if [ "$USE_DHCP" -eq 1 ]; then
        echo "[INFO] Creating DHCP Ethernet connection on ${IFACE}"
        sudo nmcli con add type ethernet ifname "$IFACE" con-name "${IFACE}-dhcp" \
            ipv4.method auto ipv6.method ignore connection.autoconnect yes
        whiptail --title "Ethernet setup" --msgbox \
"Ethernet ${IFACE} configured for DHCP." 10 60
    else
        echo "[INFO] Creating static Ethernet connection on ${IFACE} (${IP_ADDR}, GW ${GW_ADDR})"
        sudo nmcli con add type ethernet ifname "$IFACE" con-name "${IFACE}-static" \
            ipv4.addresses "$IP_ADDR" \
            ipv4.gateway "$GW_ADDR" \
            ipv4.method manual \
            ipv4.never-default yes \
            ipv6.method ignore \
            connection.autoconnect yes
        whiptail --title "Ethernet setup" --msgbox \
"Ethernet ${IFACE} configured with static IP:
${IP_ADDR}, gateway ${GW_ADDR}." 12 70
    fi
}

choose_wifi_iface() {
    local IFACES
    IFACES=$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="wifi"{print $1}')

    if [ -z "$IFACES" ]; then
        whiptail --title "Wi-Fi setup" --msgbox "No Wi-Fi interfaces (TYPE=wifi) found." 10 60
        return 1
    fi

    local MENU_ITEMS=()
    for i in $IFACES; do
        MENU_ITEMS+=("$i" "Wi-Fi device")
    done

    WIFI_IFACE=$(
      whiptail --title "Select Wi-Fi interface" --menu \
"Select which Wi-Fi interface to configure:" 15 70 5 \
"${MENU_ITEMS[@]}" \
3>&1 1>&2 2>&3
    )

    if [ $? -ne 0 ] || [ -z "$WIFI_IFACE" ]; then
        return 1
    fi
    echo "$WIFI_IFACE"
}

configure_wifi_iface() {
    local IFACE="$1"

    # Verify interface exists and is wifi
    if ! nmcli -t -f DEVICE,TYPE device | grep -q "^${IFACE}:wifi$"; then
        whiptail --title "Wi-Fi setup" --msgbox \
"Interface '${IFACE}' is not detected as a Wi-Fi device.

Check hardware/driver and try again." 12 70
        return 1
    fi

    # Ask SSID
    local WIFI_SSID WIFI_PASS
    WIFI_SSID=$(whiptail --inputbox "Enter Wi-Fi SSID:" 10 60 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$WIFI_SSID" ]; then
        whiptail --title "Wi-Fi setup" --msgbox "SSID not provided. Aborting Wi-Fi configuration." 10 60
        return 1
    fi

    WIFI_PASS=$(whiptail --passwordbox \
"Enter Wi-Fi password (leave empty for open network):" \
10 60 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && WIFI_PASS=""

    # Remove existing profiles on this IFACE
    local EXISTING_WIFI_CON
    EXISTING_WIFI_CON=$(nmcli -t -f NAME,DEVICE con show | grep ":${IFACE}" | cut -d: -f1 || true)

    if [ -n "$EXISTING_WIFI_CON" ]; then
        echo "[INFO] Removing existing Wi-Fi connection(s) for ${IFACE}: ${EXISTING_WIFI_CON}"
        while read -r C; do
            [ -n "$C" ] && sudo nmcli con delete "$C" || true
        done <<< "$EXISTING_WIFI_CON"
    fi

    local CON_NAME="wifi-${IFACE}"

    # Connect (create profile)
    if [ -n "$WIFI_PASS" ]; then
        echo "[INFO] Creating WPA/WPA2 Wi-Fi connection on ${IFACE}"
        if ! sudo nmcli dev wifi connect "$WIFI_SSID" password "$WIFI_PASS" ifname "$IFACE" name "$CON_NAME"; then
            whiptail --title "Wi-Fi setup" --msgbox \
"Failed to connect to SSID '${WIFI_SSID}' with password.

Check credentials and try again." 12 70
            return 1
        fi
    else
        echo "[INFO] Creating OPEN Wi-Fi connection on ${IFACE}"
        if ! sudo nmcli dev wifi connect "$WIFI_SSID" ifname "$IFACE" name "$CON_NAME"; then
            whiptail --title "Wi-Fi setup" --msgbox \
"Failed to connect to open SSID '${WIFI_SSID}'.

Check that the network is visible and try again." 12 70
            return 1
        fi
    fi

# Ensure autoconnect on boot
sudo nmcli con mod "$CON_NAME" \
    connection.autoconnect yes \
    connection.autoconnect-priority 10

    # Ask DHCP vs Static
    if whiptail --title "Wi-Fi IP mode" --yesno \
"Use static IP on Wi-Fi interface ${IFACE}?

Yes  → Static IP
No   → DHCP (automatic)" \
10 70; then

        local WIFI_IP WIFI_GW
        WIFI_IP=$(whiptail --inputbox \
"Enter IPv4 address with prefix (e.g. 192.168.1.50/24):" \
10 70 "192.168.1.50/24" 3>&1 1>&2 2>&3)

        WIFI_GW=$(whiptail --inputbox \
"Enter IPv4 gateway (e.g. 192.168.1.1):" \
10 70 "192.168.1.1" 3>&1 1>&2 2>&3)

        if [ -n "$WIFI_IP" ]; then
            echo "[INFO] Setting static IP ${WIFI_IP}, GW ${WIFI_GW} on ${CON_NAME}"
            sudo nmcli con mod "$CON_NAME" \
                ipv4.addresses "$WIFI_IP" \
                ipv4.gateway "$WIFI_GW" \
                ipv4.method manual \
                ipv6.method ignore
            whiptail --title "Wi-Fi setup" --msgbox \
"Wi-Fi ${IFACE} configured with static IP:
${WIFI_IP}, gateway ${WIFI_GW}." 12 70
        else
            echo "[WARN] No IP entered, keeping DHCP on Wi-Fi."
            sudo nmcli con mod "$CON_NAME" \
                ipv4.method auto \
                ipv6.method ignore
        fi
    else
        echo "[INFO] Using DHCP on Wi-Fi (auto)."
        sudo nmcli con mod "$CON_NAME" \
            ipv4.method auto \
            ipv6.method ignore
        whiptail --title "Wi-Fi setup" --msgbox \
"Wi-Fi ${IFACE} configured for DHCP." 10 60
    fi
}

###############################################################################
# Main menu
###############################################################################

CHOICE=$(
  whiptail --title "WFB-NG network setup" --menu \
"This script configures management interfaces for your WFB-NG system.

It does NOT touch wfb0 (Realtek link), only regular Ethernet / Wi-Fi
used for SSH, updates, QGroundControl, etc.

Choose what you want to configure now:" 20 78 5 \
"1" "RPI 3-4-5 Ethernet interface (eth0)" \
"2" "RPI 3-4-5 and PiZero wireless interface (wlan0)" \
"3" "Radxa 3E Ethernet interface (end1)" \
"4" "Radxa 3W wireless interface (wlan1)" \
"5" "Custom settings (select interface manually)" \
3>&1 1>&2 2>&3
)

if [ $? -ne 0 ]; then
    echo "[INFO] User cancelled network setup."
    exit 0
fi

case "$CHOICE" in
  1)
    # Fixed: eth0
    configure_eth_iface "eth0"
    ;;

  2)
    # Fixed: wlan0
    configure_wifi_iface "wlan0"
    ;;

  3)
    # Fixed: end1
    configure_eth_iface "end1"
    ;;

  4)
    # Fixed: wlan1
    configure_wifi_iface "wlan1"
    ;;

  5)
    # Custom: user picks type then specific interface
    CUSTOM_TYPE=$(
      whiptail --title "Custom interface type" --menu \
"Select which type of interface you want to configure:" 15 60 2 \
"1" "Ethernet (wired)" \
"2" "Wi-Fi (wireless)" \
3>&1 1>&2 2>&3
    )

    if [ $? -ne 0 ]; then
        echo "[INFO] User cancelled custom settings."
        exit 0
    fi

    case "$CUSTOM_TYPE" in
      1)
        IFACE=$(choose_eth_iface) || exit 1
        configure_eth_iface "$IFACE"
        ;;
      2)
        IFACE=$(choose_wifi_iface) || exit 1
        configure_wifi_iface "$IFACE"
        ;;
      *)
        echo "[ERR] Invalid custom type."
        exit 1
        ;;
    esac
    ;;

  *)
    echo "[ERR] Invalid choice."
    exit 1
    ;;
esac

echo "[INFO] Network setup script finished."
exit 0