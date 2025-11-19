#!/bin/bash

/usr/bin/gst-launch-1.0 -v \
  udpsrc port=5600 caps="application/x-rtp,media=video,encoding-name=H264,payload=96,clock-rate=90000" ! \
  tee name=t \
    t. ! queue ! udpsink host=192.168.30.5 port=5600 \
    t. ! queue ! fakesink
