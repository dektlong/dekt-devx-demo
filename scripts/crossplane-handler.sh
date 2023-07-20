#!/usr/bin/env bash


#setup-rabbitmq-crossplane
setup-rabbitmq-crossplane() {
	
	cluster_name=$1
	scripts/dektecho.sh status "Installing RabbitMQ operatror and setup crossplane in cluster $cluster_name"
	
	kapp -y deploy --app rmq-operator --file https://github.com/rabbitmq/cluster-operator/releases/latest/download/cluster-operator.yml

	kubectl apply -f .config/crossplane/oncluster/corp-rabbitmq-xrd.yaml

	kubectl apply -f .config/crossplane/oncluster/corp-rabbitmq-composition.yaml
	
	kubectl create ns rmq-corp

	kubectl apply -f .config/crossplane/oncluster/corp-rabbitmq-class.yaml

	kubectl apply -f .config/crossplane/oncluster/corp-rabbitmq-rbac.yaml


}

#setup-rds-crossplane
setup-rds-crossplane () {

        cluster_name=$1
		export region=$2
		scripts/dektecho.sh status "Installing crossplane provider for AWS cluster $cluster_name in region $region and configure RDS Postgres access"
        
        kubectl apply -f .config/crossplane/aws/aws-provider.yaml
        	kubectl wait "providers.pkg.crossplane.io/provider-aws" --for=condition=Healthy --timeout=3m
		
		awsProfile=default && echo -e "[default]\naws_access_key_id = $(aws configure get aws_access_key_id --profile $awsProfile)\naws_secret_access_key = $(aws configure get aws_secret_access_key --profile $awsProfile)\naws_session_token = $(aws configure get aws_session_token --profile $awsProfile)" > .config/creds-aws.conf
    	kubectl create secret generic aws-provider-creds -n crossplane-system --from-file=creds=.config/creds-aws.conf
    	rm -f .config/creds-aws.conf

		kubectl apply -f .config/crossplane/aws/aws-provider-config.yaml
		kubectl apply -f .config/crossplane/aws/rds-postgres-xrd.yaml
		yq '.spec.resources.[0].base.spec.forProvider.region = env(region)' .config/crossplane/aws/rds-postgres-composition.yaml -i
		kubectl apply -f .config/crossplane/aws/rds-postgres-composition.yaml
		kubectl apply -f .config/crossplane/aws/rds-postgres-class.yaml
		kubectl apply -f .config/crossplane/aws/rds-postgres-rbac.yaml

   
}

#setup-azuresql-crossplane
setup-azuresql-crossplane () {

	cluster_name=$1
	export location=$2
	azureSubscription=$(yq .clouds.azure.subscriptionID .config/demo-values.yaml)

	scripts/dektecho.sh status "Installing crossplane provider for Azure cluster $cluster_name in location $location and configure AzureSQL Postgres access"

	kubectl apply -f .config/crossplane/azure/azure-provider.yaml
		kubectl -n crossplane-system wait provider/provider-jet-azure --for=condition=Healthy=True --timeout=3m
	
	azureSpName='sql-crossplane-demo'
	kubectl create secret generic jet-azure-creds -o yaml --dry-run=client --from-literal=creds="$(
	az ad sp create-for-rbac -n "${azureSpName}" \
	--sdk-auth \
	--role "Contributor" \
	--scopes "/subscriptions/${azureSubscription}" \
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
	yq '.spec.resources.[0].base.spec.forProvider.location = env(location)' .config/crossplane/azure/azuresql-postgres-composition.yaml -i
	kubectl apply -f .config/crossplane/azure/azuresql-postgres-composition.yaml
	kubectl apply -f .config/crossplane/azure/azuresql-postgres-class.yaml
	kubectl apply -f .config/crossplane/azure/azuresql-postgres-rbac.yaml

}

#setup-cloudsql-crossplane
setup-cloudsql-crossplane () {

	cluster_name=$1
	export region=$2
	gcpProjectId=$(yq .clouds.gcp.projectID .config/demo-values.yaml)
	saName=crossplane-cloudsql

	scripts/dektecho.sh status "Installing crossplane provider for GCP cluster $cluster_name in region $region and configure CloudSQL Postgres access"

	kubectl apply -f .config/crossplane/gcp/gcp-provider.yaml
		kubectl wait "providers.pkg.crossplane.io/provider-gcp" --for=condition=Healthy --timeout=3m

	
    gcloud iam service-accounts create "${saName}" --project "${gcpProjectId}"
    gcloud projects add-iam-policy-binding "${gcpProjectId}" \
        --role="roles/cloudsql.admin" \
        --member "serviceAccount:${saName}@${gcpProjectId}.iam.gserviceaccount.com"
    gcloud iam service-accounts keys create .config/creds-gcp.json --project "${gcpProjectId}" --iam-account "${saName}@${gcpProjectId}.iam.gserviceaccount.com"
    kubectl create secret generic gcp-creds -n crossplane-system --from-file=creds=.config/creds-gcp.json
	rm -f .config/creds-gcp.json

	kubectl apply -f .config/crossplane/gcp/gcp-provider-config.yaml
	kubectl apply -f .config/crossplane/gcp/cloudsql-postgres-xrd.yaml
	yq '.spec.resources.[0].base.spec.forProvider.region = env(region)'  .config/crossplane/gcp/cloudsql-postgres-composition.yaml -i
	kubectl apply -f .config/crossplane/gcp/cloudsql-postgres-composition.yaml
	kubectl apply -f .config/crossplane/gcp/cloudsql-postgres-class.yaml
	kubectl apply -f .config/crossplane/gcp/cloudsql-postgres-rbac.yaml

}



#################### main #######################

#incorrect-usage
incorrect-usage() {
	
	scripts/dektecho.sh err "Incorrect usage. Please specify:"
    echo "  aks/eks/gke cluster-name region"
    exit
}

clusterProvider=$1
clusterName=$2
region=$3

case $clusterProvider in
aks)
	setup-azuresql-crossplane $clusterName $region
	setup-rabbitmq-crossplane $clusterName
    ;;
eks)
	setup-rds-crossplane $clusterName $region
	setup-rabbitmq-crossplane $clusterName
	;;
gke)
	setup-cloudsql-crossplane $clusterName $region
	setup-rabbitmq-crossplane $clusterName
	;;
*)
	incorrect-usage
	;;
esac