#!/usr/bin/env bash

source .config/config-values.env



#create-cluster
create-eks-cluster () {

    cluster_name=$1
    number_of_nodes="$2"
    #must run after setting access via 'aws configure'

    eksctl create cluster \
    --name $cluster_name \
    --nodegroup-name standard-workers \
    --node-type t3.medium \
    --nodes $number_of_nodes \
    --nodes-min 2 \
    --nodes-max $number_of_nodes
}

#delete-cluster
delete-eks-cluster () {

    cluster_name=$1

   	echo
	echo "Starting deleting resources of EKS cluster $cluster_name ..."
	echo
    eksctl delete cluster --name $cluster_name --force
}

case $1 in
create-clusters)
  	create-eks-cluster $FULL_CLUSTER_NAME 4
    create-eks-cluster $BUILD_CLUSTER_NAME 2
    create-eks-cluster $RUN_CLUSTER_NAME 2
    ;;
delete-clusters)
    delete-eks-cluster $FULL_CLUSTER_NAME
    delete-eks-cluster $BUILD_CLUSTER_NAME
    delete-eks-cluster $RUN_CLUSTER_NAME
    ;;
*)
	echo "Incorrect usage. Please specific 'create' or 'delete'"
	;;
esac