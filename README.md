
## Original Wiki: [![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/svpcom/wfb-ng)
See https://github.com/svpcom/wfb-ng/wiki for additional info

## What this version could
1. dialog based setup
2. you could choose which board used (rpi 3-4-5, pi zero 2w, radxa 3w, radxa3e)
3. role based on selected board
4. Fixed drivers. No error in compilation
5. Fixed installing process
6. Select driver which we will use
7. you can choose: use original deb from SVcom repository or build one from source
8. manual ip configuration from menu
9. key transfer via usb, regenerate key-pairs, load new keys, switch roles, etc.

## Installation:
To install this fork run next commands

```
sudo apt update && sudo apt install git -y
git clone http://github.com/lexvyshnevskyy/wfb-ng.git
cd wfb-ng/
./install.sh
```

### Drone
#### RPI pi zero

1. Use only bookworm minimal OS installation
2. On this board only support one Video stream. Lack of resources
3. Solder your Rx/Tx to pin 8/10 (GPIO 14/GPIO 15)

---
## QGroundControl configuration

For this assembly visit [This manual](./doc/QGround.md)