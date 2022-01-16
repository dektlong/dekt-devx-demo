#!/usr/bin/env bash

source .config/config-values.env

#create-aks-cluster
create-aks-cluster() {

	resourceGroup="tap-aks"
	
	numberOfNodes=7
	
	nodeSize="Standard_DS3_v2" # 4 vCPU, 14GB memory, 28GB temp disk

	echo
	echo "==========> Creating AKS cluster named $CLUSTER_NAME with $numberOfNodes nodes of size $nodeSize ..."
	echo
	
	#make sure your run 'azure login' and use WorkspaceOn SSO prior to running this
	
	az group create --name $resourceGroup --location westus

	az aks create --name $CLUSTER_NAME \
		--resource-group $resourceGroup \
		--node-count $numberOfNodes \
		--node-vm-size $nodeSize \
		--generate-ssh-keys \
		--enable-addons http_application_routing 

	az aks get-credentials --overwrite-existing --resource-group $resourceGroup --name $1
}

delete-aks-cluster() {
	
	az aks delete --name $CLUSTER_NAME --resource-group $resourceGroup --yes --no-wait

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
