#!/bin/bash

# Required packages
sudo apt-get install -y dkms build-essential bc libelf-dev linux-headers-`uname -r` whiptail \
                        git aircrack-ng gstreamer1.0-tools gstreamer1.0-plugins-good v4l-utils \
                        gstreamer1.0-plugins-ugly gstreamer1.0-plugins-bad gstreamer1.0-libav gstreamer1.0-gl


sudo apt install -y python3-all libpcap-dev libsodium-dev python3-pip python3-pyroute2 \
            python3-future python3-twisted python3-serial python3-all-dev iw virtualenv \
            debhelper dh-python build-essential network-manager

# This step will remove all available ORIGINAL drivers
whiptail --title "Wireless drivers" --yesno "Do you want to remove the old drivers and install new one?" 10 50
if [ $? -eq 0 ]; then
  echo "Removing old drivers"
  sudo dkms uninstall -m rtl8812au -v 5.2.20.2 --all || true
  sudo dkms remove -m rtl8812au -v 5.2.20.2 --all || true
  sudo dkms uninstall -m rtl88x2bu -v 5.13.1 --all || true
  sudo dkms remove -m rtl88x2bu -v 5.13.1 --all || true
  whiptail --title "Installing drivers" --msgbox "Installing drivers..." 10 50
  git config --global http.postBuffer 157286400
  git clone https://github.com/lexvyshnevskyy/rtl8812au.git
  cd rtl8812au/
  sudo ./dkms-install.sh
  sudo modprobe 88XXau_wfb
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
# maximize output power, see note below
options 88XXau_wfb rtw_tx_pwr_idx_override=45
EOF
          fi
        fi
fi

# Add UDEV configuration
whiptail --title "Configure Wireless Driver" --msgbox "Set udev" 10 50
sudo ifconfig
# Extract the wireless interface name
INTERFACE=$(ip link show | grep wlx | awk '{print $2}' | sed 's/://')

# Check if the interface was found
if [ -z "$INTERFACE" ]; then
  echo "No wireless interface found."
  exit 1
fi

# Extract the MAC address of the identified interface
MAC_ADDRESS=$(ip link show "$INTERFACE" | grep ether | awk '{print $2}')

# Check if the MAC address was successfully retrieved
if [ -z "$MAC_ADDRESS" ]; then
  echo "Failed to retrieve the MAC address."
  exit 1
fi

# Add the MAC address to the udev rules file
sudo tee /etc/udev/rules.d/65-persistent-net.rules > /dev/null <<EOF
SUBSYSTEM=="net",ACTION=="add",ATTR{address}=="$MAC_ADDRESS",NAME="wfb0"
EOF

echo "MAC address $MAC_ADDRESS for interface $INTERFACE added to /etc/udev/rules.d/65-persistent-net.rules"

whiptail --title "Installing wfbng" --msgbox "install wfbng" 10 50
git clone https://github.com/lexvyshnevskyy/wfb-ng.git
cd wfb-ng
sudo ./scripts/install_gs.sh wfb0
echo "net.core.bpf_jit_enable = 1" | sudo tee -a /etc/sysctl.conf > /dev/null
sudo sysctl -p

sudo tee -a /etc/NetworkManager/NetworkManager.conf > /dev/null << EOF
[keyfile]
unmanaged-devices=interface-name:wfb0
EOF

CHOICE=$(whiptail --title "Select Mode" --menu "Choose your option" 15 60 2 \
"1" "GS" \
"2" "DRONE" 3>&1 1>&2 2>&3)

# Check the exit status of whiptail (0 if OK was pressed, 1 if Cancel)
if [ $? -eq 0 ]; then
    case $CHOICE in
        1)
sudo tee /etc/wifibroadcast.cfg > /dev/null << EOF
[common]
wifi_channel = 161     # 161 -- radio channel @5825 MHz, range: 5815–5835 MHz, width 20MHz
                       # 1 -- radio channel @2412 Mhz,
                       # see https://en.wikipedia.org/wiki/List_of_WLAN_channels for reference
wifi_region = 'BO'     # Your country for CRDA (use BO or GY if you want max tx power)

[gs_mavlink]
peer = 'connect://127.0.0.1:14550'  # outgoing connection
# peer = 'listen://0.0.0.0:14550'   # incoming connection

[gs_video]
peer = 'connect://127.0.0.1:5600'  # outgoing connection for
                                   # video sink (QGroundControl on GS)
EOF

whiptail --title "Set default security keys?" --yesno "This will copy existing keys. If you want use fresh generated keys: Ignore this step and copy it manually from GS" 10 50
  if [ $? -eq 0 ]; then
    sudo rm /etc/gs.key
    sudo cp ./wfb-ng/gs.key /etc
  fi

sudo apt-get remove modemmanager -y
sudo apt install libfuse2 -y
sudo apt install libxcb-xinerama0 libxkbcommon-x11-0 libxcb-cursor-dev -y
sudo apt-get install libpulse-mainloop-glib0
sudo apt-get install libxcb-icccm4 libxcb-xinerama0 libxcb-keysyms1 libxcb-image0 libxcb-shm0 libxcb-randr0 libxcb-glx0
sudo apt-get install libxcb-shape0 libxcb-shm0 libxcb-xfixes0 libxcb-sync1 libxcb-randr0 libxcb-render0 libxcb-render-util0 libxcb-xinerama0 libxcb-keysyms1 libxcb-icccm4 libxcb-image0 libxcb-glx0 libxcb-dri3-0
wget https://d176tv9ibo4jno.cloudfront.net/latest/QGroundControl.AppImage
chmod +x ./QGroundControl.AppImage
sudo usermod -a -G dialout $USER

sudo systemctl enable wifibroadcast@gs.service
sudo systemctl start wifibroadcast@gs

sudo reboot
            ;;
        2)
sudo tee /etc/wifibroadcast.cfg > /dev/null << EOF
[common]
wifi_channel = 161     # 161 -- radio channel @5825 MHz, range: 5815–5835 MHz, width 20MHz
                       # 1 -- radio channel @2412 Mhz,
                       # see https://en.wikipedia.org/wiki/List_of_WLAN_channels for reference
wifi_region = 'BO'     # Your country for CRDA (use BO or GY if you want max tx power)

[drone_mavlink]
# use autopilot connected to /dev/ttyUSB0 at 115200 baud:
# peer = 'serial:ttyUSB0:115200'

# Connect to autopilot via malink-router or mavlink-proxy:
# peer = 'listen://0.0.0.0:14550'   # incoming connection
# peer = 'connect://127.0.0.1:14550'  # outgoing connection

[drone_video]
peer = 'listen://0.0.0.0:5602'  # listen for video stream (gstreamer on drone)
EOF
whiptail --title "Set default security keys?" --yesno "This will copy existing keys. If you want use fresh generated keys: Ignore this step and copy it manually from GS" 10 50
  if [ $? -eq 0 ]; then
        sudo rm /etc/gs.key
        sudo cp ./wfb-ng/drone.key /etc
  fi
sudo systemctl enable wifibroadcast@drone.service
sudo systemctl start wifibroadcast@drone

# TODO: add services
#whiptail --title "Start Video Transmission service?" --yesno "Start Video Transmission service? This will create service for GStreamer" 10 50
#if [ $? -eq 0 ]; then
#sudo tee /etc/modprobe.d/wfb.conf > /dev/null << EOF
## blacklist stock module
#blacklist 88XXau
#blacklist 8812au
#blacklist rtl8812au
#blacklist rtl88x2bs
## maximize output power, see note below
#options 88XXau_wfb rtw_tx_pwr_idx_override=30
#EOF
#fi

sudo reboot
            ;;
    esac
else
    echo "User cancelled."
    exit 1
fi

