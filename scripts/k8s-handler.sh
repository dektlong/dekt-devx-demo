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

    cluster_name=$1
	number_of_nodes=$2

	scripts/dektecho.sh info "Creating EKS cluster $cluster_name with $number_of_nodes nodes"

    eksctl create cluster \
		--name $cluster_name \
		--region $AWS_REGION \
		--without-nodegroup
	
	#docker to containerd bug workaround
	containerdAMI=$(aws ssm get-parameter --name /aws/service/eks/optimized-ami/1.21/amazon-linux-2/recommended/image_id --region $AWS_REGION --query "Parameter.Value" --output text)
	bootstrap_cmd="/etc/eks/bootstrap.sh $cluster_name --container-runtime containerd"

cat <<EOF | eksctl create nodegroup -f -
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: $cluster_name
  region: $AWS_REGION
managedNodeGroups:
  - name: containerd-ng
    ami: $containerdAMI
    instanceType: $AWS_INSTANCE_TYPE
    desiredCapacity: $number_of_nodes
    overrideBootstrapCommand: $bootstrap_cmd
EOF

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

	gcloud container clusters get-credentials $cluster_name --region $GCP_REGION 
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

#verify cluster
verify () {

	cluster_name=$1

	kubectl config use-context $cluster_name 
	kubectl get pods -A
	kubectl get svc -A
	scripts/dektecho.sh prompt  "Verfiy core components of $cluster_name have been created succefully. Continue?" && [ $? -eq 0 ] || exit
}

#################### main #######################

#incorrect-usage
incorrect-usage() {
	
	scripts/dektecho.sh err "Incorrect usage. Please specify:"
    echo "  create [aks/eks/gke cluster-name numbber-of-nodes]"
    echo "  delete [aks/eks/gke cluster-name]"
	echo "  set-context [aks/eks/gke cluster-name]"
    exit
}

operation=$1
clusterProvider=$2
clusterName=$3
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
set-context)
	case $clusterProvider in
	aks)
  		az aks get-credentials --overwrite-existing --resource-group $AZURE_RESOURCE_GROUP --name $clusterName
		verify $clusterName
    	;;
	eks)
		kubectl config rename-context $AWS_IAM_USER@$clusterName.$AWS_REGION.eksctl.io $clusterName
		verify $clusterName
		;;
	gke)
		kubectl config rename-context gke_$GCP_PROJECT_ID"_"$GCP_REGION"_"$clusterName $clusterName
		verify $clusterName
		;;
	*)
		incorrect-usage
		;;
	esac
	;;	
*)
	incorrect-usage
	;;
esac