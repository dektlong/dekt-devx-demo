#!/usr/bin/env bash

#azure configs
AZURE_SUBSCRIPTION_ID=$(yq .clouds.azure.subscriptionID .config/demo-values.yaml)
AZURE_RESOURCE_GROUP=$(yq .clouds.azure.resourceGroup .config/demo-values.yaml)
AZURE_NODE_TYPE=$(yq .clouds.azure.nodeType .config/demo-values.yaml)
#aws configs
AWS_ACCOUNT_ID=$(yq .clouds.aws.accountID .config/demo-values.yaml)
AWS_IAM_USER=$(yq .clouds.aws.IAMuser .config/demo-values.yaml)
AWS_INSTANCE_TYPE=$(yq .clouds.aws.instanceType .config/demo-values.yaml)
#gcp configs
GCP_PROJECT_ID=$(yq .clouds.gcp.projectID .config/demo-values.yaml)
GCP_MACHINE_TYPE=$(yq .clouds.gcp.machineType .config/demo-values.yaml)


#create-aks-cluster
create-aks-cluster() {

	cluster_name=$1
	location=$2
	number_of_nodes=$3

	scripts/dektecho.sh info "Creating AKS cluster $cluster_name in location $location with $number_of_nodes nodes"
		
	#make sure your run 'az login' and use WorkspaceOn SSO prior to running this
	
	az group create --name $AZURE_RESOURCE_GROUP --location $location

	az aks create --name $cluster_name \
		--resource-group $AZURE_RESOURCE_GROUP \
		--node-count $number_of_nodes \
		--node-vm-size $AZURE_NODE_TYPE \
		--generate-ssh-keys
}

#delete-aks-cluster
delete-aks-cluster() {

	cluster_name=$1
	location=$2

	scripts/dektecho.sh status "Starting deleting resources of AKS cluster $cluster_name in location $location"

	az aks delete --name $cluster_name --resource-group $AZURE_RESOURCE_GROUP --yes
}


#create-eks-cluster
create-eks-cluster () {

    #must run after setting access via 'aws configure'

    cluster_name=$1
	region=$2
	number_of_nodes=$3

	scripts/dektecho.sh info "Creating EKS cluster $cluster_name in region $region with $number_of_nodes nodes"

	eksctl create cluster \
		--name $cluster_name \
		--managed \
		--region $region \
		--instance-types $AWS_INSTANCE_TYPE \
		--version 1.24 \
        --with-oidc \
		-N $number_of_nodes

	eksctl create iamserviceaccount \
  		--name ebs-csi-controller-sa \
  		--namespace kube-system \
  		--cluster $cluster_name \
		--region $region \
  		--attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  		--approve \
  		--role-only \
  		--role-name AmazonEKS_EBS_CSI_DriverRole-$cluster_name

	eksctl create addon \
		--name aws-ebs-csi-driver \
		--cluster $cluster_name \
		--region $region \
		--service-account-role-arn arn:aws:iam::$AWS_ACCOUNT_ID:role/AmazonEKS_EBS_CSI_DriverRole-$cluster_name \
		--force
}

#delete-eks-cluster
delete-eks-cluster () {

    cluster_name=$1
	region=$2

	scripts/dektecho.sh status "Starting deleting resources of EKS cluster $cluster_name in region $region..."

	eksctl delete cluster --name $cluster_name --region $region --force
}

#create-gke-cluster
create-gke-cluster () {

	cluster_name=$1
	region=$2
	number_of_nodes=$3

	scripts/dektecho.sh info "Creating GKE cluster $cluster_name in region $region with $number_of_nodes nodes"
	
	gcloud container clusters create $cluster_name \
		--region $region \
		--project $GCP_PROJECT_ID \
		--num-nodes $number_of_nodes \
		--machine-type $GCP_MACHINE_TYPE

	gcloud container clusters get-credentials $cluster_name --region $region --project $GCP_PROJECT_ID 

	gcloud components install gke-gcloud-auth-plugin
}

#delete-eks-cluster
delete-gke-cluster () {

    cluster_name=$1
	region=$2

	scripts/dektecho.sh status "Starting deleting resources of GKE cluster $cluster_name in region $region"
	
	gcloud container clusters delete $cluster_name \
		--region $region \
		--project $GCP_PROJECT_ID \
		--quiet

	kubectl config delete-context $cluster_name

}


#install-krew
install-krew () {
	set -x; cd "$(mktemp -d)" &&
  	OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
  	ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
  	KREW="krew-${OS}_${ARCH}" &&
  	curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
  	tar zxvf "${KREW}.tar.gz" &&
  	./"${KREW}" install krew

	export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

}


#wait-for-all-running-pods
wait-for-all-running-pods () {

		namespace=$1
        status=""
        printf "Waiting for all pods in namespace $namespace to be in 'running' state  ."
        while [ "$status" == "" ]
        do
            printf "."
            status="$(kubectl get pods -n $namespace  -o=json | grep 'running')" 
            sleep 1
        done
        echo
}

#################### main #######################

#incorrect-usage
incorrect-usage() {
	
	scripts/dektecho.sh err "Incorrect usage. Please specify:"
    echo "  create [aks/eks/gke cluster-name region number-of-nodes]"
    echo "  delete [aks/eks/gke cluster-name region]"
	echo "  set-context [aks/eks/gke cluster-name region]"
    exit
}

operation=$1
clusterProvider=$2
clusterName=$3
region=$4
numOfNodes=$5

case $operation in
create)
	case $clusterProvider in
	aks)
  		create-aks-cluster $clusterName $region $numOfNodes
    	;;
	eks)
		create-eks-cluster $clusterName $region $numOfNodes
		;;
	gke)
		create-gke-cluster $clusterName $region $numOfNodes
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
    	;;
	eks)
		kubectl config rename-context $AWS_IAM_USER@$clusterName.$region.eksctl.io $clusterName
		;;
	gke)
		kubectl config rename-context gke_$GCP_PROJECT_ID"_"$region"_"$clusterName $clusterName
		;;
	*)
		incorrect-usage
		;;
	esac
	;;
delete)
	case $clusterProvider in
	aks)
  		delete-aks-cluster $clusterName $region
    	;;
	eks)
		delete-eks-cluster $clusterName $region
		;;
	gke)
		delete-gke-cluster $clusterName $region
		;;
	*)
		incorrect-usage
		;;
	esac
	;;
install-krew)
	install-krew
	;;
*)
	incorrect-usage
	;;
esac