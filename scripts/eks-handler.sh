#!/usr/bin/env bash

source .config/config-values.env

cluster_name=$2
number_of_nodes="$3"

#create-cluster
create-eks-cluster () {

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

   	echo
	echo "Starting deleting resources of EKS cluster $cluster_name ..."
	echo
    eksctl delete cluster --name $cluster_name --force
}

case $1 in
create)
  	create-eks-cluster
    ;;
delete)
    delete-eks-cluster
    ;;
*)
	echo "Incorrect usage. Please specific 'create' or 'delete'"
	;;
esac