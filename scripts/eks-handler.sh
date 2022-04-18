#!/usr/bin/env bash

source .config/config-values.env

REGION="eu-west-2" #aws ec2 describe-regions --output table

CLUSTER_NAME=$2
NUMBER_OF_NODES="$3"
TANZU_NETWORK_USER=$(yq .buildservice.tanzunet_username .config/tap-values-full.yaml)
TANZU_NETWORK_PASSWORD=$(yq .buildservice.tanzunet_password .config/tap-values-full.yaml)

#create-cluster
create-eks-cluster () {

    if [ -z "$CLUSTER_NAME" ] | [ -z "$NUMBER_OF_NODES" ]; then
        incorrect-usage
    fi
    #must run after setting access via 'aws configure'

    echo
	echo "Creating EKS cluster $CLUSTER_NAME with $NUMBER_OF_NODES nodes ..."
	echo

    eksctl create cluster \
    --name $CLUSTER_NAME \
    --nodegroup-name workers-$CLUSTER_NAME \
    --version "1.21" \
    --region $REGION \
    --nodes $NUMBER_OF_NODES \
    --node-type t3.xlarge # 4 vCPU , 16GB memory, 80GB temp disk 

    kubectl config rename-context $(kubectl config current-context) $CLUSTER_NAME
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
#delete-cluster
delete-eks-cluster () {

   	if [ -z "$CLUSTER_NAME" ] ; then
        incorrect-usage
    fi
       
    echo
	echo "Starting deleting resources of EKS cluster $CLUSTER_NAME ..."
	echo
    eksctl delete cluster --name $CLUSTER_NAME --force
}

#incorrect-usage
incorrect-usage() {
    echo "Incorrect usage. Please specify:"
    echo "  create [cluster-name number-of-nodes]"
    echo "  delete [cluster-name]"
    exit
}


case $1 in
create)
  	create-eks-cluster
    add-carvel-tools
    ;;
delete)
    delete-eks-cluster
    ;;
*)
	incorrect-usage
	;;
esac