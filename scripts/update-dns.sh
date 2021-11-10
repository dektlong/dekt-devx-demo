#!/usr/bin/env bash

source .config/config-values.env

if [ "$1" == "" ] | [ "$2" == "" ] | [ "$3" == "" ]; then
    echo "Incorrect usage. Please specify ingress_service_name , ingress_namespace , record_name"
    exit
fi

ingress_service_name=$1
ingress_namespace=$2
record_name=$3

ingressType=""

echo
printf "Waiting for ingress controller to receive public address from loadbalancer ."

while [ "$ingressType" == "" ]
do
    printf "."
    ingressType=$(kubectl get svc $ingress_service_name --namespace $ingress_namespace -o=jsonpath='{.status.loadBalancer.ingress[0]}')
    sleep 1
done

if [[ "$ingressType" == *"hostname"* ]]; then
    #host-name=$(kubectl get svc $ingress_service_name --namespace $ingress_namespace -o=jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    read -p "Enter public IP of loadbalancer " ingress_public_ip
elif [[ "$ingressType" == *"ip"* ]]; then
    ingress_public_ip=$(kubectl get svc $ingress_service_name --namespace $ingress_namespace -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')
fi
        
echo
echo "updating this A record in GoDaddy:  $record_name.$DOMAIN --> $ingress_public_ip..."

# Update/Create DNS A Record

curl -s -X PUT \
    -H "Authorization: sso-key $GODADDY_API_KEY:$GODADDY_API_SECRET" "https://api.godaddy.com/v1/domains/$DOMAIN/records/A/$record_name" \
    -H "Content-Type: application/json" \
    -d "[{\"data\": \"${ingress_public_ip}\"}]"