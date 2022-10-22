#!/usr/bin/env bash

#azure configs
AZURE_LOCATION=$(yq .clouds.azureLocation .config/demo-values.yaml)
AZURE_RESOURCE_GROUP=$(yq .clouds.azureResourceGroup .config/demo-values.yaml)
AZURE_NODE_TYPE=$(yq .clouds.azureNodeType .config/demo-values.yaml)
#aws configs
AWS_IAM_USER=$(yq .clouds.awsIAMuser .config/demo-values.yaml)
AWS_REGION=$(yq .clouds.awsRegion .config/demo-values.yaml)
AWS_INSTANCE_TYPE=$(yq .clouds.awsInstanceType .config/demo-values.yaml)
#gcp configs
GCP_REGION=$(yq .clouds.gcpRegion .config/demo-values.yaml)
GCP_PROJECT_ID=$(yq .clouds.gcpProjectID .config/demo-values.yaml)
GCP_MACHINE_TYPE=$(yq .clouds.gcpMachineType .config/demo-values.yaml)


#create-aks-cluster
create-aks-cluster() {

	cluster_name=$1
	number_of_nodes=$2

	scripts/dektecho.sh info "Creating AKS cluster named $cluster_name with $number_of_nodes nodes"
		
	#make sure your run 'az login' and use WorkspaceOn SSO prior to running this
	
	az group create --name $AZURE_RESOURCE_GROUP --location $AZURE_LOCATION

	az aks create --name $cluster_name \
		--resource-group $AZURE_RESOURCE_GROUP \
		--node-count $number_of_nodes \
		--node-vm-size $AZURE_NODE_TYPE \
		--generate-ssh-keys

	az aks get-credentials --overwrite-existing --resource-group $AZURE_RESOURCE_GROUP --name $cluster_name

}

#delete-aks-cluster
delete-aks-cluster() {

	cluster_name=$1

	scripts/dektecho.sh status "Starting deleting resources of AKS cluster $cluster_name"

	kubectl config delete-context $clusterName
	
	az aks delete --name $cluster_name --resource-group $AZURE_RESOURCE_GROUP --yes
}


#create-eks-cluster
create-eks-cluster () {

    #must run after setting access via 'aws configure'

    cluster_name=$1
	number_of_nodes=$2

	scripts/dektecho.sh info "Creating EKS cluster $cluster_name with $number_of_nodes nodes"

    eksctl create cluster \
		--name $cluster_name \
		--managed \
		--region $AWS_REGION \
		--version 1.23 \
		--with-oidc \
		--nodes $number_of_nodes \
		--node-type $AWS_INSTANCE_TYPE 

	kubectl config rename-context $AWS_IAM_USER@$cluster_name.$AWS_REGION.eksctl.io $cluster_name
}

#delete-eks-cluster
delete-eks-cluster () {

    cluster_name=$1

	scripts/dektecho.sh status "Starting deleting resources of EKS cluster $cluster_name ..."
	
    kubectl config delete-context $clusterName

	eksctl delete cluster --name $cluster_name --force
}

#create-gke-cluster
create-gke-cluster () {

	cluster_name=$1
	number_of_nodes=$2

	scripts/dektecho.sh info "Creating GKE cluster $cluster_name with $number_of_nodes nodes"
	
	gcloud container clusters create $cluster_name \
		--region $GCP_REGION \
		--project $GCP_PROJECT_ID \
		--num-nodes $number_of_nodes \
		--machine-type $GCP_MACHINE_TYPE

	gcloud container clusters get-credentials $cluster_name --region $GCP_REGION 

	kubectl config rename-context gke_$GCP_PROJECT_ID"_"$GCP_REGION"_"$cluster_name $cluster_name

}

#delete-eks-cluster
delete-gke-cluster () {

    cluster_name=$1

	scripts/dektecho.sh status "Starting deleting resources of GKE cluster $cluster_name"
	
    kubectl config delete-context $clusterName

	gcloud container clusters delete $cluster_name \
		--region $GCP_REGION \
		--project $GCP_PROJECT_ID \
		--quiet

}

#################### main #######################

#incorrect-usage
incorrect-usage() {
	
	scripts/dektecho.sh err "Incorrect usage. Please specify:"
    echo "  create [aks/eks/gke cluster-name numbber-of-nodes]"
    echo "  delete [aks/eks/gke cluster-name]"
	echo "  verify [aks/eks/gke cluster-name]"
    exit
}

operation=$1
clusterName=$2
clusterProvider=$3
numOfNodes=$4
case $operation in
create)
	case $clusterProvider in
	aks)
  		create-aks-cluster $clusterName $numOfNodes
    	;;
	eks)
		create-eks-cluster $clusterName $numOfNodes
		;;
	gke)
		create-gke-cluster $clusterName $numOfNodes
		;;
	*)
		incorrect-usage
		;;
	esac
	;;
delete)
	case $clusterProvider in
	aks)
  		delete-aks-cluster $clusterName
    	;;
	eks)
		delete-eks-cluster $clusterName
		;;
	gke)
		delete-gke-cluster $clusterName
		;;
	*)
		incorrect-usage
		;;
	esac
	;;	
verify)
	scripts/dektecho.sh status "Core components of $clusterName cluster"
	kubectl config use-context $clusterName 
	kubectl get pods -A
	kubectl get svc -A
	;;
*)
	incorrect-usage
	;;
esac