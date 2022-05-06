#!/usr/bin/env bash


REGION="us-west-1" #aws ec2 describe-regions --output table
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
    scripts/tanzu-handler.sh add-carvel-tools
    ;;
delete)
    delete-eks-cluster $2
    ;;
*)
	incorrect-usage
	;;
esac