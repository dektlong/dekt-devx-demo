#!/usr/bin/env bash

source .config/config-values.env

#create-cluster
create-eks-cluster () {

    #must run after setting access via 'aws configure'

    eksctl create cluster \
    --name $CLUSTER_NAME \
    --nodegroup-name standard-workers \
    --node-type t3.medium \
    --nodes 8 \
    --nodes-min 4 \
    --nodes-max 8
}

#delete-cluster
delete-eks-cluster () {

    eksctl delete cluster --name $CLUSTER_NAME --force
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