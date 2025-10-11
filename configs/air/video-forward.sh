#!/bin/bash
# video-forward.sh
# Forward drone video to laptop AND create local copy for optical flow

/usr/bin/gst-launch-1.0 -v \
  libcamerasrc ! videoconvert ! video/x-raw,format=I420 ! tee name=t \
  \
  t. ! queue ! x264enc tune=zerolatency speed-preset=ultrafast bitrate=2000 key-int-max=30 byte-stream=true ! h264parse ! \
      rtph264pay config-interval=1 pt=96 ! udpsink host=10.5.0.2 port=5602 sync=false \
  \
  t. ! queue ! videoscale ! video/x-raw,width=640,height=480,format=I420 ! videorate ! video/x-raw,framerate=15/1 ! \
      x264enc tune=zerolatency speed-preset=superfast bitrate=500 key-int-max=15 byte-stream=true ! h264parse ! \
      rtph264pay config-interval=1 pt=96 ! udpsink host=127.0.0.1 port=5603 sync=false


#/usr/bin/gst-launch-1.0 -v \
#  libcamerasrc ! videoconvert !   x264enc tune=zerolatency speed-preset=ultrafast bitrate=2000 key-int-max=30 byte-stream=true ! \
#  h264parse ! rtph264pay config-interval=1 pt=96 !   udpsink host=10.5.0.2 port=5602


