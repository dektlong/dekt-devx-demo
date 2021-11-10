#!/usr/bin/env bash



#create-cluster
create-cluster () {

    #must run after setting access via 'aws configure'

    clusterName=$1

    eksctl create cluster \
    --name $clusterName \
    --nodegroup-name standard-workers \
    --node-type t3.medium \
    --nodes 8 \
    --nodes-min 4 \
    --nodes-max 8
}

#delete-cluster
delete-cluster () {

    clusterName=$1

    eksctl delete cluster --name $clusterName --force
}

case $1 in 
create)
	create-cluster $2
	scripts/install-nginx.sh
    scripts/update-dns.sh "manual" "dekt-ingress-nginx-controller" "nginx-system" "*.$APPS_SUB_DOMAIN"
	scripts/start-app.sh "octant"
	;;
delete)
	delete-cluster $2
	scripts/stop-app.sh "octant"
  	;;
*)
  	incorrect-usage
  	;;
esac