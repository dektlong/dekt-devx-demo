#!/usr/bin/env bash

#################### configs ################
    #clusters
    DEV_CLUSTER_NAME=$(yq .clusters.dev.name .config/demo-values.yaml)
    DEV_CLUSTER_PROVIDER=$(yq .clusters.dev.provider .config/demo-values.yaml)
    DEV_CLUSTER_NODES=$(yq .clusters.dev.nodes .config/demo-values.yaml)
    STAGE_CLUSTER_NAME=$(yq .clusters.stage.name .config/demo-values.yaml)
    STAGE_CLUSTER_PROVIDER=$(yq .clusters.stage.provider .config/demo-values.yaml)
    STAGE_CLUSTER_NODES=$(yq .clusters.stage.nodes .config/demo-values.yaml)
    PROD_CLUSTER_NAME=$(yq .clusters.prod.name .config/demo-values.yaml)
    PROD_CLUSTER_PROVIDER=$(yq .clusters.prod.provider .config/demo-values.yaml)
    PROD_CLUSTER_NODES=$(yq .clusters.prod.nodes .config/demo-values.yaml)
    VIEW_CLUSTER_NAME=$(yq .clusters.view.name .config/demo-values.yaml)
    VIEW_CLUSTER_PROVIDER=$(yq .clusters.view.provider .config/demo-values.yaml)
    VIEW_CLUSTER_NODES=$(yq .clusters.view.nodes .config/demo-values.yaml)
    BROWNFIELD_CLUSTER_NAME=$(yq .clusters.brownfield.name .config/demo-values.yaml)
    BROWNFIELD_CLUSTER_PROVIDER=$(yq .clusters.brownfield.provider .config/demo-values.yaml)
    BROWNFIELD_CLUSTER_NODES=$(yq .clusters.brownfield.nodes .config/demo-values.yaml)
    PRIVATE_CLUSTER_NAME=$(yq .brownfield_apis.privateClusterContext .config/demo-values.yaml)

    #image registry
    PRIVATE_REPO_SERVER=$(yq .private_registry.host .config/demo-values.yaml)
    PRIVATE_REPO_USER=$(yq .private_registry.username .config/demo-values.yaml)
    PRIVATE_REPO_PASSWORD=$(yq .private_registry.password .config/demo-values.yaml)
    SYSTEM_REPO=$(yq .repositories.system .config/demo-values.yaml)
    #tap
    TANZU_NETWORK_USER=$(yq .tanzu_network.username .config/demo-values.yaml)
    TANZU_NETWORK_PASSWORD=$(yq .tanzu_network.password .config/demo-values.yaml)
    TAP_VERSION=$(yq .tap.tapVersion .config/demo-values.yaml)
    CARVEL_BUNDLE=$(yq .tap.carvel_bundle .config/demo-values.yaml)

    #apps-namespaces
    DEV_NAMESPACE=$(yq .apps_namespaces.dev .config/demo-values.yaml)
    TEAM_NAMESPACE=$(yq .apps_namespaces.team .config/demo-values.yaml)
    STAGEPROD_NAMESPACE=$(yq .apps_namespaces.stageProd .config/demo-values.yaml)
    #domains
    SYSTEM_SUB_DOMAIN=$(yq .dns.sysSubDomain .config/demo-values.yaml)
    DEV_SUB_DOMAIN=$(yq .dns.devSubDomain .config/demo-values.yaml)
    RUN_SUB_DOMAIN=$(yq .dns.prodSubDomain .config/demo-values.yaml)
    #data-services
    RDS_PROFILE=$(yq .data-services.rdsProfile .config/demo-values.yaml)
    TDS_VERSION=$(yq .data_services.tdsVersion .config/demo-values.yaml)       
    AWS_REGION=$(yq .clouds.aws.region .config/demo-values.yaml)
    #apis
    GW_INSTALL_DIR=$(yq .brownfield_apis.scgwInstallDirectory .config/demo-values.yaml)
 
#################### functions ################

    #install-view-cluster
    install-view-cluster() {

        scripts/dektecho.sh info "Installing demo components for $VIEW_CLUSTER_NAME cluster"

        kubectl config use-context $VIEW_CLUSTER_NAME

        scripts/tanzu-handler.sh add-carvel-tools
        
        install-tap "tap-view.yaml"

        scripts/dektecho.sh status "Adding custom accelerators"
        kubectl apply -f accelerators -n accelerator-system

        scripts/ingress-handler.sh update-tap-dns $SYSTEM_SUB_DOMAIN $VIEW_CLUSTER_PROVIDER

        update-store-secrets

        kubectl apply -f .config/cluster-configs/cluster-issuer.yaml
        
    }

    #install-dev-cluster
    install-dev-cluster() {

        scripts/dektecho.sh info "Installing demo components for $DEV_CLUSTER_NAME cluster"

        kubectl config use-context $DEV_CLUSTER_NAME

        scripts/tanzu-handler.sh add-carvel-tools

        add-app-rbac $DEV_NAMESPACE
        add-app-rbac $TEAM_NAMESPACE

        install-tap "tap-iterate.yaml"

        scripts/dektecho.sh status "Adding custom supply chains"
        kubectl apply -f .config/supply-chains/dekt-src-config.yaml
        kubectl apply -f .config/supply-chains/dekt-src-test-api-config.yaml
        kubectl apply -f .config/supply-chains/tekton-pipeline.yaml -n $DEV_NAMESPACE
        kubectl apply -f .config/supply-chains/tekton-pipeline.yaml -n $TEAM_NAMESPACE

        add-data-services "dev"

        scripts/ingress-handler.sh update-tap-dns $DEV_SUB_DOMAIN $DEV_CLUSTER_PROVIDER

        kubectl apply -f .config/cluster-configs/cluster-issuer.yaml
        
    }

    #install-stage-cluster
    install-stage-cluster() {

        scripts/dektecho.sh info "Installing demo components for $STAGE_CLUSTER_NAME cluster"

        kubectl config use-context $STAGE_CLUSTER_NAME

        scripts/tanzu-handler.sh add-carvel-tools

        add-app-rbac $STAGEPROD_NAMESPACE

        add-metadata-store-secrets

        install-tap "tap-build.yaml"

        install-snyk

        install-carbonblack
        
        scripts/dektecho.sh status "Adding custom supply chains"
        kubectl apply -f .config/supply-chains/dekt-src-scan-config.yaml
        kubectl apply -f .config/supply-chains/dekt-src-test-scan-api-config.yaml
        kubectl apply -f .config/supply-chains/tekton-pipeline.yaml -n $STAGEPROD_NAMESPACE
        kubectl apply -f .config/scanners/scan-policy.yaml -n $STAGEPROD_NAMESPACE #for all scanners

        add-data-services "stage"

        kubectl apply -f .config/cluster-configs/cluster-issuer.yaml
    }
    
    #install-prod-cluster
    install-prod-cluster() {

        scripts/dektecho.sh info "Installing demo components for $PROD_CLUSTER_NAME cluster"

        kubectl config use-context $PROD_CLUSTER_NAME

        scripts/tanzu-handler.sh add-carvel-tools

        add-app-rbac $STAGEPROD_NAMESPACE
        
        install-tap "tap-run.yaml"

        add-data-services "prod"

        scripts/ingress-handler.sh update-tap-dns $RUN_SUB_DOMAIN $PROD_CLUSTER_PROVIDER

        kubectl apply -f .config/cluster-configs/cluster-issuer.yaml
    }

    #install-tap
    install-tap() {

        tap_values_file_name=$1

        scripts/dektecho.sh status "Installing TAP on $(kubectl config current-context) cluster with $tap_values_file_name configs"

        kubectl create ns tap-install

        tanzu secret registry add tap-registry \
            --username ${PRIVATE_REPO_USER} --password ${PRIVATE_REPO_PASSWORD} \
           --server $PRIVATE_REPO_SERVER \
           --export-to-all-namespaces --yes --namespace tap-install

        tanzu package repository add tanzu-tap-repository \
            --url $PRIVATE_REPO_SERVER/$SYSTEM_REPO/tap-packages:$TAP_VERSION \
            --namespace tap-install

        tanzu package install tap -p tap.tanzu.vmware.com -v $TAP_VERSION \
            --values-file .config/tap-profiles/$tap_values_file_name \
            --namespace tap-install
    }

    #add-app-rbac
    add-app-rbac() {
        
        appsNamespace=$1

        scripts/dektecho.sh status "Setup $appsNamespace namespace on $(kubectl config current-context) cluster"

        kubectl create ns $appsNamespace
        
        tanzu secret registry add registry-credentials \
            --server $PRIVATE_REPO_SERVER \
            --username $PRIVATE_REPO_USER \
            --password $PRIVATE_REPO_PASSWORD \
            --namespace $appsNamespace    

        kubectl apply -f .config/supply-chains/gitops-creds.yaml -n $appsNamespace
        kubectl apply -f .config/cluster-configs/single-user-access.yaml -n $appsNamespace
        #currently not using the namespace provisioner since using customer sc with gitops
        #kubectl label namespaces $appsNamespace apps.tanzu.vmware.com/tap-ns=""
    }

    #add-data-services
    add-data-services() {

        mode=$1

        scripts/dektecho.sh status "Adding data services in $mode configuration"

        tanzu package repository add tanzu-data-services-repository \
        --url $PRIVATE_REPO_SERVER/$SYSTEM_REPO/tds-packages:$TDS_VERSION \
        --namespace tap-install

        case $mode in
        dev)
            install-tanzu-postgres $TEAM_NAMESPACE
            install-tanzu-rabbitmq $TEAM_NAMESPACE
            install-tanzu-rabbitmq $DEV_NAMESPACE
            ;;
        stage)
            #temp until service binding will be included in the build and run profiles
            #obtain available version
            services_toolkit_package=$(tanzu package available list -n tap-install | grep 'services-toolkit')
            services_toolkit_version=$(echo ${services_toolkit_package: -20} | sed 's/[[:space:]]//g')
            tanzu package install services-toolkit -n tap-install -p services-toolkit.tanzu.vmware.com -v $services_toolkit_version
            
            install-crossplane
            install-tanzu-rabbitmq $STAGEPROD_NAMESPACE
            ;;
        prod)
            install-crossplane 
            install-tanzu-rabbitmq $STAGEPROD_NAMESPACE
            ;;
        esac

    }
    #install-tanzu-rabbitmq
    install-tanzu-rabbitmq() {

        appNamespace=$1

        scripts/dektecho.sh status "Install Tanzu RabbitMQ operator in $appNamespace namespace with services toolkit support"

        #install RabbitMQ operator
        kubectl apply -f "https://github.com/rabbitmq/cluster-operator/releases/latest/download/cluster-operator.yml"
        
        #configure taznu services toolkit for RabbitMQ
        kubectl apply -f .config/data-services/tanzu/rabbitmq-cluster-config.yaml -n $appNamespace
        
    }

    #install tanzu postgres operator (on cluster)
    install-tanzu-postgres() {

        appNamespace=$1

        scripts/dektecho.sh status "Install Tanzu Postgres in $appNamespace namespace"

        #obtain available version
        postgres_package=$(tanzu package available list -n tap-install | grep 'postgres')
        postgres_version=$(echo ${postgres_package: -20} | sed 's/[[:space:]]//g')

        tanzu package install tanzu-postgres \
            --package-name postgres-operator.sql.tanzu.vmware.com \
            --version $postgres_version \
            --namespace tap-install

        kubectl apply -f .config/data-services/tanzu/cluster-intance-class-postgres.yaml
        kubectl apply -f .config/data-services/tanzu/resource-claims-postgres.yaml
                
    }

    #install-crossplane
    install-crossplane() {

        scripts/dektecho.sh status "Install Crossplane provider to AWS"
       
        kubectl create namespace crossplane-system

        helm repo add crossplane-stable https://charts.crossplane.io/stable
        helm repo update

        helm install crossplane --namespace crossplane-system crossplane-stable/crossplane \
        --set 'args={--enable-external-secret-stores}'

        sleep 30

        kubectl apply -f .config/data-services/rds-postgres/crossplane-aws-provider.yaml

        AWS_PROFILE=default && echo -e "[default]\naws_access_key_id = $(aws configure get aws_access_key_id --profile $AWS_PROFILE)\naws_secret_access_key = $(aws configure get aws_secret_access_key --profile $AWS_PROFILE)\naws_session_token = $(aws configure get aws_session_token --profile $AWS_PROFILE)" > .config/creds.conf

        kubectl create secret generic aws-provider-creds -n crossplane-system --from-file=creds=.config/creds.conf

        rm -f .config/creds.conf

    }
    
    #update-store-secrets
    update-store-secrets() {

        export storeCert=$(kubectl get secret -n metadata-store ingress-cert -o json | jq -r ".data.\"ca.crt\"")
        export storeToken=$(kubectl get secrets metadata-store-read-write-client -n metadata-store -o jsonpath="{.data.token}" | base64 -d)
        
        yq '.data."ca.crt"= env(storeCert)' .config/cluster-configs/store-ca-cert.yaml -i
        yq '.stringData.auth_token= env(storeToken)' .config/cluster-configs/store-auth-token.yaml -i
        
    }
    
    #add-metadata-store-secrets 
    add-metadata-store-secrets() {

        scripts/dektecho.sh status "Adding metadata-store-secrets to access remote Store"
        kubectl create ns metadata-store-secrets
        kubectl apply -f .config/cluster-configs/store-auth-token.yaml -n metadata-store-secrets
        kubectl apply -f .config/cluster-configs/store-ca-cert.yaml -n metadata-store-secrets
        kubectl apply -f .config/cluster-configs/store-secrets-export.yaml -n metadata-store-secrets
    }

    #install-snyk
    install-snyk() {

        scripts/dektecho.sh status "Add Snyk for image scanning "
        
        kubectl apply -f .config/scanners/snyk-creds.yaml -n $STAGEPROD_NAMESPACE

        #obtain available version
        snyk_package=$(tanzu package available list -n tap-install | grep 'snyk')
        snyk_version=$(echo ${snyk_package: -20} | sed 's/[[:space:]]//g')

        tanzu package install snyk-scanner \
            --package-name snyk.scanning.apps.tanzu.vmware.com \
            --version $snyk_version \
            --namespace tap-install \
            --values-file .config/scanners/snyk-values.yaml

        #kubectl apply -f .config/scanners/snyk-scan-policy.yaml -n $STAGEPROD_NAMESPACE
    }

     #install-carbonblack
    install-carbonblack() {

        scripts/dektecho.sh status "Add CarbonBlack for image scanning "
        
        #obtain available version
        carbon_package=$(tanzu package available list -n tap-install | grep 'carbonblack')
        carbon_version=$(echo ${carbon_package: -20} | sed 's/[[:space:]]//g')
        
        kubectl apply -f .config/scanners/carbonblack-creds.yaml -n $STAGEPROD_NAMESPACE

        tanzu package install carbonblack-scanner \
            --package-name carbonblack.scanning.apps.tanzu.vmware.com \
            --version $carbon_version \
            --namespace tap-install \
            --values-file .config/scanners/carbonblack-values.yaml
        
        #kubectl apply -f .config/scanners/carbonblack-scan-policy.yaml -n $STAGEPROD_NAMESPACE

    }
    #update-multi-cluster-access
    update-multi-cluster-access() {
        
        scripts/dektecho.sh status "Updating Backstage access to dev,stage & prod clusters"

        #configure GUI on view cluster to access dev cluster
        kubectl config use-context $DEV_CLUSTER_NAME
        kubectl apply -f .config/cluster-configs/reader-accounts.yaml
        export devClusterUrl=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
        export devClusterName=$DEV_CLUSTER_NAME

        #k8 1.24 changes
        kubectl apply -f .config/cluster-configs/tap-gui-secret.yaml
        export devClusterToken=$(kubectl -n tap-gui get secret tap-gui-viewer -o=json \
            | jq -r '.data["token"]' \
            | base64 --decode)

        yq '.tap_gui.app_config.kubernetes.clusterLocatorMethods.[0].clusters.[0].url = env(devClusterUrl)' .config/tap-profiles/tap-view.yaml -i
        yq '.tap_gui.app_config.kubernetes.clusterLocatorMethods.[0].clusters.[0].name = env(devClusterName)' .config/tap-profiles/tap-view.yaml -i
        yq '.tap_gui.app_config.kubernetes.clusterLocatorMethods.[0].clusters.[0].serviceAccountToken = env(devClusterToken)' .config/tap-profiles/tap-view.yaml -i

        #configure GUI on view cluster to access stage cluster
        kubectl config use-context $STAGE_CLUSTER_NAME
        kubectl apply -f .config/cluster-configs/reader-accounts.yaml
        export stageClusterUrl=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
        export stageClusterName=$STAGE_CLUSTER_NAME
        export stageClusterToken=$(kubectl -n tap-gui get secret $(kubectl -n tap-gui get sa tap-gui-viewer -o=json \
        | jq -r '.secrets[0].name') -o=json \
        | jq -r '.data["token"]' \
        | base64 --decode)
        yq '.tap_gui.app_config.kubernetes.clusterLocatorMethods.[0].clusters.[1].url = env(stageClusterUrl)' .config/tap-profiles/tap-view.yaml -i
        yq '.tap_gui.app_config.kubernetes.clusterLocatorMethods.[0].clusters.[1].name = env(stageClusterName)' .config/tap-profiles/tap-view.yaml -i
        yq '.tap_gui.app_config.kubernetes.clusterLocatorMethods.[0].clusters.[1].serviceAccountToken = env(stageClusterToken)' .config/tap-profiles/tap-view.yaml -i
    

        #configure GUI on view cluster to access prod cluster
        kubectl config use-context $PROD_CLUSTER_NAME
        kubectl apply -f .config/cluster-configs/reader-accounts.yaml
        export prodClusterUrl=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
        export prodClusterName=$PROD_CLUSTER_NAME
        export prodClusterToken=$(kubectl -n tap-gui get secret $(kubectl -n tap-gui get sa tap-gui-viewer -o=json \
        | jq -r '.secrets[0].name') -o=json \
        | jq -r '.data["token"]' \
        | base64 --decode)
        yq '.tap_gui.app_config.kubernetes.clusterLocatorMethods.[0].clusters.[2].url = env(prodClusterUrl)' .config/tap-profiles/tap-view.yaml -i
        yq '.tap_gui.app_config.kubernetes.clusterLocatorMethods.[0].clusters.[2].name = env(prodClusterName)' .config/tap-profiles/tap-view.yaml -i
        yq '.tap_gui.app_config.kubernetes.clusterLocatorMethods.[0].clusters.[2].serviceAccountToken = env(prodClusterToken)' .config/tap-profiles/tap-view.yaml -i

        #configure view cluster proxy
        kubectl config use-context $VIEW_CLUSTER_NAME
        storeToken=$(kubectl get secrets metadata-store-read-write-client -n metadata-store -o jsonpath="{.data.token}" | base64 -d)
        export storeProxyAuthHeader="Bearer $storeToken"
        yq '.tap_gui.app_config.proxy."/metadata-store".headers.Authorization= env(storeProxyAuthHeader)' .config/tap-profiles/tap-view.yaml -i

        #update view cluster tap package
        tanzu package installed update tap --package-name tap.tanzu.vmware.com --version $TAP_VERSION -n tap-install -f .config/tap-profiles/tap-view.yaml
        

    } 
 
    #add-brownfield-apis
    add-brownfield-apis () {
        
        brownfield_apis_ns="brownfield-apis"

        scripts/dektecho.sh info "Installing brownfield APIs components"

        scripts/dektecho.sh status "adding 'provider' components on $BROWNFIELD_CLUSTER_NAME cluster"
        kubectl config use-context $BROWNFIELD_CLUSTER_NAME
        kubectl create ns scgw-system
        kubectl create secret docker-registry spring-cloud-gateway-image-pull-secret --docker-server=$PRIVATE_REPO_SERVER --docker-username=$PRIVATE_REPO_USER --docker-password=$PRIVATE_REPO_PASSWORD --namespace scgw-system
        $GW_INSTALL_DIR/scripts/install-spring-cloud-gateway.sh --namespace scgw-system
        kubectl create ns $brownfield_apis_ns
        kubectl apply -f brownfield-apis/sentiment.yaml -n $brownfield_apis_ns

        scripts/dektecho.sh status "adding 'provider' components on $PRIVATE_CLUSTER_NAME cluster"
        kubectl config use-context $PRIVATE_CLUSTER_NAME
        kubectl create ns scgw-system
        kubectl create secret docker-registry spring-cloud-gateway-image-pull-secret --docker-server=$PRIVATE_REPO_SERVER --docker-username=$PRIVATE_REPO_USER --docker-password=$PRIVATE_REPO_PASSWORD --namespace scgw-system
        $GW_INSTALL_DIR/scripts/install-spring-cloud-gateway.sh --namespace scgw-system
        kubectl create ns $brownfield_apis_ns
        kubectl apply -f brownfield-apis/datacheck.yaml -n $brownfield_apis_ns
    
        scripts/dektecho.sh status "adding'consumer' components on $DEV_CLUSTER_NAME cluster"
        kubectl config use-context $DEV_CLUSTER_NAME
        kubectl create ns $brownfield_apis_ns
        kubectl create service clusterip sentiment-api --tcp=80:80 -n $brownfield_apis_ns
        kubectl create service clusterip datacheck-api --tcp=80:80 -n $brownfield_apis_ns

        scripts/dektecho.sh status "adding 'consumer' components on $STAGE_CLUSTER_NAME cluster"
        kubectl config use-context $STAGE_CLUSTER_NAME
        kubectl create ns $brownfield_apis_ns
        kubectl create service clusterip sentiment-api --tcp=80:80 -n $brownfield_apis_ns
        kubectl create service clusterip datacheck-api --tcp=80:80 -n $brownfield_apis_ns

        scripts/dektecho.sh status "adding 'consumer' components on $PROD_CLUSTER_NAME cluster"
        kubectl config use-context $PROD_CLUSTER_NAME
        kubectl create ns $brownfield_apis_ns
        kubectl create service clusterip sentiment-api --tcp=80:80 -n $brownfield_apis_ns
        kubectl create service clusterip datacheck-api --tcp=80:80 -n $brownfield_apis_ns

    }

     #attach TMC clusters
    attach-tmc-clusters() {

        scripts/tanzu-handler.sh tmc-cluster attach $VIEW_CLUSTER_NAME
        scripts/tanzu-handler.sh tmc-cluster attach $DEV_CLUSTER_NAME
        scripts/tanzu-handler.sh tmc-cluster attach $STAGE_CLUSTER_NAME
        scripts/tanzu-handler.sh tmc-cluster attach $PROD_CLUSTER_NAME
        scripts/tanzu-handler.sh tmc-cluster attach $BROWNFIELD_CLUSTER_NAME

    }
    
    #delete-tmc-cluster
    delete-tmc-clusters() {

        scripts/tanzu-handler.sh tmc-cluster remove $VIEW_CLUSTER_NAME
        scripts/tanzu-handler.sh tmc-cluster remove $DEV_CLUSTER_NAME
        scripts/tanzu-handler.sh tmc-cluster remove $STAGE_CLUSTER_NAME
        scripts/tanzu-handler.sh tmc-cluster remove $PROD_CLUSTER_NAME
        scripts/tanzu-handler.sh tmc-cluster remove $BROWNFIELD_CLUSTER_NAME
    }

    
    #incorrect usage
    incorrect-usage() {
        
        scripts/dektecho.sh err "Incorrect usage. Please specify one of the following: "
        
        echo "  init-all"
        echo 
        echo "  create-clusters"
        echo 
        echo "  install-demo"
        echo 
        echo "  delete-all"
        echo
        echo "  generate-configs"
        echo
        echo "  export-packages tap|tbs|tds|scgw"
        echo
        echo "  runme [ function-name ]"
        echo
        exit
    }


#################### main ##########################


case $1 in
create-clusters)
    scripts/k8s-handler.sh create $VIEW_CLUSTER_PROVIDER $VIEW_CLUSTER_NAME $VIEW_CLUSTER_NODES \
    & scripts/k8s-handler.sh create $DEV_CLUSTER_PROVIDER $DEV_CLUSTER_NAME $DEV_CLUSTER_NODES \
    & scripts/k8s-handler.sh create $STAGE_CLUSTER_PROVIDER $STAGE_CLUSTER_NAME $STAGE_CLUSTER_NODES \
    & scripts/k8s-handler.sh create $PROD_CLUSTER_PROVIDER $PROD_CLUSTER_NAME $PROD_CLUSTER_NODES \
    & scripts/k8s-handler.sh create $BROWNFIELD_CLUSTER_PROVIDER $BROWNFIELD_CLUSTER_NAME $BROWNFIELD_CLUSTER_NODES  
    ;;
install-demo)
    #set k8s contexts and verify cluster install
    scripts/k8s-handler.sh init $VIEW_CLUSTER_PROVIDER $VIEW_CLUSTER_NAME
    scripts/k8s-handler.sh init $DEV_CLUSTER_PROVIDER $DEV_CLUSTER_NAME
    scripts/k8s-handler.sh init $STAGE_CLUSTER_PROVIDER $STAGE_CLUSTER_NAME
    scripts/k8s-handler.sh init $PROD_CLUSTER_PROVIDER $PROD_CLUSTER_NAME
    scripts/k8s-handler.sh init $BROWNFIELD_CLUSTER_PROVIDER $BROWNFIELD_CLUSTER_NAME
    #install all demo components
    install-view-cluster
    install-dev-cluster
    install-stage-cluster
    install-prod-cluster
    update-multi-cluster-access
    add-brownfield-apis
    attach-tmc-clusters 
    ;;
delete-all)
    scripts/dektecho.sh prompt  "Are you sure you want to delete all clusters?" && [ $? -eq 0 ] || exit
    ./demo.sh reset
    delete-tmc-clusters
    scripts/k8s-handler.sh delete $VIEW_CLUSTER_PROVIDER $VIEW_CLUSTER_NAME \
    & scripts/k8s-handler.sh delete $DEV_CLUSTER_PROVIDER $DEV_CLUSTER_NAME \
    & scripts/k8s-handler.sh delete $STAGE_CLUSTER_PROVIDER $STAGE_CLUSTER_NAME \
    & scripts/k8s-handler.sh delete $PROD_CLUSTER_PROVIDER $PROD_CLUSTER_NAME \
    & scripts/k8s-handler.sh delete $BROWNFIELD_CLUSTER_PROVIDER $BROWNFIELD_CLUSTER_NAME
    ;;
generate-configs)
    scripts/tanzu-handler.sh generate-configs
    ;;
export-packages)
    scripts/tanzu-handler.sh relocate-tanzu-images $2
    ;;
runme)
    $2 $3 $4
    ;;
*)
    incorrect-usage
    ;;
esac