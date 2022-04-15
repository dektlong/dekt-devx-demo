#!/usr/bin/env bash

source .config/config-values.env

CLUSTER_NAME=$2
NUMBER_OF_NODES="$3"
RESOURCE_GROUP="tap-aks"

TANZU_NETWORK_USER=$(yq .buildservice.tanzunet_username .config/tap-values-full.yaml)
TANZU_NETWORK_PASSWORD=$(yq .buildservice.tanzunet_password .config/tap-values-full.yaml)

#create-aks-cluster
create-aks-cluster() {

	if [ -z "$CLUSTER_NAME" ] | [ -z "$NUMBER_OF_NODES" ]; then
    	incorrect-usage
	fi
	
	echo
	echo "==========> Creating AKS cluster named $CLUSTER_NAME with $NUMBER_OF_NODES nodes ..."
	echo
	
	#make sure your run 'az login' and use WorkspaceOn SSO prior to running this
	
	az group create --name $RESOURCE_GROUP --location westus

	az aks create --name $CLUSTER_NAME \
		--resource-group $RESOURCE_GROUP \
		--node-count $NUMBER_OF_NODES \
		--node-vm-size "Standard_DS3_v2" # 4 vCPU, 14GB memory, 28GB temp disk 
	#	--generate-ssh-keys 
	#	--enable-addons http_application_routing 

	az aks get-credentials --overwrite-existing --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME

}

#add-carvel-tools
add-carvel-tools () {

	export INSTALL_BUNDLE=registry.tanzu.vmware.com/tanzu-cluster-essentials/cluster-essentials-bundle@sha256:ab0a3539da241a6ea59c75c0743e9058511d7c56312ea3906178ec0f3491f51d
    export INSTALL_REGISTRY_HOSTNAME=registry.tanzu.vmware.com
    export INSTALL_REGISTRY_USERNAME=$TANZU_NETWORK_USER
    export INSTALL_REGISTRY_PASSWORD=$TANZU_NETWORK_PASSWORD
    pushd scripts/carvel
        ./install.sh --yes
	pushd
}

#delete-aks-cluster
delete-aks-cluster() {
	
	if [ -z "$CLUSTER_NAME" ] ; then
    	incorrect-usage
	fi
	echo
	echo "Starting deleting resources of AKS cluster $CLUSTER_NAME ..."
	echo
	az aks delete --name $CLUSTER_NAME --resource-group $RESOURCE_GROUP --yes

	kubectl config delete-context $CLUSTER_NAME

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
  	create-aks-cluster
    add-carvel-tools
    ;;
delete)
    delete-aks-cluster
    ;;
*)
	incorrect-usage
	;;
esac