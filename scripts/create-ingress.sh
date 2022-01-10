#!/usr/bin/env bash

source .config/config-values.env

ingressName=$1
ingressHost=$2
ingressClass=$3
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
