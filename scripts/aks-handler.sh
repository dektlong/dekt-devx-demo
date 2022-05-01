#!/usr/bin/env bash

RESOURCE_GROUP="tap-aks"
LOCATION="westus"
TANZU_NETWORK_USER=$(yq .buildservice.tanzunet_username .config/tap-values-full.yaml)
TANZU_NETWORK_PASSWORD=$(yq .buildservice.tanzunet_password .config/tap-values-full.yaml)

#create-aks-cluster
create-aks-cluster() {

	cluster_name=$1
	number_of_nodes=$2

	if [ -z "$cluster_name" ] | [ -z "$number_of_nodes" ]; then
    	incorrect-usage
	fi

	
	echo
	echo "==========> Creating AKS cluster named $cluster_name with $number_of_nodes nodes ..."
	echo
	
	#make sure your run 'az login' and use WorkspaceOn SSO prior to running this
	
	az group create --name $RESOURCE_GROUP --location $LOCATION

	az aks create --name $cluster_name \
		--resource-group $RESOURCE_GROUP \
		--kubernetes-version "1.22.6" \
		--node-count $number_of_nodes \
		--node-vm-size "Standard_DS3_v2" # 4 vCPU, 14GB memory, 28GB temp disk 

	az aks get-credentials --overwrite-existing --resource-group $RESOURCE_GROUP --name $cluster_name

}

#delete-aks-cluster
delete-aks-cluster() {

	cluster_name=$1

	if [ -z "$cluster_name" ]; then
    	incorrect-usage
	fi
	
	echo
	echo "Starting deleting resources of AKS cluster $cluster_name ..."
	echo
	az aks delete --name $cluster_name --resource-group $RESOURCE_GROUP --yes

	kubectl config delete-context $cluster_name
}
#################### main #######################

#incorrect-usage
incorrect-usage() {
    echo "Incorrect usage. Please specify:"
    echo "  create [cluster-name number-of-nodes]"
    echo "  delete [cluster-name]"
    exit
}

case $1 in
create)
  	create-aks-cluster $2 $3
    scripts/install-carvel.sh
    ;;
delete)
    delete-aks-cluster $2
    ;;
*)
	incorrect-usage
	;;
esac