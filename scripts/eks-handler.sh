#!/usr/bin/env bash

source .config/config-values.env


REGION="us-west-1" #aws ec2 describe-regions --output table
CLUSTER_FULL_NAME=$2-eks
NUMBER_OF_NODES=$3
TANZU_NETWORK_USER=$(yq .buildservice.tanzunet_username .config/tap-values-full.yaml)
TANZU_NETWORK_PASSWORD=$(yq .buildservice.tanzunet_password .config/tap-values-full.yaml)

#create-cluster
create-eks-cluster () {

    #must run after setting access via 'aws configure'

    cluster_name=$1
	number_of_nodes=$2

	if [ -z "$cluster_name" ] | [ -z "$number_of_nodes" ]; then
    	incorrect-usage
	fi

    echo
	echo "Creating EKS cluster $cluster_name with $number_of_nodes nodes ..."
	echo

    eksctl create cluster \
    --name $cluster_name \
    --nodegroup-name workers-$cluster_name \
    --version "1.21" \
    --region $REGION \
    --nodes $number_of_nodes \
    --node-type t3.xlarge # 4 vCPU , 16GB memory, 80GB temp disk 

    kubectl config rename-context $(kubectl config current-context) $cluster_name
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

    cluster_name=$1

	if [ -z "$cluster_name" ]; then
    	incorrect-usage
	fi

    echo
	echo "Starting deleting resources of EKS cluster $cluster_name ..."
	echo
    eksctl delete cluster --name $cluster_name --force

    kubectl config delete-context $cluster_name
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
  	create-eks-cluster $2 $3
    add-carvel-tools
    ;;
delete)
    delete-eks-cluster $2
    ;;
*)
	incorrect-usage
	;;
esac