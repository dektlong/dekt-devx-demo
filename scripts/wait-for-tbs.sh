#!/usr/bin/env bash

image_name=$1
namespace=$2

status=""
printf "Waiting for tanzu build service to start building $image_name image in namespace $namespace"
while [ "$status" == "" ]
do
    printf "."
    status="$(kp image status $image_name -n $namespace | grep 'Building')" 
    sleep 1
done
echo