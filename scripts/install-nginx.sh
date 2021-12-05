#!/usr/bin/env bash

source .config/config-values.env

echo
echo "=========> Install nginx ingress controller ..."
echo

# Add the ingress-nginx repository
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx

kubectl create ns nginx-system

# Use Helm to deploy an NGINX ingress controller
helm install dekt ingress-nginx/ingress-nginx \
    --namespace nginx-system \
    --set controller.replicaCount=2 \
    --set controller.nodeSelector."beta\.kubernetes\.io/os"=linux \
    --set defaultBackend.nodeSelector."beta\.kubernetes\.io/os"=linux \
    --set controller.admissionWebhooks.patch.nodeSelector."beta\.kubernetes\.io/os"=linux

scripts/update-dns.sh "dekt-ingress-nginx-controller" "nginx-system" "*.$APPS_SUB_DOMAIN"
export INGRESS_CLASS="nginx" 