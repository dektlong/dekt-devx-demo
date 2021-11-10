#!/usr/bin/env bash

#################### functions #######################

#create cluster
create-cluster() {
	
	clusterName=$1
	
	numberOfNodes=$2
	
	nodeSize="Standard_DS3_v2" # 4 vCPU, 14GB memory, 28GB temp disk
	
	echo
	echo "==========> Creating AKS cluster named $clusterName with $numberOfNodes nodes of size $nodeSize ..."
	echo
	
	az login -u $AZURE_USER -p $AZURE_PASSWORD --allow-no-subscriptions
	
	az group create --name $RESOURCE_GROUP --location westus

	az aks create --resource-group $RESOURCE_GROUP --name $clusterName --node-count $numberOfNodes --node-vm-size $nodeSize --generate-ssh-keys

	az aks get-credentials --overwrite-existing --resource-group $RESOURCE_GROUP --name $1
}

delete-cluster() {
	
	clusterName=$1

	az login -u $AZURE_USER -p $AZURE_PASSWORD

	echo
	echo "==========> Starting deletion of AKS cluster named $clusterName"
	echo

	az aks delete --name $clusterName --resource-group $RESOURCE_GROUP --yes --no-wait

}

#incorrect usage
incorrect-usage() {
	
	echo "Incorrect usage. Required: create {cluster-name,number-of-worker-nodes} | delete {cluster-name}"
	exit
}


#################### main #######################

source .config/config-values.env

case $1 in 
create)
	create-cluster $2 $3
	scripts/install-nginx.sh
	scripts/update-dns.sh "auto" "dekt-ingress-nginx-controller" "nginx-system" "*.$APPS_SUB_DOMAIN"
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


