#!/usr/bin/env bash

DOMAIN=$(yq .dns.domain .config/demo-values.yaml)
GODADDY_API_KEY=$(yq .dns.godaddyApiKey .config/demo-values.yaml)
GODADDY_API_SECRET=$(yq .dns.godaddyApiSecret .config/demo-values.yaml)

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
    elif [[ "$ingressType" == *"ip"* ]]; then
        ingress_public_ip=$(kubectl get svc $ingress_service_name --namespace $ingress_namespace -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')
    fi
        
    echo
    echo "updating this A record in GoDaddy:  $record_name.$DOMAIN--> $ingress_public_ip..."

    # Update/Create DNS A Record

    curl -s -X PUT \
        -H "Authorization: sso-key $GODADDY_API_KEY:$GODADDY_API_SECRET" "https://api.godaddy.com/v1/domains/$DOMAIN/records/A/$record_name" \
        -H "Content-Type: application/json" \
        -d "[{\"data\": \"${ingress_public_ip}\"}]"
}

subDomain=$2

case $1 in
update-tap-dns)
    update-dns-A-record "*.$subDomain" "envoy" "tanzu-system-ingress"
    ;;
apis)
    create-ingress-rule "api-portal-ingress" "contour" "api-portal.$subDomain.$DOMAIN" "api-portal-server" "8080" "api-portal"
    create-ingress-rule "scg-openapi-ingress" "contour" "scg-openapi.$subDomain.$DOMAIN"  "scg-operator" "80" "scgw-system"
    ;;
scgw)
    scripts/install-nginx.sh
    update-dns-A-record "*.$subDomain" "dekt-ingress-nginx-controller" "nginx-system" 
    create-ingress-rule "dekt4pets-dev" "nginx" "dekt4pets-dev.$subDomain.$DOMAIN"  "dekt4pets-gateway" "80" $DEMO_APPS_NS
    create-ingress-rule "dekt4pets" "nginx" "dekt4pets.$subDomain.$DOMAIN"  "dekt4pets-gateway" "80" $DEMO_APPS_NS
    ;;
gui-dev)
    create-ingress-rule "tap-gui-ingress" "contour" "tap-gui.$subDomain.$DOMAIN" "server" "7000" "tap-gui"
    ;;
*)
    echo "incorrect usage. Please use 'tap-full', 'tap-run', 'apis', 'gui-dev' or 'scgw'"
    ;;
esac





        