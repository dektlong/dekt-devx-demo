#!/usr/bin/env bash

#access gui on localhost:7000

kubectl port-forward service/server 7000 -n tap-gui 

osascript -e 'tell application "Terminal" to set miniaturized of every window to true'