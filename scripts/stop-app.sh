#!/usr/bin/env bash

procid=$(pgrep $1)

if [ "$procid" == "" ]
then
    echo "$1 process is not running"
else 
    kill $procid
    osascript -e 'quit app "Terminal"'
fi