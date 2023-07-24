#!/usr/bin/env bash


#setup-rabbitmq-crossplane
setup-rabbitmq-crossplane() {
	
	cluster_name=$1
	scripts/dektecho.sh status "Installing RabbitMQ operatror and setup crossplane in cluster $cluster_name"
	
	kapp -y deploy --app rmq-operator --file https://github.com/rabbitmq/cluster-operator/releases/latest/download/cluster-operator.yml

	kubectl apply -f .config/dataservices/oncluster/corp-rabbitmq-xrd.yaml

	kubectl apply -f .config/dataservices/oncluster/corp-rabbitmq-composition.yaml
	
	kubectl create ns rmq-corp

	kubectl apply -f .config/dataservices/oncluster/corp-rabbitmq-class.yaml

	kubectl apply -f .config/dataservices/oncluster/corp-rabbitmq-rbac.yaml


}

#setup-rds-crossplane
setup-rds-crossplane () {

        cluster_name=$1
		export region=$2
		scripts/dektecho.sh status "Installing crossplane provider for AWS cluster $cluster_name in region $region and configure RDS Postgres access"
        
        kubectl apply -f .config/dataservices/aws/aws-provider.yaml
        	kubectl wait "providers.pkg.crossplane.io/provider-aws" --for=condition=Healthy --timeout=3m
		
		awsProfile=default && echo -e "[default]\naws_access_key_id = $(aws configure get aws_access_key_id --profile $awsProfile)\naws_secret_access_key = $(aws configure get aws_secret_access_key --profile $awsProfile)\naws_session_token = $(aws configure get aws_session_token --profile $awsProfile)" > .config/creds-aws.conf
    	kubectl create secret generic aws-provider-creds -n crossplane-system --from-file=creds=.config/creds-aws.conf
    	rm -f .config/creds-aws.conf

		kubectl apply -f .config/dataservices/aws/aws-provider-config.yaml
		kubectl apply -f .config/dataservices/aws/rds-postgres-xrd.yaml
		yq '.spec.resources.[0].base.spec.forProvider.region = env(region)' .config/dataservices/aws/rds-postgres-composition.yaml -i
		kubectl apply -f .config/dataservices/aws/rds-postgres-composition.yaml
		kubectl apply -f .config/dataservices/aws/rds-postgres-class.yaml
		kubectl apply -f .config/dataservices/aws/rds-postgres-rbac.yaml

   
}

#setup-azuresql-crossplane
setup-azuresql-crossplane () {

	cluster_name=$1
	export location=$2
	azureSubscription=$(yq .clouds.azure.subscriptionID .config/demo-values.yaml)

	scripts/dektecho.sh status "Installing crossplane provider for Azure cluster $cluster_name in location $location and configure AzureSQL Postgres access"

	kubectl apply -f .config/dataservices/azure/azure-provider.yaml
		kubectl -n crossplane-system wait provider/provider-jet-azure --for=condition=Healthy=True --timeout=3m
	
	azureSpName='sql-crossplane-demo'
	kubectl create secret generic jet-azure-creds -o yaml --dry-run=client --from-literal=creds="$(
	az ad sp create-for-rbac -n "${azureSpName}" \
	--sdk-auth \
	--role "Contributor" \
	--scopes "/subscriptions/${azureSubscription}" \
	-o json
	)" | kubectl apply -n crossplane-system -f -

	kubectl apply -f .config/dataservices/azure/azure-provider-config.yaml

	serviceAccount=$(kubectl -n dataservices-system get sa -o name | grep provider-kubernetes | sed -e 's|serviceaccount\/|crossplane-system:|g')
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
	
	kubectl apply -f .config/dataservices/azure/azuresql-postgres-xrd.yaml
	yq '.spec.resources.[0].base.spec.forProvider.location = env(location)' .config/dataservices/azure/azuresql-postgres-composition.yaml -i
	kubectl apply -f .config/dataservices/azure/azuresql-postgres-composition.yaml
	kubectl apply -f .config/dataservices/azure/azuresql-postgres-class.yaml
	kubectl apply -f .config/dataservices/azure/azuresql-postgres-rbac.yaml

}

#provision-azuresql-direct
provision-azuresql-db-direct () {
	
	location=$(yq .clusters.stage.region .config/demo-values.yaml)
	namespace=$(yq .apps_namespaces.stageProd .config/demo-values.yaml)
	resourceGroup=db-group

	scripts/dektecho.sh status "Provisioning azuresql db instance named inventory-db in location $location , accesible in namespace $namespace"
	
	az group create --name $resourceGroup --location "$location"

	az sql server create --name dekt-db-server \
		--resource-group $resourceGroup \
		--location "$location" \
		--admin-user azure-admin \
		--admin-password appCl0udlong

	#az sql server firewall-rule create --resource-group $resourceGroup --server $server -n AllowYourIp --start-ip-address $startIp --end-ip-address $endIp

	az sql db create \
		--resource-group $resourceGroup \
		--server dekt-db-server \
		--name inventory-db \
		--sample-name AdventureWorksLT \
		--edition GeneralPurpose \
		--family Gen5 \
		--capacity 2 

	kubectl apply -f .config/dataservices/azure/direct-secret-binding.yaml -n $namespace

}

#provision-cloudsql-crossplane
provision-cloudsql-crossplane () {

	namespace=$(yq .apps_namespaces.stageProd .config/demo-values.yaml)
	kubectl apply -f .config/dataservices/gcp/cloudsql-postgres-instance.yaml -n $namespace

}

#provision-cloudsql-crossplane
provision-rds-db-crossplane () {

	namespace=$(yq .apps_namespaces.stageProd .config/demo-values.yaml)

	scripts/dektecho.sh status "Provisioning rds postgres instance name inventory-db, accesible in namespace $namespace"
	
	kubectl apply -f .config/dataservices/aws/rds-postgres-instance.yaml -n $namespace
}

#setup-cloudsql-crossplane
setup-cloudsql-crossplane () {

	cluster_name=$1
	export region=$2
	gcpProjectId=$(yq .clouds.gcp.projectID .config/demo-values.yaml)
	saName=crossplane-cloudsql

	scripts/dektecho.sh status "Installing crossplane provider for GCP cluster $cluster_name in region $region and configure CloudSQL Postgres access"

	kubectl apply -f .config/dataservices/gcp/gcp-provider.yaml
		kubectl wait "providers.pkg.crossplane.io/provider-gcp" --for=condition=Healthy --timeout=3m

	
    gcloud iam service-accounts create "${saName}" --project "${gcpProjectId}"
    gcloud projects add-iam-policy-binding "${gcpProjectId}" \
        --role="roles/cloudsql.admin" \
        --member "serviceAccount:${saName}@${gcpProjectId}.iam.gserviceaccount.com"
    gcloud iam service-accounts keys create .config/creds-gcp.json --project "${gcpProjectId}" --iam-account "${saName}@${gcpProjectId}.iam.gserviceaccount.com"
    kubectl create secret generic gcp-creds -n crossplane-system --from-file=creds=.config/creds-gcp.json
	rm -f .config/creds-gcp.json

	kubectl apply -f .config/dataservices/gcp/gcp-provider-config.yaml
	kubectl apply -f .config/dataservices/gcp/cloudsql-postgres-xrd.yaml
	yq '.spec.resources.[0].base.spec.forProvider.region = env(region)'  .config/dataservices/gcp/cloudsql-postgres-composition.yaml -i
	kubectl apply -f .config/dataservices/gcp/cloudsql-postgres-composition.yaml
	kubectl apply -f .config/dataservices/gcp/cloudsql-postgres-class.yaml
	kubectl apply -f .config/dataservices/gcp/cloudsql-postgres-rbac.yaml

}

#################### main #######################

#incorrect-usage
incorrect-usage() {
	
	scripts/dektecho.sh err "Incorrect usage. Please specify:"
    echo "  setup [ provider,clusterName, region ]"
	echo " 	provision-db [provider]"
	echo "	delete-db [provider] "
    exit
}

provider=$2
clusterName=$3
region=$4

case $1 in
setup)
	case $provider in
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
	;;
provision-db)
	case $provider in
	aks)
		provision-azuresql-db-direct
		#provision-azuresql-db-crossplane
		;;
	eks)
		provision-rds-db-crossplane
		;;
	gke)
		provision-cloudsql-db-crossplane
		;;
	*)
		incorrect-usage
		;;
	esac
	;;
delete-db)
	namespace=$(yq .apps_namespaces.stageProd .config/demo-values.yaml)
	case $provider in
	aks)
		az group delete --name db-group --yes
		#kubectl delete -f .config/dataservices/azure/azuresql-postgres-instance.yaml -n $namespace
		;;
	eks)
		kubectl delete -f .config/dataservices/aws/rds-postgres-instance.yaml -n $namespace
		;;
	gke)
		kubectl delete -f .config/dataservices/gcp/cloudsql-postgres-instance.yaml -n $namespace
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