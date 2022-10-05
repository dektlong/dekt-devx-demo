#!/usr/bin/env bash

#azure configs
AZURE_LOCATION=$(yq .clouds.azureLocation .config/demo-values.yaml)
AZURE_RESOURCE_GROUP=$(yq .clouds.azureResourceGroup .config/demo-values.yaml)
AZURE_NODE_TYPE=$(yq .clouds.azureNodeType .config/demo-values.yaml)
#aws configs
AWS_REGION=$(yq .clouds.awsRegion .config/demo-values.yaml)
AWS_INSTANCE_TYPE=$(yq .clouds.awsRegion .config/demo-values.yaml)
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
		--node-vm-size $AZURE_NODE_TYPE 

	az aks get-credentials --overwrite-existing --resource-group $AZURE_RESOURCE_GROUP --name $cluster_name

}

#delete-aks-cluster
delete-aks-cluster() {

	cluster_name=$1

	scripts/dektecho.sh status "Starting deleting resources of AKS cluster $cluster_name"
	
	az aks delete --name $cluster_name --resource-group $AZURE_RESOURCE_GROUP --yes
}


#create-eks-cluster
create-eks-cluster () {

    #must run after setting access via 'aws configure'

    export cluster_name=$1
	export aws_region=$AWS_REGION
	export aws_instance_type=$AWS_INSTANCE_TYPE
	number_of_nodes=$2
	export bootstrap_cmd="/etc/eks/bootstrap.sh $cluster_name --container-runtime containerd"

	scripts/dektecho.sh info "Creating EKS cluster $cluster_name with $number_of_nodes nodes"

    eksctl create cluster \
		--name $cluster_name \
		--region $AWS_REGION \
		--without-nodegroup #containerd to docker bug
	
	#containerd to docker bug
	yq '.metadata.name = env(cluster_name)' .config/rbac//containerd-ng.yaml -i
	yq '.metadata.region = env(aws_region)' .config/rbac/containerd-ng.yaml -i
	yq '.managedNodeGroups.instanceType = env(aws_instance_type)' .config/rbac/containerd-ng.yaml -i
	yq '.managedNodeGroups[0].overrideBootstrapCommand = env(bootstrap_cmd)' scripts/containerd-ng.yaml -i
	
    eksctl create ng -f scripts/containerd-ng.yaml
    eksctl scale nodegroup \
		--cluster=$cluster_name \
		--nodes=$number_of_nodes \
		--name=containerd-ng \
		--nodes-min=$number_of_nodes \
		--nodes-max=$number_of_nodes
	
	kubectl config rename-context $(kubectl config current-context) $cluster_name


}

#scale-aks-nodes
scale-aks-nodes () {

    cluster_name=$1
	number_of_nodes=$2

	az aks nodepool scale --name nodepool1 --cluster-name $cluster_name --resource-group $AZURE_RESOURCE_GROUP  --node-count 0 #$number_of_nodes

}

#delete-eks-cluster
delete-eks-cluster () {

    cluster_name=$1

	scripts/dektecho.sh status "Starting deleting resources of EKS cluster $cluster_name ..."
	
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

	gcloud container clusters get-credentials $cluster_name --region $GCP_REGION --project $GCP_PROJECT_ID

	kubectl config rename-context $(kubectl config current-context) $cluster_name

}

#delete-eks-cluster
delete-gke-cluster () {

    cluster_name=$1

	scripts/dektecho.sh status "Starting deleting resources of GKE cluster $cluster_name"
	
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
    echo "  scale-nodes [aks/eks/gke cluster-name numbber-of-nodes]"
	echo "  delete [aks/eks/gke cluster-name]"
    exit
}

case $1 in
create)
	case $2 in
	aks)
  		create-aks-cluster $3 $4
    	;;
	eks)
		create-eks-cluster $3 $4
		;;
	gke)
		create-gke-cluster $3 $4
		;;
	*)
		incorrect-usage
		;;
	esac
	;;
scale-nodes)
    case $2 in
	aks)
  		scale-aks-nodes $3 $4
    	;;
	eks)
		scale-eks-nodes $3 $4
		;;
	gke)
		scale-gke-nodes $3 $4
		;;
	*)
		incorrect-usage
		;;
	esac
	;;
delete)
    case $2 in
	aks)
  		delete-aks-cluster $3
    	;;
	eks)
		delete-eks-cluster $3
		;;
	gke)
		delete-gke-cluster $3
		;;
	*)
		incorrect-usage
		;;
	esac
	;;	
test-cluster)
	ctx $2 && kubectl get pods -A && kubectl get svc -A
	;;
*)
	incorrect-usage
	;;
esac