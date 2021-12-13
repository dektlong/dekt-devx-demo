#!/usr/bin/env bash

source .config/config-values.env

product=$1
serviceName=$2
servicePort=$3
namespace=$4
host=$APPS_SUB_DOMAIN.$DOMAIN

case $K8S_DIALTONE in
  aks)
    ingress_class="addon-http-application-routing"
    ;;
  eks)
	  ingress_class="nginx" 
    ;;      
  tkg)
	  ingress_class="contour" 
    ;;
esac


cat > output.yaml <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress 
metadata: 
  name: $product-ingress
  annotations: 
    kubernetes.io/ingress.class: $ingress_class
spec: 
  rules: 
    - host: $product.$host
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
