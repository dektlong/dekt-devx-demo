#!/usr/bin/env bash

source .config/config-values.env

#create-ingress-rule
create-ingress-rule() {

  ingressName=$1
  ingressClass=$2
  ingressHost=$3
  serviceName=$4
  servicePort=$5
  namespace=$6

  cat > output.yaml <<EOF
  apiVersion: networking.k8s.io/v1
  kind: Ingress 
  metadata: 
    name: $ingressName
    annotations: 
      kubernetes.io/ingress.class: $ingressClass
  spec: 
    rules: 
      - host: $ingressHost
        http: 
          paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: $serviceName
                port:
                  number: $servicePort
EOF

kubectl apply -f output.yaml -n $namespace

#more output.yaml

rm output.yaml

}

update-dns-A-record()
{

    record_name=$1
    ingress_service_name=$2
    ingress_namespace=$3

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
        echo
        echo
        echo "@@@ingress_host_name=$ingress_host_name"
        echo "@@@ingress_public_ip=$ingress_public_ip"
        echo
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

case $1 in
tap-full)
    update-dns-A-record "*.sys" "envoy" "tanzu-system-ingress"
    update-dns-A-record "*.apps" "envoy" "tanzu-system-ingress"
    ;;
tap-run)
    update-dns-A-record "*.run" "envoy" "tanzu-system-ingress"
    ;;
apis)
    create-ingress-rule "api-portal-ingress" "contour" "api-portal.sys.$DOMAIN" "api-portal-server" "8080" "api-portal"
    create-ingress-rule "scg-openapi-ingress" "contour" "scg-openapi.sys.$DOMAIN"  "scg-operator" "80" "scgw-system"
    ;;
scgw)
    scripts/install-nginx.sh
    update-dns-A-record "*.gw" "dekt-ingress-nginx-controller" "nginx-system" 
    create-ingress-rule "dekt4pets-dev" "nginx" "dekt4pets-dev.gw.$DOMAIN"  "dekt4pets-gateway" "80" $DEMO_APPS_NS
    create-ingress-rule "dekt4pets" "nginx" "dekt4pets.gw.$DOMAIN"  "dekt4pets-gateway" "80" $DEMO_APPS_NS
    ;;
gui-dev)
    create-ingress-rule "tap-gui-ingress" "contour" "tap-gui.sys.$DOMAIN" "server" "7000" "tap-gui"
    ;;
*)
    echo "incorrect usage. Please use 'tap-full', 'tap-run', 'apis', 'gui-dev' or 'scgw'"
    ;;
esac





        