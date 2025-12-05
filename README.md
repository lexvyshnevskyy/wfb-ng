
## Original Wiki: [![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/svpcom/wfb-ng)
See https://github.com/svpcom/wfb-ng/wiki for additional info

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