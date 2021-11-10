#!/usr/bin/env bash

source .config/config-values.env

ingress_public_ip=""

    retrieve-ip-info ()
    {
        ingress_service_name=$1
        ingress_namespace=$2

        echo
        printf "Waiting for ingress controller to receive public IP address from loadbalancer ."

        while [ "$ingress_public_ip" == "" ]
        do
            printf "."
            ingress_public_ip="$(kubectl get svc $ingress_service_name --namespace $ingress_namespace -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')"
            sleep 1
        done
    }

    update-a-record() {

        record_name=$1
        echo
        echo "updating this A record in GoDaddy:  $record_name.$DOMAIN --> $ingress_public_ip..."

        # Update/Create DNS A Record

        curl -s -X PUT \
            -H "Authorization: sso-key $GODADDY_API_KEY:$GODADDY_API_SECRET" "https://api.godaddy.com/v1/domains/$DOMAIN/records/A/$record_name" \
            -H "Content-Type: application/json" \
            -d "[{\"data\": \"${ingress_public_ip}\"}]"
    }

case $1 in 
manual)
	read -p "enter public IP address of ingress controller " ingress_public_ip
    update-a-record $4
	;;
auto)
	retrieve-ip-info $2 $3
	update-a-record $4
  	;;
*)
  	echo "incorrect usage. specify: manual/auto ingresss-service-name ingress-ns record-name"
  	;;
esac