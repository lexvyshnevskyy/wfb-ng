#!/bin/bash

# video via tunel
#/usr/bin/gst-launch-1.0 -v \
#  udpsrc port=5602 caps="application/x-rtp,media=video,encoding-name=H264,payload=96,clock-rate=90000" !   tee name=t     t. ! queue ! \
#  rtpjitterbuffer latency=50 ! rtph264depay ! avdec_h264 ! autovideosink sync=false     t. ! queue ! udpsink host=192.168.30.5 port=5600

#video via broadcast tunel
/usr/bin/gst-launch-1.0 -v \
  udpsrc port=5600 caps="application/x-rtp,media=video,encoding-name=H264,payload=96,clock-rate=90000" !   tee name=t     t. ! queue ! \
  rtpjitterbuffer latency=50 ! rtph264depay ! avdec_h264 ! autovideosink sync=false     t. ! queue ! udpsink host=192.168.30.5 port=5600

#/usr/bin/gst-launch-1.0 -v \
#  udpsrc port=5600 caps="application/x-rtp,media=video,encoding-name=H264,payload=96,clock-rate=90000" ! tee name=t \
#    t. ! queue ! rtpjitterbuffer latency=50 ! rtph264depay ! avdec_h264 ! autovideosink sync=false \
#    t. ! queue ! udpsink host=192.168.30.5 port=5600 \
#    t. ! queue ! udpsink host=192.168.30.6 port=5600
