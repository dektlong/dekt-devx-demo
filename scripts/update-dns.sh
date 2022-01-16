#!/usr/bin/env bash

source .config/config-values.env

update-dns-A-record()
{

    record_name=$1
    ingress_service_name="envoy" 
    ingress_namespace="tanzu-system-ingress"

    ingressType=""

    printf "Waiting for ingress controller to receive public address from loadbalancer ."

    while [ "$ingressType" == "" ]
    do
        printf "."
        ingressType=$(kubectl get svc $ingress_service_name --namespace $ingress_namespace -o=jsonpath='{.status.loadBalancer.ingress[0]}')
        sleep 1
    done

    if [[ "$ingressType" == *"hostname"* ]]; then
        ingress_host_name=$(kubectl get svc $ingress_service_name --namespace $ingress_namespace -o=jsonpath='{.status.loadBalancer.ingress[0].hostname}')
        ingress_public_ip=$(dig +short $ingress_host_name| head -1)
        #read -p "Enter public IP of load-balancer: " ingress_public_ip
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
}

update-dns-A-record "*.sys"
update-dns-A-record "*.apps"
update-dns-A-record "*.gw"