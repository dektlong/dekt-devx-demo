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
    TAP_VERSION=$(yq .tap.version .config/demo-values.yaml)
    CARVEL_BUNDLE=$(yq .tap.carvel_bundle .config/demo-values.yaml)
    SNYK_VERSION=$(yq .snyk.version .config/demo-values.yaml)
    CARBONBLACK_VERSION=$(yq .carbonblack.version .config/demo-values.yaml)
    SERVICES_TOOLKIT_VERSION=$(yq .tap.serviceToolkitVersion .config/demo-values.yaml)
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
    TANZU_POSTGRES_VERSION=$(yq .data_services.tanzuPostgresVersion .config/demo-values.yaml)
    #apis
    GW_INSTALL_DIR=$(yq .brownfield_apis.scgwInstallDirectory .config/demo-values.yaml)
    #tmc
    export TMC_API_TOKEN=$(yq .tmc.apiToken .config/demo-values.yaml)
    TMC_CLUSTER_GROUP=$(yq .tmc.clusterGroup .config/demo-values.yaml)

#################### functions ################

    #install-view-cluster
    install-view-cluster() {

        scripts/dektecho.sh info "Installing demo components for $VIEW_CLUSTER_NAME cluster"

        kubectl config use-context $VIEW_CLUSTER_NAME

        scripts/tanzu-handler.sh add-carvel-tools
        
        add-tap-package "tap-view.yaml"

        scripts/dektecho.sh status "Adding custom accelerators"
        kubectl apply -f accelerators -n accelerator-system

        scripts/ingress-handler.sh update-tap-dns $SYSTEM_SUB_DOMAIN

        update-store-secrets
    }

    #install-dev-cluster
    install-dev-cluster() {

        scripts/dektecho.sh info "Installing demo components for $DEV_CLUSTER_NAME cluster"

        kubectl config use-context $DEV_CLUSTER_NAME

        scripts/tanzu-handler.sh add-carvel-tools

        add-app-rbac $DEV_NAMESPACE
        add-app-rbac $TEAM_NAMESPACE

        add-tap-package "tap-iterate.yaml"

        scripts/dektecho.sh status "Adding custom supply chains"
        kubectl apply -f .config/supply-chains/dekt-src-config.yaml
        kubectl apply -f .config/supply-chains/dekt-src-test-api-config.yaml
        kubectl apply -f .config/supply-chains/tekton-pipeline.yaml -n $DEV_NAMESPACE
        kubectl apply -f .config/supply-chains/tekton-pipeline.yaml -n $TEAM_NAMESPACE

        add-data-services "dev"

        scripts/ingress-handler.sh update-tap-dns $DEV_SUB_DOMAIN
    }

    #install-stage-cluster
    install-stage-cluster() {

        scripts/dektecho.sh info "Installing demo components for $STAGE_CLUSTER_NAME cluster"

        kubectl config use-context $STAGE_CLUSTER_NAME

        scripts/tanzu-handler.sh add-carvel-tools
    
        add-app-rbac $STAGEPROD_NAMESPACE

        add-metadata-store-secrets

        add-tap-package "tap-build.yaml"

        install-snyk

        install-carbonblack
        
        scripts/dektecho.sh status "Adding custom supply chains"
        kubectl apply -f .config/supply-chains/dekt-src-scan-config.yaml
        kubectl apply -f .config/supply-chains/dekt-src-test-scan-api-config.yaml
        kubectl apply -f .config/supply-chains/tekton-pipeline.yaml -n $STAGEPROD_NAMESPACE
        kubectl apply -f .config/scanners/scan-policy.yaml -n $STAGEPROD_NAMESPACE #for all scanners

        add-data-services "stage"

    }
    
    #install-prod-cluster
    install-prod-cluster() {

        scripts/dektecho.sh info "Installing demo components for $PROD_CLUSTER_NAME cluster"

        kubectl config use-context $PROD_CLUSTER_NAME

        scripts/tanzu-handler.sh add-carvel-tools
        
        add-app-rbac $STAGEPROD_NAMESPACE
        
        add-tap-package "tap-run.yaml"

        add-data-services "prod"

        scripts/ingress-handler.sh update-tap-dns $RUN_SUB_DOMAIN

    }

    #add-tap-package
    add-tap-package() {

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
            add-tanzu-postgres $TEAM_NAMESPACE
            add-tanzu-rabbitmq 1 $TEAM_NAMESPACE
            ;;
        stage)
            #temp until service binding will be included in the build and run profiles
            tanzu package install services-toolkit -n tap-install -p services-toolkit.tanzu.vmware.com -v $SERVICES_TOOLKIT_VERSION
            add-rds-postgres $STAGEPROD_NAMESPACE
            add-tanzu-rabbitmq 2 $STAGEPROD_NAMESPACE
            ;;
        prod)
            add-rds-postgres $STAGEPROD_NAMESPACE
            add-tanzu-rabbitmq 2 $STAGEPROD_NAMESPACE
            ;;
        esac

    }
    #add-tanzu-rabbitmq
    add-tanzu-rabbitmq() {

        export numReplicas=$1
        appNamespace=$2

        scripts/dektecho.sh status "Adding Tanzu RabbitMQ with $numReplicas replicas in namespace $appNamespace"

        #install RabbitMQ operator
        kubectl apply -f "https://github.com/rabbitmq/cluster-operator/releases/latest/download/cluster-operator.yml"
        
        #configure taznu services toolkit for RabbitMQ
        kubectl apply -f .config/data-services/tanzu/rabbitmq-cluster-config.yaml -n $appNamespace
        
        #provision the RabbitMQ 'reading' instance(s)
        yq '.spec.replicas = env(numReplicas)' .config/data-services/tanzu/reading-instance-tanzu_rabbitmq.yaml -i
        kubectl apply -f .config/data-services/tanzu/reading-instance-tanzu_rabbitmq.yaml -n $appNamespace

        #create a service claim
        tanzu service claim create rabbitmq-claim -n $appNamespace \
            --resource-name reading-queue \
            --resource-kind RabbitmqCluster \
            --resource-api-version rabbitmq.com/v1beta1
    }

    #add tanzu postgres operator (on cluster)
    add-tanzu-postgres() {

        appNamespace=$1

        scripts/dektecho.sh status "Install Tanzu Postgres in $appNamespace namespace"

        tanzu package install tanzu-postgres \
            --package-name postgres-operator.sql.tanzu.vmware.com \
            --version $TANZU_POSTGRES_VERSION \
            --namespace tap-install

        kubectl apply -f .config/data-services/tanzu/cluster-intance-class-postgres.yaml
        kubectl apply -f .config/data-services/tanzu/resource-claims-postgres.yaml
        

        #provision inventory-db instance 
        kubectl apply -f .config/data-services/tanzu/inventory-instance-tanzu_postgres.yaml -n $appNamespace

        #create inventory-db resource claim
        tanzu service claim create postgres-claim \
            --resource-name inventory-db \
            --resource-kind Postgres \
            --resource-api-version sql.tanzu.vmware.com/v1 \
            --resource-namespace $appNamespace \
            --namespace $appNamespace
    }

    #add-rds-postgres
    add-rds-postgres() { #WIP

        appNamespace=$1

        scripts/dektecho.sh status "Install Crossplane connector to RDS Postgres in $appNamespace namespace"
        #install crossplane 
        #kubectl create namespace crossplane-system
        #helm repo add crossplane-stable https://charts.crossplane.io/stable
        #helm repo update
        #helm install crossplane --namespace crossplane-system crossplane-stable/crossplane \
        #    --set 'args={--enable-external-secret-stores}'
        
        #configure crossplan access to your RDS account
        #AWS_PROFILE=$RDS_PROFILE && echo -e "[$RDS_PROFILE]\naws_access_key_id = $(aws configure get aws_access_key_id --profile $AWS_PROFILE)\naws_secret_access_key = $(aws configure get aws_secret_access_key --profile $AWS_PROFILE)\naws_session_token = $(aws configure get aws_session_token --profile $AWS_PROFILE)" > creds.conf
        #kubectl create secret generic aws-provider-creds -n crossplane-system --from-file=creds=./creds.conf
        #rm -f creds.conf
        
        #configure taznu services toolkit for RDS
        #kubectl apply -f .config/data-services/postgres-cluster-config.yaml
        
        #provision the RDS postgres-inventory-db instance using crossplane
        #kubectl apply -f .config/data-services/inventory-db-prod.yaml -n $TEAM_NAMESPACE

        #scripts/dektecho.sh status "Waiting for RDS PostgreSQL instance named inventory-db to be create"
        #kubectl wait --for=condition=Ready=true postgresqlinstances.bindable.database.example.org inventory-db

        kubectl apply -f .config/data-services/aws/inventory-instance-rds_postgresql.yaml -n $appNamespace

        #create a service claim for inventory-db
        tanzu service claim create postgres-claim -n $appNamespace \
            --resource-name inventory-db \
            --resource-kind Secret \
            --resource-api-version v1 
    }
    
    #update-store-secrets
    update-store-secrets() {

        export storeCert=$(kubectl get secret -n metadata-store ingress-cert -o json | jq -r ".data.\"ca.crt\"")
        export storeToken=$(kubectl get secrets metadata-store-read-write-client -n metadata-store -o jsonpath="{.data.token}" | base64 -d)
        export storeProxyAuthHeader="Bearer $storeToken"

        yq '.data."ca.crt"= env(storeCert)' .config/cluster-configs/store-ca-cert.yaml -i
        yq '.stringData.auth_token= env(storeToken)' .config/cluster-configs/store-auth-token.yaml -i
        yq '.tap_gui.app_config.proxy."/metadata-store".headers.Authorization= env(storeProxyAuthHeader)' .config/tap-profiles/tap-view.yaml -i
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

        tanzu package install snyk-scanner \
            --package-name snyk.scanning.apps.tanzu.vmware.com \
            --version $SNYK_VERSION \
            --namespace tap-install \
            --values-file .config/scanners/snyk-values.yaml

        #kubectl apply -f .config/scanners/snyk-scan-policy.yaml -n $STAGEPROD_NAMESPACE
    }

     #install-carbonblack
    install-carbonblack() {

        scripts/dektecho.sh status "Add CarbonBlack for image scanning "
        
        kubectl apply -f .config/scanners/carbonblack-creds.yaml -n $STAGEPROD_NAMESPACE

        tanzu package install carbonblack-scanner \
            --package-name carbonblack.scanning.apps.tanzu.vmware.com \
            --version $CARBONBLACK_VERSION \
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
        export devClusterToken=$(kubectl -n tap-gui get secret $(kubectl -n tap-gui get sa tap-gui-viewer -o=json \
        | jq -r '.secrets[0].name') -o=json \
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

        #update view cluster after config changes
        kubectl config use-context $VIEW_CLUSTER_NAME
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

        attach-tmc-cluster $VIEW_CLUSTER_NAME
        attach-tmc-cluster $DEV_CLUSTER_NAME
        attach-tmc-cluster $STAGE_CLUSTER_NAME
        attach-tmc-cluster $PROD_CLUSTER_NAME

    }
    #attach TMC cluster
    attach-tmc-cluster() {

        scripts/dektecho.sh info "Attaching TMC clusters"

        tmc system context create -n devxdemo-tmc -c
        tmc login -n tmc-login -c

        kubectl config use-context $VIEW_CLUSTER_NAME
        tmc cluster attach -n $VIEW_CLUSTER_NAME -g $TMC_CLUSTER_GROUP
        kubectl apply -f k8s-attach-manifest.yaml
        rm -f k8s-attach-manifest.yaml

        kubectl config use-context $DEV_CLUSTER_NAME
        tmc cluster attach -n $DEV_CLUSTER_NAME -g $TMC_CLUSTER_GROUP
        kubectl apply -f k8s-attach-manifest.yaml 

        rm -f k8s-attach-manifest.yaml

        kubectl config use-context $STAGE_CLUSTER_NAME
        tmc cluster attach -n $STAGE_CLUSTER_NAME -g $TMC_CLUSTER_GROUP
        kubectl apply -f k8s-attach-manifest.yaml
        rm -f k8s-attach-manifest.yaml

        kubectl config use-context $PROD_CLUSTER_NAME
        tmc cluster attach -n $PROD_CLUSTER_NAME -g $TMC_CLUSTER_GROUP
        kubectl apply -f k8s-attach-manifest.yaml
        rm -f k8s-attach-manifest.yaml

        kubectl config use-context $BROWNFIELD_CLUSTER_NAME
        tmc cluster attach -n $BROWNFIELD_CLUSTER_NAME -g $TMC_CLUSTER_GROUP
        kubectl apply -f k8s-attach-manifest.yaml
        rm -f k8s-attach-manifest.yaml

    }

    #delete-tmc-cluster
    delete-tmc-clusters() {

        tmc login -n devxdemo-tmc -c

        tmc cluster delete $VIEW_CLUSTER_NAME -f -m attached -p attached
        tmc cluster delete $DEV_CLUSTER_NAME -f -m attached -p attached
        tmc cluster delete $STAGE_CLUSTER_NAME -f -m attached -p attached
        tmc cluster delete $PROD_CLUSTER_NAME -f -m attached -p attached
        tmc cluster delete $BROWNFIELD_CLUSTER_NAME -f -m attached -p attached
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
        echo "  relocate-tap-images"
        echo
        echo "  runme [ function-name ]"
        echo
        exit
    }

    #innerloop-handler
    innerloop-handler() {

        case $1 in
        create-clusters) 
            scripts/k8s-handler.sh create $VIEW_CLUSTER_PROVIDER $VIEW_CLUSTER_NAME $VIEW_CLUSTER_NODES \
            & scripts/k8s-handler.sh create $DEV_CLUSTER_PROVIDER $DEV_CLUSTER_NAME $DEV_CLUSTER_NODES
            ;;
      set-contexts)
            scripts/k8s-handler.sh set-context $VIEW_CLUSTER_PROVIDER $VIEW_CLUSTER_NAME
            scripts/k8s-handler.sh set-context $DEV_CLUSTER_PROVIDER $DEV_CLUSTER_NAME
            ;;
        delete-clusters)
            scripts/k8s-handler.sh delete $VIEW_CLUSTER_NAME $VIEW_CLUSTER_PROVIDER \
            & scripts/k8s-handler.sh delete $DEV_CLUSTER_NAME $DEV_CLUSTER_PROVIDER 
            ;;
        install-demo)
            install-view-cluster
            install-dev-cluster 
            ;;
        esac
    }

    #outerloop-handler
    outerloop-handler() {

        case $1 in
        create-clusters) 
            scripts/k8s-handler.sh create $STAGE_CLUSTER_PROVIDER $STAGE_CLUSTER_NAME $STAGE_CLUSTER_NODES \
            & scripts/k8s-handler.sh create $PROD_CLUSTER_PROVIDER $PROD_CLUSTER_NAME $PROD_CLUSTER_NODES \
            & scripts/k8s-handler.sh create $BROWNFIELD_CLUSTER_PROVIDER $BROWNFIELD_CLUSTER_NAME $BROWNFIELD_CLUSTER_NODES                  
            ;;
        set-contexts)
            scripts/k8s-handler.sh set-context $STAGE_CLUSTER_PROVIDER $STAGE_CLUSTER_NAME
            scripts/k8s-handler.sh set-context $PROD_CLUSTER_PROVIDER $PROD_CLUSTER_NAME
            scripts/k8s-handler.sh set-context $BROWNFIELD_CLUSTER_PROVIDER $BROWNFIELD_CLUSTER_NAME
            ;;
        delete-clusters)
            scripts/k8s-handler.sh delete $STAGE_CLUSTER_NAME $STAGE_CLUSTER_PROVIDER \
            & scripts/k8s-handler.sh delete $PROD_CLUSTER_NAME $PROD_CLUSTER_PROVIDER \
            & scripts/k8s-handler.sh delete $BROWNFIELD_CLUSTER_NAME $BROWNFIELD_CLUSTER_PROVIDER
            delete-tmc-clusters
            ;;
        install-demo)
            install-stage-cluster
            install-prod-cluster
            update-multi-cluster-access
            add-brownfield-apis
            attach-tmc-clusters
            ;;
        esac
    }
   

#################### main ##########################


case $1 in
create-clusters)
    innerloop-handler create-clusters & outerloop-handler create-clusters
    ;;
install-demo)
    innerloop-handler set-contexts
    outerloop-handler set-contexts
    innerloop-handler install-demo
    outerloop-handler install-demo
    ;;
delete-all)
    scripts/dektecho.sh prompt  "Are you sure you want to delete all clusters?" && [ $? -eq 0 ] || exit
    ./demo.sh besad
    innerloop-handler delete-clusters & outerloop-handler delete-clusters
    kubectl config delete-context $VIEW_CLUSTER_NAME
    kubectl config delete-context $DEV_CLUSTER_NAME
    kubectl config delete-context $STAGE_CLUSTER_NAME
    kubectl config delete-context $PROD_CLUSTER_NAME
    kubectl config delete-context $BROWNFIELD_CLUSTER_NAME
    ;;
runme)
    $2 $3 $4
    ;;
*)
    incorrect-usage
    ;;
esac