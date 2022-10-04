#!/usr/bin/env bash

#################### configs ################
    #clusters
    DEV_CLUSTER_NAME=$(yq .dev-cluster.name .config/demo-values.yaml)
    DEV_CLUSTER_PROVIDER=$(yq .dev-cluster.provider .config/demo-values.yaml)
    DEV_CLUSTER_NODES=$(yq .dev-cluster.nodes .config/demo-values.yaml)
    STAGE_CLUSTER_NAME=$(yq .stage-cluster.name .config/demo-values.yaml)
    STAGE_CLUSTER_PROVIDER=$(yq .stage-cluster.provider .config/demo-values.yaml)
    STAGE_CLUSTER_NODES=$(yq .stage-cluster.nodes .config/demo-values.yaml)
    PROD_CLUSTER_NAME=$(yq .prod-cluster.name .config/demo-values.yaml)
    PROD_CLUSTER_PROVIDER=$(yq .prod-cluster.provider .config/demo-values.yaml)
    PROD_CLUSTER_NODES=$(yq .prod-cluster.nodes .config/demo-values.yaml)
    VIEW_CLUSTER_NAME=$(yq .view-cluster.name .config/demo-values.yaml)
    VIEW_CLUSTER_PROVIDER=$(yq .view-cluster.provider .config/demo-values.yaml)
    VIEW_CLUSTER_NODES=$(yq .view-cluster.nodes .config/demo-values.yaml)
    BROWNFIELD_CLUSTER_NAME=$(yq .brownfield-cluster.name .config/demo-values.yaml)
    BROWNFIELD_CLUSTER_PROVIDER=$(yq .brownfield-cluster.provider .config/demo-values.yaml)
    BROWNFIELD_CLUSTER_NODES=$(yq .brownfield-cluster.nodes .config/demo-values.yaml)

    #image registry
    PRIVATE_REPO_SERVER=$(yq .ootb_supply_chain_basic.registry.server .config/tap-profiles/tap-iterate.yaml)
    PRIVATE_REPO_USER=$(yq .buildservice.kp_default_repository_username .config/tap-profiles/tap-iterate.yaml)
    PRIVATE_REPO_PASSWORD=$(yq .buildservice.kp_default_repository_password .config/tap-profiles/tap-iterate.yaml)
    SYSTEM_REPO=$(yq .tap.systemRepo .config/demo-values.yaml)
    #tap
    TANZU_NETWORK_USER=$(yq .buildservice.tanzunet_username .config/tap-profiles/tap-iterate.yaml)
    TANZU_NETWORK_PASSWORD=$(yq .buildservice.tanzunet_password .config/tap-profiles/tap-iterate.yaml)
    TAP_VERSION=$(yq .tap.version .config/demo-values.yaml)
    CARVEL_BUNDLE=$(yq .tap.carvel_bundle .config/demo-values.yaml)
    SNYK_VERSION=$(yq .tap.snyk_version .config/demo-values.yaml)
    SERVICE_BINDING_VERSION=$(yq .tap.service_binding_version .config/demo-values.yaml)
    #apps-namespaces
    DEV_NAMESPACE=$(yq .apps-namespaces.dev .config/demo-values.yaml)
    TEAM_NAMESPACE=$(yq .apps-namespaces.team .config/demo-values.yaml)
    STAGEPROD_NAMESPACE=$(yq .apps-namespaces.stageProd .config/demo-values.yaml)
    #domains
    SYSTEM_SUB_DOMAIN=$(yq .shared.ingress_domain .config/tap-profiles/tap-view.yaml | cut -d'.' -f 1)
    DEV_SUB_DOMAIN=$(yq .shared.ingress_domain .config/tap-profiles/tap-iterate.yaml | cut -d'.' -f 1)
    RUN_SUB_DOMAIN=$(yq .shared.ingress_domain .config/tap-profiles/tap-run.yaml | cut -d'.' -f 1)
    #misc 
    RDS_PROFILE=$(yq .data-services.rdsProfile .config/demo-values.yaml)       
    GW_INSTALL_DIR=$(yq .apis.scgwInstallDirectory .config/demo-values.yaml)
    MY_TMC_API_TOKEN=$(yq .tmc.apiToken .config/demo-values.yaml)

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

        scripts/dektecho.sh status "Adding RabbitMQ and Postgres in team configurations"
        add-rabbitmq-team
        add-postgres-team

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
        
        scripts/dektecho.sh status "Adding custom supply chains"
        kubectl apply -f .config/supply-chains/dekt-src-scan-config.yaml
        kubectl apply -f .config/supply-chains/dekt-src-test-scan-api-config.yaml
        kubectl apply -f .config/supply-chains/tekton-pipeline.yaml -n $STAGEPROD_NAMESPACE
        kubectl apply -f .config/supply-chains/scan-policy.yaml -n $STAGEPROD_NAMESPACE

        scripts/dektecho.sh status "Adding RabbitMQ and Postgres in stage/prod configurations"
        add-rabbitmq-stageprod
        add-postgres-stageprod

    }
    
    #install-prod-cluster
    install-prod-cluster() {

        scripts/dektecho.sh info "Installing demo components for $PROD_CLUSTER_NAME cluster"

        kubectl config use-context $PROD_CLUSTER_NAME

        scripts/tanzu-handler.sh add-carvel-tools
        
        add-app-rbac $STAGEPROD_NAMESPACE
        
        add-tap-package "tap-run.yaml"

        scripts/dektecho.sh status "Adding RabbitMQ and Postgres in stage/prod configurations"
        add-rabbitmq-stageprod
        add-postgres-stageprod

        scripts/ingress-handler.sh update-tap-dns $RUN_SUB_DOMAIN

    }

    #add-tap-package
    add-tap-package() {

        tap_values_file_name=$1

        scripts/dektecho.sh status "Installing TAP on $(kubectl config current-context) cluster with $tap_values_file_name configs"

        kubectl create ns tap-install
       
        #tanzu secret registry add tap-registry \
        #    --username ${TANZU_NETWORK_USER} --password ${TANZU_NETWORK_PASSWORD} \
        #    --server "registry.tanzu.vmware.com" \
        #    --export-to-all-namespaces --yes --namespace tap-install
        tanzu secret registry add tap-registry \
            --username ${PRIVATE_REPO_USER} --password ${PRIVATE_REPO_PASSWORD} \
           --server $PRIVATE_REPO_SERVER \
           --export-to-all-namespaces --yes --namespace tap-install

        #tanzu package repository add tanzu-tap-repository \
        #    --url registry.tanzu.vmware.com/tanzu-application-platform/tap-packages:$TAP_VERSION \
        #    --namespace tap-install
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

        kubectl apply -f .config/rbac/gitops-creds.yaml -n $appsNamespace
        kubectl apply -f .config/rbac/single-user-access.yaml -n $appsNamespace
    }

    #add-rabbitmq-team
    add-rabbitmq-team() {

        #install RabbitMQ operator
        kubectl apply -f "https://github.com/rabbitmq/cluster-operator/releases/latest/download/cluster-operator.yml"
        
        #configure taznu services toolkit for RabbitMQ
        kubectl apply -f .config/data-services/rabbitmq-cluster-config.yaml -n $TEAM_NAMESPACE
        
        #provision a RabbitMQ single instance
        kubectl apply -f .config/data-services/reading-queue-dev.yaml -n $TEAM_NAMESPACE

        #create a service claim
        tanzu service claim create rabbitmq-claim -n $TEAM_NAMESPACE \
            --resource-name reading-queue \
            --resource-kind RabbitmqCluster \
            --resource-api-version rabbitmq.com/v1beta1
    }

    #add-rabbitmq-stageprod
    add-rabbitmq-stageprod() {

        #install RabbitMQ operator
        kubectl apply -f "https://github.com/rabbitmq/cluster-operator/releases/latest/download/cluster-operator.yml"
        
        #configure taznu services toolkit for RabbitMQ
        kubectl apply -f .config/data-services/rabbitmq-cluster-config.yaml -n $STAGEPROD_NAMESPACE
        
        #provision a RabbitMQ HA instance
        kubectl apply -f .config/data-services/reading-queue-prod.yaml -n $STAGEPROD_NAMESPACE

        #create a service claim
        tanzu service claim create rabbitmq-claim -n $STAGEPROD_NAMESPACE \
            --resource-name reading-queue \
            --resource-kind RabbitmqCluster \
            --resource-api-version rabbitmq.com/v1beta1
    }

    #add-posgtres-team
    add-postgres-team() {

        #Direct secret to a pre-provisioned Azure PostgresSQL named inventory-db
        kubectl apply -f .config/data-services/inventory-db-dev.yaml -n $TEAM_NAMESPACE
        
        #create a service claim for inventory-db
        tanzu service claim create postgres-claim -n $TEAM_NAMESPACE \
            --resource-name inventory-db \
            --resource-kind Secret \
            --resource-api-version v1 
    }

    #add-posgtres-stageprod
    add-postgres-stageprod() {

        
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

        kubectl apply -f .config/data-services/inventory-db-prod.yaml -n $STAGEPROD_NAMESPACE

        #create a service claim for inventory-db
        tanzu service claim create postgres-claim -n $STAGEPROD_NAMESPACE \
            --resource-name inventory-db \
            --resource-kind Secret \
            --resource-api-version v1 
    }
    
    #update-store-secrets
    update-store-secrets() {

        export storeCert=$(kubectl get secret -n metadata-store ingress-cert -o json | jq -r ".data.\"ca.crt\"")
        export storeToken=$(kubectl get secrets metadata-store-read-write-client -n metadata-store -o jsonpath="{.data.token}" | base64 -d)
        export storeProxyAuthHeader="Bearer $storeToken"

        yq '.data."ca.crt"= env(storeCert)' .config/rbac/store-ca-cert.yaml -i
        yq '.stringData.auth_token= env(storeToken)' .config/rbac/store-auth-token.yaml -i
        yq '.tap_gui.app_config.proxy."/metadata-store".headers.Authorization= env(storeProxyAuthHeader)' .config/tap-profiles/tap-view.yaml -i
    }
    
    #add-metadata-store-secrets 
    add-metadata-store-secrets() {

        scripts/dektecho.sh status "Adding metadata-store-secrets to access remote Store"
        kubectl create ns metadata-store-secrets
        kubectl apply -f .config/rbac/store-auth-token.yaml -n metadata-store-secrets
        kubectl apply -f .config/rbac/store-ca-cert.yaml -n metadata-store-secrets
        kubectl apply -f .config/rbac/store-secrets-export.yaml -n metadata-store-secrets
    }

    #install-snyk
    install-snyk() {

        scripts/dektecho.sh status "Add Snyk for image scanning "
        
        kubectl apply -f .config/rbac/snyk-creds.yaml -n $STAGEPROD_NAMESPACE

        tanzu package install snyk-scanner \
            --package-name snyk.scanning.apps.tanzu.vmware.com \
            --version $SNYK_VERSION \
            --namespace tap-install \
            --values-file .config/supply-chains/snyk-values.yaml

            #1.0.0-beta.2

    }
    #update-multi-cluster-access
    update-multi-cluster-access() {
        
        scripts/dektecho.sh status "Updating Backstage access to dev,stage & prod clusters"

        #configure GUI on view cluster to access dev cluster
        kubectl config use-context $DEV_CLUSTER_NAME
        kubectl apply -f .config/rbac/reader-accounts.yaml
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
        kubectl apply -f .config/rbac/reader-accounts.yaml
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
        kubectl apply -f .config/rbac/reader-accounts.yaml
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
        kubectl create secret docker-registry spring-cloud-gateway-image-pull-secret \
            --docker-server=$PRIVATE_REPO_SERVER \
            --docker-username=$PRIVATE_REPO_USER \
            --docker-password=$PRIVATE_REPO_PASSWORD \
            --namespace scgw-system
        $GW_INSTALL_DIR/scripts/install-spring-cloud-gateway.sh --namespace scgw-system
        
        kubectl create ns $brownfield_apis_ns
        kustomize build brownfield-apis | kubectl apply -f -

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

    #relocate-images
    relocate-gw-images() {

        echo "Make sure docker deamon is running..."
        read
        
        docker login $PRIVATE_REPO_SERVER -u $PRIVATE_REPO_USER -p $PRIVATE_REPO_PASSWORD
        
        $GW_INSTALL_DIR/scripts/relocate-images.sh $PRIVATE_REPO_SERVER/$SYSTEM_REPO
    }

    #relocate-tds-images
    relocate-tds-images() {

        #docker login $PRIVATE_REPO_SERVER -u $PRIVATE_REPO_USER -p $PRIVATE_REPO_PASSWORD
        #docker login registry.tanzu.vmware.com -u $TANZU_NETWORK_USER -p $TANZU_NETWORK_PASSWORD
        
        #imgpkg copy -b registry.tanzu.vmware.com/packages-for-vmware-tanzu-data-services/tds-packages:1.0.0 \
        #    --to-repo $PRIVATE_REPO_SERVER/$SYSTEM_REPO/tds-packages

        tanzu package repository add tanzu-data-services-repository --url $PRIVATE_REPO_SERVER/$SYSTEM_REPO/tds-packages:1.0.0 -n tap-install
    }

    #attach TMC clusters
    attach-tmc-clusters() {

        scripts/dektecho.sh info "Attaching TMC clusters"

        export TMC_API_TOKEN=$MY_TMC_API_TOKEN
        tmc login -n dekt-tmc-login -c

        kubectl config use-context $VIEW_CLUSTER_NAME
        tmc cluster attach -n $VIEW_CLUSTER_NAME -g dekt
        kubectl apply -f k8s-attach-manifest.yaml
        rm -f k8s-attach-manifest.yaml

        kubectl config use-context $DEV_CLUSTER_NAME
        tmc cluster attach -n $DEV_CLUSTER_NAME -g dekt
        kubectl apply -f k8s-attach-manifest.yaml 

        rm -f k8s-attach-manifest.yaml

        kubectl config use-context $STAGE_CLUSTER_NAME
        tmc cluster attach -n $STAGE_CLUSTER_NAME -g dekt
        kubectl apply -f k8s-attach-manifest.yaml
        rm -f k8s-attach-manifest.yaml

        kubectl config use-context $PROD_CLUSTER_NAME
        tmc cluster attach -n $PROD_CLUSTER_NAME -g dekt
        kubectl apply -f k8s-attach-manifest.yaml
        rm -f k8s-attach-manifest.yaml

        kubectl config use-context $BROWNFIELD_CLUSTER_NAME
        tmc cluster attach -n $BROWNFIELD_CLUSTER_NAME -g dekt
        kubectl apply -f k8s-attach-manifest.yaml
        rm -f k8s-attach-manifest.yaml

    }

    #delete-tmc-cluster
    delete-tmc-clusters() {

        export TMC_API_TOKEN=$MY_TMC_API_TOKEN
        tmc login -n dekt-tmc-login -c

        tmc cluster delete $VIEW_CLUSTER_NAME -f -m attached -p attached
        tmc cluster delete $DEV_CLUSTER_NAME -f -m attached -p attached
        tmc cluster delete $STAGE_CLUSTER_NAME -f -m attached -p attached
        tmc cluster delete $PROD_CLUSTER_NAME -f -m attached -p attached
        tmc cluster delete $BROWNFIELD_CLUSTER_NAME -f -m attached -p attached
    }

    #relocate-tap-images
    relocate-tap-images() {

        scripts/dektecho.sh prompt "Make sure docker deamon is running before proceeding"
        
        docker login $PRIVATE_REPO_SERVER -u $PRIVATE_REPO_USER -p $PRIVATE_REPO_PASSWORD

        docker login registry.tanzu.vmware.com -u $TANZU_NETWORK_USER -p $TANZU_NETWORK_PASSWORD
        
        export IMGPKG_REGISTRY_HOSTNAME=$PRIVATE_REPO_SERVER
        export IMGPKG_REGISTRY_USERNAME=$PRIVATE_REPO_USER
        export IMGPKG_REGISTRY_PASSWORD=$PRIVATE_REPO_PASSWORD
        export TAP_VERSION=$TAP_VERSION
    

        imgpkg copy \
            --bundle registry.tanzu.vmware.com/tanzu-application-platform/tap-packages:$TAP_VERSION \
            --to-tar tap-packages-$TAP_VERSION.tar \
            --include-non-distributable-layers

        imgpkg copy \
            --tar tap-packages-$TAP_VERSION.tar \
            --to-repo $IMGPKG_REGISTRY_HOSTNAME/$SYSTEM_REPO/tap-packages \
            --include-non-distributable-layers
            
    }
  
    #delete-demo
    delete-demo() {

        kubectl config use-context $1

        tanzu package installed delete tap -n tap-install -y

        tanzu package installed delete snyk-scanner -n tap-install -y

        kubectl delete -f .config/supply-chains -n $STAGEPROD_NAMESPACE
        kubectl delete -f .config/supply-chains -n $TEAM_NAMESPACE

        kubectl delete ns tap-gui
        kubectl delete ns metadata-store-secrets
        kubectl delete ns $STAGEPROD_NAMESPACE
        kubectl delete ns $DEV_NAMESPACE
        kubectl delete ns $TEAM_NAMESPACE
        kubectl delete ns rabbitmq-system
        kubectl delete ns secretgen-controller
        kubectl delete ns tanzu-package-repo-global
        kubectl delete ns tanzu-cluster-essentials
        kubectl delete ns kapp-controller 
        kubectl delete ns tap-install

    }
    
    #incorrect usage
    incorrect-usage() {
        
        scripts/dektecho.sh err "Incorrect usage. Please specify one of the following: "
        
        echo "  init-all"
        echo 
        echo "  uninstall-demo"
        echo
        echo "  delete-all"
        echo
        echo "  relocate-tap-images"
        echo
        echo "  runme [ function-name ]"
        echo
        exit
    }

    #test-all-clusters
    test-all-clusters() {
        scripts/k8s-handler.sh test-cluster $VIEW_CLUSTER_NAME
        echo
        scripts/dektecho.sh prompt  "Verify that cluster $VIEW_CLUSTER_NAME was created succefully. Continue?" && [ $? -eq 0 ] || exit
        scripts/k8s-handler.sh test-cluster $DEV_CLUSTER_NAME
        echo
        scripts/dektecho.sh prompt  "Verify that cluster $DEV_CLUSTER_NAME was created succefully. Continue?" && [ $? -eq 0 ] || exit
        scripts/k8s-handler.sh test-cluster $STAGE_CLUSTER_NAME
        echo
        scripts/dektecho.sh prompt  "Verify that cluster $STAGE_CLUSTER_NAME was created succefully. Continue?" && [ $? -eq 0 ] || exit
        scripts/k8s-handler.sh test-cluster $PROD_CLUSTER_NAME
        echo
        scripts/dektecho.sh prompt  "Verify that cluster $PROD_CLUSTER_NAME was created succefully. Continue?" && [ $? -eq 0 ] || exit
        scripts/k8s-handler.sh test-cluster $BROWNFIELD_CLUSTER_NAME
        echo
        scripts/dektecho.sh prompt  "Verify that cluster $BROWNFIELD_CLUSTER_NAME was created succefully. Continue?" && [ $? -eq 0 ] || exit
    }

    #innerloop-handler
    innerloop-handler() {

        case $1 in
        create-clusters) 
            scripts/k8s-handler.sh create $VIEW_CLUSTER_PROVIDER $VIEW_CLUSTER_NAME $VIEW_CLUSTER_NODES
            scripts/k8s-handler.sh create $DEV_CLUSTER_PROVIDER $DEV_CLUSTER_NAME $DEV_CLUSTER_NODES
            ;;
        delete-clusters)
            scripts/k8s-handler.sh delete $VIEW_CLUSTER_PROVIDER $VIEW_CLUSTER_NAME
            scripts/k8s-handler.sh delete $DEV_CLUSTER_PROVIDER $DEV_CLUSTER_NAME
            ;;
        install-demo)
            install-view-cluster
            install-dev-cluster 
            ;;
        uninstall-demo)
            delete-demo $VIEW_CLUSTER_NAME
            delete-demo $DEV_CLUSTER_NAME
            ;;
        esac
    }

    #outerloop-handler
    outerloop-handler() {

        case $1 in
        create-clusters) 
            scripts/k8s-handler.sh create $STAGE_CLUSTER_PROVIDER $STAGE_CLUSTER_NAME $STAGE_CLUSTER_NODES          
            scripts/k8s-handler.sh create $PROD_CLUSTER_PROVIDER $PROD_CLUSTER_NAME $PROD_CLUSTER_NODES 
            scripts/k8s-handler.sh create $BROWNFIELD_CLUSTER_PROVIDER $BROWNFIELD_CLUSTER_NAME $BROWNFIELD_CLUSTER_NODES                  
            ;;
        delete-clusters)
            scripts/k8s-handler.sh delete $STAGE_CLUSTER_PROVIDER $STAGE_CLUSTER_NAME
            scripts/k8s-handler.sh delete $PROD_CLUSTER_PROVIDER $PROD_CLUSTER_NAME
            scripts/k8s-handler.sh delete $BROWNFIELD_CLUSTER_PROVIDER $BROWNFIELD_CLUSTER_NAME
            delete-tmc-clusters
            ;;
        install-demo)
            install-stage-cluster
            install-prod-cluster
            update-multi-cluster-access
            add-brownfield-apis
            attach-tmc-clusters
            ;;
        uninstall-demo)
            delete-demo $STAGE_CLUSTER_NAME
            delete-demo $PROD_CLUSTER_NAME
            ;;
        esac
    }
   

#################### main ##########################

case $1 in
init-all)    
    innerloop-handler create-clusters
    outerloop-handler create-clusters
    test-all-clusters
    scripts/dektecho.sh prompt  "Continue to install demo components" && [ $? -eq 0 ] || exit
    innerloop-handler install-demo
    outerloop-handler install-demo
    ;;
delete-all)
    scripts/dektecho.sh prompt  "Are you sure you want to delete all clusters?" && [ $? -eq 0 ] || exit
    ./dekt-DevSecOps.sh besad
    innerloop-handler delete-clusters
    outerloop-handler delete-clusters
    rm -f /Users/dekt/.kube/config
    ;;
uninstall-demo)
    scripts/dektecho.sh prompt  "Are you sure you want to uninstall all demo components?" && [ $? -eq 0 ] || exit
    ./dekt-DevSecOps.sh toggle-dog sad
    innerloop-handler uninstall-demo
    outerloop-handler uninstall-demo
    ;;
relocate-tap-images)
    relocate-tap-images
    ;;
runme)
    $2 $3 $4
    ;;
*)
    incorrect-usage
    ;;
esac
