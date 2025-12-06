#!/bin/bash
set -e

# Helper: always try to unmount on exit if mounted
MNT="/mnt/wfb_keys"
MOUNTED=0

cleanup() {
    if [ $MOUNTED -eq 1 ]; then
        echo "[INFO] Unmounting USB drive..."
        sudo umount "$MNT" || true
        sudo rm -r "$MNT"
        MOUNTED=0
    fi
}
trap cleanup EXIT

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root: sudo $0"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

###############################################################################
# Select role – where are we applying keys?
###############################################################################
ROLE=$(
  whiptail --title "Apply WFB-NG keys" --menu \
"Select what this device is:

This helps decide where to copy drone.key and gs.key." 15 75 3 \
"1" "Ground Station (GS)" \
"2" "Drone (Air Unit)" \
"3" "Generic (just copy keys into /etc)" \
3>&1 1>&2 2>&3
) || exit 1

###############################################################################
# Ask user to attach USB drive
###############################################################################
whiptail --title "Attach USB drive" --msgbox \
"Attach the USB flash drive that contains:

  drone.key and/or gs.key

The script will search for a USB mass-storage device and copy
the keys into /etc/ on this system." 13 75

###############################################################################
# Detect USB block device (e.g. /dev/sda)
###############################################################################
USB_DEV=""
for retry in {1..30}; do
    for d in /dev/sd[a-z]; do
        [ -b "$d" ] || continue
        if udevadm info "$d" 2>/dev/null | grep -q "ID_BUS=usb"; then
            USB_DEV="$d"
            break 2
        fi
    done
    sleep 1
done

if [ -z "$USB_DEV" ]; then
    whiptail --title "USB not found" --msgbox \
"No USB flash drive was detected within timeout.

You can run this script again when the drive is attached." 10 70
    exit 1
fi

echo "[INFO] USB flash drive detected: $USB_DEV"

# Prefer first partition on that device if present
if [ -b "${USB_DEV}1" ]; then
    USB_PART="${USB_DEV}1"
else
    USB_PART="$USB_DEV"
fi

sudo mkdir -p "$MNT"

echo "[INFO] Mounting $USB_PART on $MNT..."
if ! sudo mount "$USB_PART" "$MNT"; then
    whiptail --title "Mount error" --msgbox \
"ERROR: Could not mount $USB_PART.

Please check the drive/filesystem and try again." 10 70
    exit 1
fi
MOUNTED=1

###############################################################################
# Check for keys on USB
###############################################################################
SRC_DRONE="$MNT/drone.key"
SRC_GS="$MNT/gs.key"

HAS_DRONE=0
HAS_GS=0

[ -f "$SRC_DRONE" ] && HAS_DRONE=1
[ -f "$SRC_GS" ] && HAS_GS=1

if [ $HAS_DRONE -eq 0 ] && [ $HAS_GS -eq 0 ]; then
    whiptail --title "No keys on USB" --msgbox \
"No drone.key or gs.key were found on the USB drive.

Expected locations:
  $SRC_DRONE
  $SRC_GS" 12 75
    exit 1
fi

###############################################################################
# Apply keys depending on ROLE
###############################################################################
DEST_SUMMARY=""

case "$ROLE" in
  1)  # Ground Station
      if [ $HAS_DRONE -eq 1 ]; then
          sudo cp "$SRC_DRONE" /etc/drone.key
          sudo chmod 600 /etc/drone.key
          sudo chown root:root /etc/drone.key
          DEST_SUMMARY="${DEST_SUMMARY}\n- /etc/drone.key updated"
      fi
      if [ $HAS_GS -eq 1 ]; then
          sudo cp "$SRC_GS" /etc/gs.key
          sudo chmod 600 /etc/gs.key
          sudo chown root:root /etc/gs.key
          DEST_SUMMARY="${DEST_SUMMARY}\n- /etc/gs.key updated"
      fi
      ;;

  2)  # Drone (Air Unit)
      if [ $HAS_DRONE -eq 1 ]; then
          sudo cp "$SRC_DRONE" /etc/drone.key
          sudo chmod 600 /etc/drone.key
          sudo chown root:root /etc/drone.key
          DEST_SUMMARY="${DEST_SUMMARY}\n- /etc/drone.key updated"
      fi
      if [ $HAS_GS -eq 1 ]; then
          sudo cp "$SRC_GS" /etc/gs.key
          sudo chmod 600 /etc/gs.key
          sudo chown root:root /etc/gs.key
          DEST_SUMMARY="${DEST_SUMMARY}\n- /etc/gs.key updated"
      fi
      ;;

  3)  # Generic
      if [ $HAS_DRONE -eq 1 ]; then
          sudo cp "$SRC_DRONE" /etc/drone.key
          sudo chmod 600 /etc/drone.key
          sudo chown root:root /etc/drone.key
          DEST_SUMMARY="${DEST_SUMMARY}\n- /etc/drone.key updated"
      fi
      if [ $HAS_GS -eq 1 ]; then
          sudo cp "$SRC_GS" /etc/gs.key
          sudo chmod 600 /etc/gs.key
          sudo chown root:root /etc/gs.key
          DEST_SUMMARY="${DEST_SUMMARY}\n- /etc/gs.key updated"
      fi
      ;;
esac

if [ -z "$DEST_SUMMARY" ]; then
    whiptail --title "Nothing copied" --msgbox \
"Keys were found on USB, but nothing was copied
(bug or unexpected role combination).

Check manually and rerun if needed." 12 70
    exit 1
fi

###############################################################################
# Done – tell user & ask about reboot
###############################################################################
whiptail --title "Keys applied" --msgbox \
"Keys from USB have been applied:

$DEST_SUMMARY

You should reboot this device to make sure all
WFB-NG services use the updated keys." 14 75

if whiptail --title "Reboot now?" --yesno \
"Reboot now to apply new keys?" 8 50; then
    cleanup
    sudo reboot
else
    exit 0
fi