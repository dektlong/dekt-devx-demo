#!/usr/bin/env bash

source .config/config-values.env

resourceGroup="tap-aks"


#create-aks-cluster
create-aks-cluster() {

	cluster_name=$1
	number_of_nodes="$2"
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
	
	cluster_name=$1

	echo
	echo "Starting deleting resources of AKS cluster $cluster_name ..."
	echo
	az aks delete --name $cluster_name --resource-group $resourceGroup --yes

}
#################### main #######################

case $1 in
create-clusters)
  	#create-aks-cluster $FULL_CLUSTER_NAME 3
	#create-aks-cluster $BUILD_CLUSTER_NAME 2
	create-aks-cluster $RUN_CLUSTER_NAME 1
    ;;
delete-clusters)
    delete-aks-cluster $FULL_CLUSTER_NAME
	delete-aks-cluster $BUILD_CLUSTER_NAME
	delete-aks-cluster $RUN_CLUSTER_NAME
    ;;
*)
	echo "Incorrect usage. Please specific 'create-clusters' or 'delete-clusters'"
	;;
esac
