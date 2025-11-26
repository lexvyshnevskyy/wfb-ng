#!/bin/bash

# Required packages
sudo apt-get install -y dkms build-essential bc libelf-dev linux-headers-`uname -r` whiptail \
                        git aircrack-ng gstreamer1.0-tools gstreamer1.0-plugins-good v4l-utils \
                        gstreamer1.0-plugins-ugly gstreamer1.0-plugins-bad gstreamer1.0-libav gstreamer1.0-gl

sudo apt-get install -y \
  libcamera0.5 libcamera-ipa libcamera-apps \
  gstreamer1.0-libcamera gstreamer1.0-tools \
  gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
  gstreamer1.0-plugins-bad v4l-utils


sudo apt install -y \
  python3-all python3-all-dev python3-pip python3-serial python3-pyroute2 \
  python3-twisted libpcap-dev libsodium-dev iw virtualenv \
  debhelper dh-python build-essential network-manager

#sudo -H pip3 install --no-cache-dir future


###############################################################################
# Select board type (MANDATORY)
###############################################################################

BOARD_CHOICE=$(whiptail --title "Select Board" --menu \
"Select your board type:" 15 70 4 \
"1" "Raspberry Pi 3 / 4 / 5 (GS or Air)" \
"2" "Raspberry Pi Zero 2W (GS only via wlan0 interface, or Air)" \
"3" "Radxa Zero 3W – Ethernet mode (Air & Ground)" \
"4" "Radxa Zero 3W – WiFi mode (Air only)" \
3>&1 1>&2 2>&3)

# If user cancels → exit script
if [ $? -ne 0 ]; then
    echo "[ERR] Board selection is required. Exiting."
    exit 1
fi

# Convert selection to variable
case "$BOARD_CHOICE" in
    1)
        BOARD_TYPE="rpi"
        sudo apt install -y raspberrypi-kernel-headers
        # -----------------------------
        # Enable UART for MAVLink (Pi 3/4/5, Bookworm layout: /boot/firmware)
        # -----------------------------
        # Remove any existing serial console on UART
        sudo sed -i 's/console=serial0,[0-9]* //g' /boot/firmware/cmdline.txt
        sudo sed -i 's/console=ttyAMA0,[0-9]* //g' /boot/firmware/cmdline.txt

        # Clean previous UART/Bluetooth lines to avoid duplicates
        sudo sed -i '/^enable_uart=/d' /boot/firmware/config.txt
        sudo sed -i '/^dtoverlay=disable-bt/d' /boot/firmware/config.txt

        # Enable UART and disable BT to free UART on GPIO14/15
        sudo tee -a /boot/firmware/config.txt > /dev/null <<EOF
# Enable UART for MAVLink
enable_uart=1
# Disable Bluetooth to free primary UART for GPIO14/15
dtoverlay=disable-bt
EOF
        ;;
2)
        BOARD_TYPE="rpi_zero2"
        sudo apt install -y raspberrypi-kernel-headers

        # -----------------------------
        # Swap: universal 2G /swapfile
        # -----------------------------
        sudo swapoff -a || true
        sudo rm -f /swapfile

        # Try fallocate first (fast); fall back to dd if needed
        if ! sudo fallocate -l 2G /swapfile 2>/dev/null; then
            sudo dd if=/dev/zero of=/swapfile bs=1M count=2048 status=progress
        fi

        sudo chmod 600 /swapfile
        sudo mkswap /swapfile
        sudo swapon /swapfile

        # Make /swapfile persistent in fstab (idempotent)
        sudo sed -i '\|/swapfile|d' /etc/fstab
        echo "/swapfile swap swap defaults 0 0" | sudo tee -a /etc/fstab > /dev/null

        # -----------------------------
        # Enable UART for MAVLink
        # (Bookworm layout: /boot/firmware)
        # -----------------------------
        sudo sed -i 's/console=serial0,[0-9]* //g' /boot/firmware/cmdline.txt
        sudo sed -i 's/console=ttyAMA0,[0-9]* //g' /boot/firmware/cmdline.txt

        sudo tee -a /boot/firmware/config.txt > /dev/null <<EOF
# Enable UART for MAVLink
enable_uart=1
# Disable Bluetooth (Pi Zero 2W only)
dtoverlay=disable-bt
EOF
        ;;
    3)
        BOARD_TYPE="radxa_zero3_eth"
        sudo  apt install git openssh-server
        sudo systemctl disable --now sddm && sudo systemctl set-default multi-user.target
        sudo systemctl enable ssh
        sudo systemctl start ssh
        ;;
    4)
        BOARD_TYPE="radxa_zero3_wifi"
                sudo  apt install git openssh-server
                sudo systemctl disable --now sddm && sudo systemctl set-default multi-user.target
                sudo systemctl enable ssh
                sudo systemctl start ssh
        ;;
    *)
        echo "[ERR] Invalid board selection. Exiting."
        exit 1
        ;;
esac

echo "[INFO] Selected board: $BOARD_TYPE"

###############################################################################
# Optional Wi-Fi + IP configuration for Pi Zero 2W / Radxa Zero 3W WiFi
###############################################################################
if [ "$BOARD_TYPE" = "rpi_zero2" ] || [ "$BOARD_TYPE" = "radxa_zero3_wifi" ]; then

    if whiptail --title "Wi-Fi setup" --yesno \
"Do you want to configure onboard Wi-Fi (wlan0) now?\n\nThis is for management/home network, not wfb0." \
10 70; then

        # --- Ask SSID ---
        WIFI_SSID=$(whiptail --inputbox "Enter Wi-Fi SSID:" 10 60 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ] || [ -z "$WIFI_SSID" ]; then
            echo "[INFO] Wi-Fi SSID not provided, skipping Wi-Fi setup."
        else
            # --- Ask password (can be empty for open networks) ---
            WIFI_PASS=$(whiptail --passwordbox "Enter Wi-Fi password (leave empty for open network):" 10 60 3>&1 1>&2 2>&3)
            [ $? -ne 0 ] && WIFI_PASS=""

            # Detect first Wi-Fi device (usually wlan0)
            WIFI_IFACE=$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="wifi"{print $1; exit}')

            if [ -z "$WIFI_IFACE" ]; then
                echo "[ERR] No Wi-Fi interface detected for management (TYPE=wifi). Skipping Wi-Fi setup."
            else
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
"Use STATIC IP on Wi-Fi interface ${WIFI_IFACE}?\n\nYes → static IP\nNo  → DHCP (automatic)" \
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
            fi
        fi
    else
        echo "[INFO] Skipped onboard Wi-Fi configuration."
    fi
fi

###############################################################################
# 1. Remove old drivers and install rtl8812au / rtl8812eu
###############################################################################
whiptail --title "Wireless drivers" --yesno "Do you want to remove the old drivers and install a new one?" 10 50
if [ $? -eq 0 ]; then
  # Ask which driver to install
  DRIVER_CHOICE=$(whiptail --title "Select Realtek driver" --menu \
    "Which Realtek WFB driver do you want to install?" 15 70 2 \
    "1" "RTL8812AU (default)" \
    "2" "RTL8812EU" \
    3>&1 1>&2 2>&3)

  if [ $? -ne 0 ]; then
    echo "[INFO] Driver installation cancelled by user."
  else
    case "$DRIVER_CHOICE" in
      2)
        DRIVER_NAME="rtl8812eu"
        DRIVER_REPO="https://github.com/lexvyshnevskyy/rtl8812eu.git"
        DRIVER_DIR="rtl8812eu"
        # NOTE: adjust MODULE name if your EU driver builds a different module
        DRIVER_MODULE="8812eu"
        ;;
      1|*)
        DRIVER_NAME="rtl8812au"
        DRIVER_REPO="https://github.com/lexvyshnevskyy/rtl8812au.git"
        DRIVER_DIR="rtl8812au"
        DRIVER_MODULE="88XXau_wfb"
        ;;
    esac


    echo "Removing old drivers"
    sudo dkms uninstall -m rtl8812au -v 5.2.20.2 --all || true
    sudo dkms remove -m rtl8812au -v 5.2.20.2 --all || true
    sudo dkms uninstall -m rtl88x2bu -v 5.13.1 --all || true
    sudo dkms remove -m rtl88x2bu -v 5.13.1 --all || true
    # If rtl8812eu also gets a dkms entry later, clean it here similarly.
    sudo dkms uninstall -m rtl88x2eu -v 5.15.0.1 --all || true
    sudo dkms remove -m rtl88x2eu -v 5.15.0.1 --all || true

    whiptail --title "Installing drivers" --msgbox "Installing $DRIVER_NAME driver..." 10 50
    git config --global http.postBuffer 157286400

    TMP_DIR=$(mktemp -d)
    cd "$TMP_DIR"
    git clone "$DRIVER_REPO"
    cd "$DRIVER_DIR"

# ------------------------------------------------------------------
    # Limit DKMS build jobs: use (nproc-1) for small boards, or -j3 on Pi Zero 2W
    # ------------------------------------------------------------------
    if [ "$BOARD_TYPE" = "rpi_zero2" ] || \
       [ "$BOARD_TYPE" = "radxa_zero3_eth" ] || \
       [ "$BOARD_TYPE" = "radxa_zero3_wifi" ]; then

        if [ -f dkms.conf ]; then
            echo "[INFO] Adjusting dkms.conf MAKE jobs for small board..."

            if [ "$BOARD_TYPE" = "rpi_zero2" ]; then
                # Pi Zero 2W → force make -j3
                JOBS=3
            else
                # Calculate jobs: min( nproc-1 , 16 ), but at least 1
                JOBS=$(nproc)
                if [ "$JOBS" -gt 1 ]; then
                    JOBS=$((JOBS-1))
                fi
                if [ "$JOBS" -gt 16 ]; then
                    JOBS=16
                fi
            fi

            # Replace MAKE= line with fixed -j<JOBS>
            sudo sed -i \
                "s|^MAKE=.*|MAKE=\"'make' -j${JOBS} KVER=\${kernelver} KSRC=/lib/modules/\${kernelver}/build\"|" \
                dkms.conf

            echo "[INFO] dkms.conf: using make -j${JOBS}"
        fi
    fi

    sudo ./dkms-install.sh
    sudo modprobe "$DRIVER_MODULE"
    cd /
    sudo rm -rf "$TMP_DIR"

    echo "[OK] New driver installed and module loaded ($DRIVER_MODULE)."
  fi
fi

# Preconfiguration power state of card
whiptail --title "Configure Wireless Driver" --msgbox "Configure Wireless Driver ..." 10 50

whiptail --title "Configure Wireless Driver" --yesno "Set Default power?" 10 50
if [ $? -eq 0 ]; then
  sudo tee /etc/modprobe.d/wfb.conf > /dev/null << EOF
# blacklist stock module
blacklist 88XXau
blacklist 8812au
blacklist rtl8812au
blacklist rtl88x2bs
blacklist 88XXeu
blacklist 8812eu
blacklist rtl8812eu
# maximize output power, see note below
options 88XXau_wfb rtw_tx_pwr_idx_override=30
EOF
else
        whiptail --title "Configure Wireless Driver" --yesno "Set Max power" 10 50
        if [ $? -eq 0 ]; then
          sudo tee /etc/modprobe.d/wfb.conf > /dev/null << EOF
# blacklist stock module
blacklist 88XXau
blacklist 8812au
blacklist rtl8812au
blacklist rtl88x2bs
blacklist 88XXeu
blacklist 8812eu
blacklist rtl8812eu
# maximize output power, see note below
options 88XXau_wfb rtw_tx_pwr_idx_override=63
EOF
        else
        whiptail --title "Configure Wireless Driver" --yesno "Set Max distance" 10 50
          if [ $? -eq 0 ]; then
            sudo tee /etc/modprobe.d/wfb.conf > /dev/null << EOF
# blacklist stock module
blacklist 88XXau
blacklist 8812au
blacklist rtl8812au
blacklist rtl88x2bs
blacklist 88XXeu
blacklist 8812eu
blacklist rtl8812eu
# maximize output power, see note below
options 88XXau_wfb rtw_tx_pwr_idx_override=45
EOF
          fi
        fi
fi

# Add UDEV configuration
whiptail --title "Configure Wireless Driver" --msgbox "Set udev" 10 50

# --- Detect wireless interface using 88XXau_wfb / rtl88xxau_wfb driver ---
echo "[INFO] Detecting wireless interface using Realtek AU WFB driver ..."

# Accept both names and common variants, case-insensitive
TARGETS=("88xxau_wfb" "rtl88xxau_wfb" "88xxau" "rtl8812au" "rtl8812eu" "rtl88x2bu" "8812eu" "88xxeu_wfb" "rtl88xxeu_wfb")

normalize() { echo "$1" | tr '[:upper:]' '[:lower:]'; }

iface_driver() {
  local ifc="$1"
  # 1) ethtool (most reliable, returns "driver: <name>")
  if command -v ethtool >/dev/null 2>&1; then
    local d
    d=$(ethtool -i "$ifc" 2>/dev/null | awk -F': ' '/^driver:/{print $2}')
    if [ -n "$d" ]; then echo "$d"; return 0; fi
  fi
  # 2) kernel module basename
  local p="/sys/class/net/$ifc/device/driver/module"
  if [ -L "$p" ]; then
    basename "$(readlink -f "$p")"
    return 0
  fi
  # 3) driver dir basename
  local d2="/sys/class/net/$ifc/device/driver"
  if [ -L "$d2" ]; then
    basename "$(readlink -f "$d2")"
    return 0
  fi
  echo ""
}

INTERFACE=""
for IFACE in $(ls /sys/class/net | grep -E '^wl'); do
  D=$(iface_driver "$IFACE")
  DL=$(normalize "$D")
  for T in "${TARGETS[@]}"; do
    if [ "$DL" = "$T" ]; then
      INTERFACE="$IFACE"
      break 2
    fi
  done
done

if [ -z "$INTERFACE" ]; then
  echo "[ERR] No wireless interface found using AU/WFB driver."
  echo "Listing all detected wireless interfaces and drivers:"
  for IFACE in $(ls /sys/class/net | grep -E '^wl'); do
    D=$(iface_driver "$IFACE"); echo "  → $IFACE uses driver: ${D:-unknown}"
  done
  exit 1
else
  echo "[OK] Found wireless interface: $INTERFACE"
fi

# Extract MAC and write persistent udev rule to rename to wfb0
MAC_ADDRESS=$(cat /sys/class/net/$INTERFACE/address 2>/dev/null)
if [ -z "$MAC_ADDRESS" ]; then
  echo "[ERR] Failed to retrieve MAC address for $INTERFACE"; exit 1
fi
echo "[INFO] Interface $INTERFACE has MAC $MAC_ADDRESS"

sudo tee /etc/udev/rules.d/65-persistent-net.rules >/dev/null <<EOF
SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="$MAC_ADDRESS", NAME="wfb0"
EOF
echo "[INFO] udev rule installed: $INTERFACE → wfb0 on next boot"


whiptail --title "Installing wfbng" --msgbox "install wfbng" 10 50
cd ~
git clone https://github.com/lexvyshnevskyy/wfb-ng.git
cd ~/wfb-ng
sudo ./scripts/install_gs.sh wfb0
sudo echo "net.core.bpf_jit_enable = 1" | sudo tee -a /etc/sysctl.conf > /dev/null
sudo sysctl -p

sudo tee -a /etc/NetworkManager/NetworkManager.conf > /dev/null << EOF
[keyfile]
unmanaged-devices=interface-name:wfb0
EOF

cd ~/wfb-ng

###############################################################################
# Select mode based on board type
###############################################################################

if [ "$BOARD_TYPE" = "rpi" ] || [ "$BOARD_TYPE" = "radxa_zero3_eth" ]; then
    # GS-capable boards
    CHOICE=$(whiptail --title "Select Mode" --menu "Choose your option" 15 60 1 \
"1" "GS (Ground Station)" \
3>&1 1>&2 2>&3)
elif [ "$BOARD_TYPE" = "rpi_zero2" ] || [ "$BOARD_TYPE" = "radxa_zero3_wifi" ]; then
    # Air-only boards
    CHOICE=$(whiptail --title "Select Mode" --menu "Choose your option" 15 60 1 \
"2" "DRONE (Air Unit)" \
3>&1 1>&2 2>&3)
else
    echo "[ERR] Unknown BOARD_TYPE: $BOARD_TYPE"
    exit 1
fi


# Check the exit status of whiptail (0 if OK was pressed, 1 if Cancel)
if [ $? -eq 0 ]; then
    case $CHOICE in
        1)


# === Copy configuration and scripts for Ground Station ===
echo "[INFO] Installing Ground Station configuration..."

# Copy required files with sudo privileges
sudo install -m 0755 ./configs/ground/video-forward-gs.sh /usr/local/bin/video-forward-gs.sh
sudo install -m 0644 ./configs/ground/wifibroadcast.cfg /etc/wifibroadcast.cfg

sudo rm -rf /etc/mavlink-router
sudo cp -r ./configs/ground/mavlink-router /etc/

# --------- Build and install mavlink-router from source ----------
echo "[INFO] Installing mavlink-router from source..."
git clone https://github.com/mavlink-router/mavlink-router.git
cd mavlink-router
git submodule update --init --recursive
sudo apt install -y git meson ninja-build pkg-config gcc g++ systemd
meson setup build .
ninja -C build
sudo ninja -C build install
sudo rm -f /etc/systemd/system/mavlink-router.service
sudo install -m 0644 ./build/mavlink-router.service /usr/lib/systemd/system/mavlink-router.service
sudo systemctl daemon-reload
sudo systemctl enable mavlink-router.service
sudo systemctl start mavlink-router.service || true
cd ..

# ----- SYSTEMD UNIT MANAGEMENT (vendor units under /usr/lib) -----
echo "[INFO] Installing systemd vendor units under /usr/lib/systemd/system"

# Remove any local overrides that might shadow vendor units
sudo rm -f /etc/systemd/system/wifibroadcast.service
sudo rm -f /etc/systemd/system/wifibroadcast@.service
sudo rm -f /etc/systemd/system/video-forward*.service

# Install vendor units (use your configs/ground copies)
sudo install -m 0644 ./configs/ground/wifibroadcast.service   /usr/lib/systemd/system/wifibroadcast.service
sudo install -m 0644 ./configs/ground/wifibroadcast@.service  /usr/lib/systemd/system/wifibroadcast@.service
sudo install -m 0644 ./configs/ground/video-forward.service      /usr/lib/systemd/system/video-forward.service


# Reload systemd to pick up new vendor units
sudo systemctl daemon-reload

# Disable any other instances to avoid conflicts
sudo systemctl disable --now wifibroadcast@drone.service 2>/dev/null || true
sudo systemctl disable --now wifibroadcast@gs.service   2>/dev/null || true

# Enable + start the GS instance; this will create:
# /etc/systemd/system/wifibroadcast.service.wants/wifibroadcast@gs.service
echo "[INFO] Enabling wifibroadcast@gs.service"
sudo systemctl enable wifibroadcast@gs.service
sudo systemctl start  wifibroadcast@gs.service

# Ensure the main unit (if it’s a target/container) is enabled as well
sudo systemctl enable wifibroadcast.service 2>/dev/null || true
sudo systemctl start  wifibroadcast.service 2>/dev/null || true

# Enable + start the air video forwarder
echo "[INFO] Enabling video-forward.service"
sudo systemctl enable video-forward.service
sudo systemctl start  video-forward.service

# Show resulting symlink to confirm
echo "[INFO] Wants symlink:"
ls -l /etc/systemd/system/wifibroadcast.service.wants/ | grep wifibroadcast@gs.service || true

echo "[INFO] Ground station setup complete."

sudo cp /etc/drone.key ~/
sudo rm -f /etc/drone.key

echo "[INFO] Ground station setup complete. Rebooting..."

sudo apt-get remove modemmanager -y
sudo apt install libfuse2 -y
sudo apt install libxcb-xinerama0 libxkbcommon-x11-0 libxcb-cursor-dev -y
sudo apt-get install -y libpulse-mainloop-glib0
sudo apt-get install -y libxcb-icccm4 libxcb-xinerama0 libxcb-keysyms1 libxcb-image0 libxcb-shm0 libxcb-randr0 libxcb-glx0
sudo apt-get install -y libxcb-shape0 libxcb-shm0 libxcb-xfixes0 libxcb-sync1 libxcb-randr0 libxcb-render0 libxcb-render-util0 libxcb-xinerama0 libxcb-keysyms1 libxcb-icccm4 libxcb-image0 libxcb-glx0 libxcb-dri3-0
sudo usermod -a -G dialout $USER

if whiptail --title "Ground Station IP" --yesno \
"Add default static IP address for GS on eth0?\n\nIP: 192.168.30.10/24\n" \
10 60; then

    # ---------------------------------------------------------------------------
    # Detect correct Ethernet interface: eth0 or end1
    # ---------------------------------------------------------------------------
    ETH_IFACE=""

    if nmcli device | grep -q "^eth0"; then
        ETH_IFACE="eth0"
    elif nmcli device | grep -q "^end1"; then
        ETH_IFACE="end1"
    else
        echo "[ERR] No Ethernet interface (eth0 or end1) found. Exiting."
        exit 1
    fi

    echo "[INFO] Using Ethernet interface: $ETH_IFACE"

    # ---------------------------------------------------------------------------
    # Remove existing connection for this interface
    # ---------------------------------------------------------------------------
    EXISTING_CON=$(nmcli -t -f NAME,DEVICE con show | grep ":${ETH_IFACE}" | cut -d: -f1)

    if [ -n "$EXISTING_CON" ]; then
        echo "[INFO] Removing existing connection: $EXISTING_CON"
        sudo nmcli con delete "$EXISTING_CON" || true
    fi

    # ---------------------------------------------------------------------------
    # Create new static connection profile
    # ---------------------------------------------------------------------------
    echo "[INFO] Creating new static IP profile on ${ETH_IFACE}"

    sudo nmcli con add type ethernet ifname "$ETH_IFACE" con-name "${ETH_IFACE}-static" \
        ipv4.addresses "192.168.30.10/24" \
        ipv4.method manual \
        ipv4.never-default yes \
        connection.autoconnect yes

    echo "[OK] Static IP configured: ${ETH_IFACE} → 192.168.30.10/24"
else
    echo "[INFO] Skipped eth0 static IP configuration."
fi

sudo reboot
            ;;
        2)
# === Copy configuration and scripts for DRONE (Air Unit) ===
echo "[INFO] Installing DRONE (air) configuration..."

sudo install -m 0755 ./configs/air/video-forward.sh /usr/local/bin/video-forward.sh
sudo install -m 0644 ./configs/air/wifibroadcast.cfg /etc/wifibroadcast.cfg

echo "[INFO] Installing systemd vendor units under /usr/lib/systemd/system"

# Remove overrides that could shadow vendor units
sudo rm -f /etc/systemd/system/wifibroadcast.service
sudo rm -f /etc/systemd/system/wifibroadcast@.service
sudo rm -f /etc/systemd/system/video-forward*.service

# Install vendor units (generic wifibroadcast units + air video-forward)
sudo install -m 0644 ./configs/ground/wifibroadcast.service   /usr/lib/systemd/system/wifibroadcast.service
sudo install -m 0644 ./configs/ground/wifibroadcast@.service  /usr/lib/systemd/system/wifibroadcast@.service
sudo install -m 0644 ./configs/air/video-forward.service      /usr/lib/systemd/system/video-forward.service

# Pick up new units
sudo systemctl daemon-reload

# Avoid conflicts with GS instance
sudo systemctl disable --now wifibroadcast@gs.service 2>/dev/null || true

# Enable the drone instance (creates ...wifibroadcast.service.wants/wifibroadcast@drone.service)
echo "[INFO] Enabling wifibroadcast@drone.service"
sudo systemctl enable wifibroadcast@drone.service
sudo systemctl start  wifibroadcast@drone.service

# (Optional) enable the main unit if used as a target
sudo systemctl enable wifibroadcast.service 2>/dev/null || true
sudo systemctl start  wifibroadcast.service 2>/dev/null || true

# Enable + start the air video forwarder
echo "[INFO] Enabling video-forward.service"
sudo systemctl enable video-forward.service
sudo systemctl start  video-forward.service

# Show resulting symlinks for verification
echo "[INFO] Wants symlinks:"
ls -l /etc/systemd/system/wifibroadcast.service.wants/ | grep -E 'wifibroadcast@drone\.service|video-forward\.service' || true

sudo cp /etc/gs.key ~/
sudo rm -f /etc/gs.key

echo "[INFO] DRONE (air) setup complete."

sudo usermod -a -G dialout $USER
sudo reboot
            ;;
    esac
else
    echo "User cancelled."
    exit 1
fi