#!/usr/bin/env bash

source secrets/config-values.env

#update-dns
    update-dns ()
    {
        ingress_service_name=$1
        ingress_namespace=$2
        record_name=$3

        echo
        echo "====> Updating your DNS ..."
        echo
        
        echo
        printf "Waiting for ingress controller to receive public IP address from loadbalancer ."

        ingress_public_ip=""

        while [ "$ingress_public_ip" == "" ]
        do
            printf "."
            ingress_public_ip="$(kubectl get svc $ingress_service_name --namespace $ingress_namespace -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')"
            sleep 1
        done
        
        echo

        echo "updating this A record in GoDaddy:  $record_name.$DOMAIN --> $ingress_public_ip..."

        # Update/Create DNS A Record

        curl -s -X PUT \
            -H "Authorization: sso-key $GODADDY_API_KEY:$GODADDY_API_SECRET" "https://api.godaddy.com/v1/domains/$DOMAIN/records/A/$record_name" \
            -H "Content-Type: application/json" \
            -d "[{\"data\": \"${ingress_public_ip}\"}]"
    }

update-dns $1 $2 $3