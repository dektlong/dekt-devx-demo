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
        	kubectl wait "providers.pkg.crossplane.io/upbound-provider-aws-rds" --for=condition=Healthy --timeout=3m
		
cat <<EOF |	kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: aws-secret
  namespace: crossplane-system
stringData:
  creds: |
    $(printf "[default]\n    aws_access_key_id = %s\n    aws_secret_access_key = %s\n    aws_session_token = %s" "${AWS_ACCESS_KEY_ID}" "${AWS_SECRET_ACCESS_KEY}" "${AWS_SESSION_TOKEN}")
EOF

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


provider=$1
clusterName=$2
region=$3

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
	scripts/dektecho.sh err "Incorrect usage. Please specify provider, clusterName, region"
	;;
esac