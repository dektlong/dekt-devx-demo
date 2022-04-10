#!/usr/bin/env bash

source .config/config-values.env

cluster_name=$2
number_of_nodes="$3"

resourceGroup="tap-aks"


#create-aks-cluster
create-aks-cluster() {

	nodeSize="Standard_DS3_v2" # 4 vCPU, 14GB memory, 28GB temp disk

	echo
	echo "==========> Creating AKS cluster named $cluster_name with $number_of_nodes nodes of size $nodeSize ..."
	echo
	
	#make sure your run 'az login' and use WorkspaceOn SSO prior to running this
	
	az group create --name $resourceGroup --location westus

	az aks create --name $cluster_name \
		--resource-group $resourceGroup \
		--node-count $number_of_nodes \
		--node-vm-size $nodeSize \
		--generate-ssh-keys 
	#	--enable-addons http_application_routing 

	az aks get-credentials --overwrite-existing --resource-group $resourceGroup --name $cluster_name
}

delete-aks-cluster() {
	
	echo
	echo "Starting deleting resources of AKS cluster $cluster_name ..."
	echo
	az aks delete --name $cluster_name --resource-group $resourceGroup --yes

}
#################### main #######################

case $1 in
create)
  	create-aks-cluster 
    ;;
delete)
    delete-aks-cluster
    ;;
*)
	echo "Incorrect usage. Please specific 'create' or 'delete'"
	;;
esac
