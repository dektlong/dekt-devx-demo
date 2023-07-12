#!/usr/bin/env bash

#azure configs
AZURE_LOCATION=$(yq .clouds.azure.location .config/demo-values.yaml)
AZURE_SUBSCRIPTION_ID=$(yq .clouds.azure.subscriptionID .config/demo-values.yaml)
AZURE_RESOURCE_GROUP=$(yq .clouds.azure.resourceGroup .config/demo-values.yaml)
AZURE_NODE_TYPE=$(yq .clouds.azure.nodeType .config/demo-values.yaml)
#aws configs
AWS_ACCOUNT_ID=$(yq .clouds.aws.accountID .config/demo-values.yaml)
AWS_IAM_USER=$(yq .clouds.aws.IAMuser .config/demo-values.yaml)
AWS_REGION=$(yq .clouds.aws.region .config/demo-values.yaml)
AWS_INSTANCE_TYPE=$(yq .clouds.aws.instanceType .config/demo-values.yaml)
#gcp configs
GCP_REGION=$(yq .clouds.gcp.region .config/demo-values.yaml)
GCP_PROJECT_ID=$(yq .clouds.gcp.projectID .config/demo-values.yaml)
GCP_MACHINE_TYPE=$(yq .clouds.gcp.machineType .config/demo-values.yaml)


#create-aks-cluster
create-aks-cluster() {

	cluster_name=$1
	number_of_nodes=$2

	scripts/dektecho.sh info "Creating AKS cluster $cluster_name with $number_of_nodes nodes"
		
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
		--managed \
		--region $AWS_REGION \
		--instance-types $AWS_INSTANCE_TYPE \
		--version 1.24 \
        --with-oidc \
		-N $number_of_nodes

	eksctl create iamserviceaccount \
  		--name ebs-csi-controller-sa \
  		--namespace kube-system \
  		--cluster $cluster_name \
  		--attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  		--approve \
  		--role-only \
  		--role-name AmazonEKS_EBS_CSI_DriverRole-$cluster_name

	eksctl create addon \
		--name aws-ebs-csi-driver \
		--cluster $cluster_name \
		--service-account-role-arn arn:aws:iam::$AWS_ACCOUNT_ID:role/AmazonEKS_EBS_CSI_DriverRole-$cluster_name \
		--force
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

	gcloud components install gke-gcloud-auth-plugin
}

#delete-eks-cluster
delete-gke-cluster () {

    cluster_name=$1

	scripts/dektecho.sh status "Starting deleting resources of GKE cluster $cluster_name"
	
	gcloud container clusters delete $cluster_name \
		--region $GCP_REGION \
		--project $GCP_PROJECT_ID \
		--quiet

	kubectl config delete-context $cluster_name

}

#setup-rds-crossplane
setup-rds-crossplane () {

        scripts/dektecho.sh status "Installing crossplane provider for AWS and configure RDS Postgres access"
        
        kubectl apply -f .config/crossplane/aws/aws-provider.yaml
        	kubectl wait "providers.pkg.crossplane.io/provider-aws" --for=condition=Healthy --timeout=3m
		
		awsProfile=default && echo -e "[default]\naws_access_key_id = $(aws configure get aws_access_key_id --profile $awsProfile)\naws_secret_access_key = $(aws configure get aws_secret_access_key --profile $awsProfile)\naws_session_token = $(aws configure get aws_session_token --profile $awsProfile)" > .config/creds-aws.conf
    	kubectl create secret generic aws-provider-creds -n crossplane-system --from-file=creds=.config/creds-aws.conf
    	rm -f .config/creds-aws.conf

		kubectl apply -f .config/crossplane/aws/aws-provider-config.yaml
		kubectl apply -f .config/crossplane/aws/rds-postgres-xrd.yaml
		kubectl apply -f .config/crossplane/aws/rds-postgres-composition.yaml
		kubectl apply -f .config/crossplane/aws/rds-postgres-class.yaml
		kubectl apply -f .config/crossplane/aws/rds-postgres-rbac.yaml

   
}

#setup-azuresql-crossplane
setup-azuresql-crossplane () {

	scripts/dektecho.sh status "Installing crossplane provider for Azure and configure AzureSQL Postgres access"

	kubectl apply -f .config/crossplane/azure/azure-provider.yaml
		kubectl -n crossplane-system wait provider/provider-jet-azure --for=condition=Healthy=True --timeout=3m
	
	azureSpName='sql-crossplane-demo'
	kubectl create secret generic jet-azure-creds -o yaml --dry-run=client --from-literal=creds="$(
	az ad sp create-for-rbac -n "${azureSpName}" \
	--sdk-auth \
	--role "Contributor" \
	--scopes "/subscriptions/${AZURE_SUBSCRIPTION_ID}" \
	-o json
	)" | kubectl apply -n crossplane-system -f -

	kubectl apply -f .config/crossplane/azure/azure-provider-config.yaml

	serviceAccount=$(kubectl -n crossplane-system get sa -o name | grep provider-kubernetes | sed -e 's|serviceaccount\/|crossplane-system:|g')
	kubectl create role -n crossplane-system password-manager --resource=passwords.secretgen.k14s.io --verb=create,get,update,delete
	kubectl create rolebinding -n crossplane-system provider-kubernetes-password-manager --role password-manager --serviceaccount="${serviceAccount}"

kubectl apply -f - <<'EOF'
apiVersion: kubernetes.crossplane.io/v1alpha1
kind: ProviderConfig
metadata:
  name: default
spec:
  credentials:
    source: InjectedIdentity
EOF
	
	kubectl apply -f .config/crossplane/azure/azuresql-postgres-xrd.yaml
	kubectl apply -f .config/crossplane/azure/azuresql-postgres-composition.yaml
	kubectl apply -f .config/crossplane/azure/azuresql-postgres-class.yaml
	kubectl apply -f .config/crossplane/azure/azuresql-postgres-rbac.yaml

}

#setup-cloudsql-crossplane
setup-cloudsql-crossplane () {

	scripts/dektecho.sh status "Installing crossplane provider for GCP and configure CloudSQL Postgres access"

	kubectl apply -f .config/crossplane/gcp/gcp-provider.yaml
		kubectl wait "providers.pkg.crossplane.io/provider-gcp" --for=condition=Healthy --timeout=3m

	SA_NAME=crossplane-cloudsql
    gcloud iam service-accounts create "${SA_NAME}" --project "${GCP_PROJECT_ID}"
    gcloud projects add-iam-policy-binding "${GCP_PROJECT_ID}" \
        --role="roles/cloudsql.admin" \
        --member "serviceAccount:${SA_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
    gcloud iam service-accounts keys create .config/creds-gcp.json --project "${GCP_PROJECT_ID}" --iam-account "${SA_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
    kubectl create secret generic gcp-creds -n crossplane-system --from-file=creds=.config/creds-gcp.json
	rm -f .config/creds-gcp.json

	kubectl apply -f .config/crossplane/gcp/gcp-provider-config.yaml
	kubectl apply -f .config/crossplane/gcp/cloudsql-postgres-xrd.yaml
	kubectl apply -f .config/crossplane/gcp/cloudsql-postgres-composition.yaml
	kubectl apply -f .config/crossplane/gcp/cloudsql-postgres-class.yaml
	kubectl apply -f .config/crossplane/gcp/cloudsql-postgres-rbac.yaml

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
    echo "  create [aks/eks/gke cluster-name numbber-of-nodes]"
    echo "  delete [aks/eks/gke cluster-name]"
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
set-context)
	case $clusterProvider in
	aks)
  		az aks get-credentials --overwrite-existing --resource-group $AZURE_RESOURCE_GROUP --name $clusterName
    	;;
	eks)
		kubectl config rename-context $AWS_IAM_USER@$clusterName.$AWS_REGION.eksctl.io $clusterName
		;;
	gke)
		kubectl config rename-context gke_$GCP_PROJECT_ID"_"$GCP_REGION"_"$clusterName $clusterName
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
setup-crossplane)
	case $clusterProvider in
	aks)
  		setup-azuresql-crossplane
    	;;
	eks)
		setup-rds-crossplane
		;;
	gke)
		setup-cloudsql-crossplane
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