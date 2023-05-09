#!/usr/bin/env bash

DOMAIN=$(yq .dns.domain .config/demo-values.yaml)
GODADDY_API_KEY=$(yq .dns.godaddyApiKey .config/demo-values.yaml)
GODADDY_API_SECRET=$(yq .dns.godaddyApiSecret .config/demo-values.yaml)
IS_ROUTE53=$(yq .dns.isRoute53 .config/demo-values.yaml)
AWS_ZONE_ID=$(yq .dns.awsRoute53HostedZoneID .config/demo-values.yaml)

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

update-dns-record()
{

    ingress_service_name=$1
    ingress_namespace=$2
    

    if [ "$cloudProvider" == "eks" ]
    then
        record_data=$(kubectl get svc $ingress_service_name --namespace $ingress_namespace -o=jsonpath='{.status.loadBalancer.ingress[0].hostname}')
        scripts/dektecho.sh status "updating this CNAME record in GoDaddy:  *.$subDomain.$DOMAIN --> $record_data"
        curl -s -X PUT \
        -H "Authorization: sso-key $GODADDY_API_KEY:$GODADDY_API_SECRET" "https://api.godaddy.com/v1/domains/$DOMAIN/records/CNAME/*.$subDomain" \
        -H "Content-Type: application/json" \
        -d "[{\"data\": \"${record_data}\"}]"
    else
        record_data=$(kubectl get svc $ingress_service_name --namespace $ingress_namespace -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')
        scripts/dektecho.sh status "updating this A record in GoDaddy:  *.$subDomain.$DOMAIN --> $record_data"
        curl -s -X PUT \
        -H "Authorization: sso-key $GODADDY_API_KEY:$GODADDY_API_SECRET" "https://api.godaddy.com/v1/domains/$DOMAIN/records/A/*.$subDomain" \
        -H "Content-Type: application/json" \
        -d "[{\"data\": \"${record_data}\"}]"
    fi
    
}

update-dns-record-route53()
{

    ingress_service_name=$1
    ingress_namespace=$2
    

    if [ "$cloudProvider" == "eks" ]
    then
        record_data=$(kubectl get svc $ingress_service_name --namespace $ingress_namespace -o=jsonpath='{.status.loadBalancer.ingress[0].hostname}')
        scripts/dektecho.sh status "updating this CNAME record in Route53:  *.$subDomain.$DOMAIN --> $record_data"
        cat > /tmp/route53upsert.tmp <<EOF
{
    "Comment": "CREATE/DELETE/UPSERT a record ",
    "Changes": [{
    "Action": "UPSERT",
                "ResourceRecordSet": {
                            "Name": "*.$subDomain.$DOMAIN",
                            "Type": "CNAME",
                            "TTL": 300,
                          "ResourceRecords": [{ "Value": "$record_data"}]
}}]
}
EOF
        aws route53 change-resource-record-sets --hosted-zone-id $AWS_ZONE_ID --change-batch file:///tmp/route53upsert.tmp
    
    fi    
}

subDomain=$2
cloudProvider=$3

case $1 in
update-tap-dns)
    if [ $IS_ROUTE53 = "true" ]; then
      update-dns-record-route53  "envoy" "tanzu-system-ingress"
    else
      update-dns-record "envoy" "tanzu-system-ingress"
    fi
    ;;
add-brownfield-apis)
    create-ingress-rule "api-portal-ingress" "contour" "api-portal.$subDomain.$DOMAIN" "api-portal-server" "8080" "api-portal"
    create-ingress-rule "scg-openapi-ingress" "contour" "scg-openapi.$subDomain.$DOMAIN"  "scg-operator" "80" "scgw-system"
    ;;
add-scgw-ingress)
    scripts/install-nginx.sh
    update-dns-record "dekt-ingress-nginx-controller" "nginx-system" 
    create-ingress-rule "dekt4pets-dev" "nginx" "dekt4pets-dev.$subDomain.$DOMAIN"  "dekt4pets-gateway" "80" $DEMO_APPS_NS
    create-ingress-rule "dekt4pets" "nginx" "dekt4pets.$subDomain.$DOMAIN"  "dekt4pets-gateway" "80" $DEMO_APPS_NS
    ;;
gui-dev)
    create-ingress-rule "tap-gui-ingress" "contour" "tap-gui.$subDomain.$DOMAIN" "server" "7000" "tap-gui"
    ;;
acc)
    create-ingress-rule "acc-ingress" "contour" "acc.sys.dekt.io" "acc-server" "80" "accelerator-system"
    ;;
*)
    scripts/dektecho.sh err "incorrect usage. Please use 'tap-full', 'tap-run', 'apis', 'gui-dev' or 'scgw'"
    ;;
esac





        