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
    HERITAGE_CLUSTER_NAME=$(yq .heritage-cluster.name .config/demo-values.yaml)
    HERITAGE_CLUSTER_PROVIDER=$(yq .heritage-cluster.provider .config/demo-values.yaml)
    HERITAGE_CLUSTER_NODES=$(yq .heritage-cluster.nodes .config/demo-values.yaml)

    #image registry
    PRIVATE_REPO_SERVER=$(yq .ootb_supply_chain_basic.registry.server .config/tap-iterate.yaml)
    PRIVATE_REPO_USER=$(yq .buildservice.kp_default_repository_username .config/tap-iterate.yaml)
    PRIVATE_REPO_PASSWORD=$(yq .buildservice.kp_default_repository_password .config/tap-iterate.yaml)
    SYSTEM_REPO=$(yq .tap.systemRepo .config/demo-values.yaml)
    #tap
    TANZU_NETWORK_USER=$(yq .buildservice.tanzunet_username .config/tap-iterate.yaml)
    TANZU_NETWORK_PASSWORD=$(yq .buildservice.tanzunet_password .config/tap-iterate.yaml)
    TAP_VERSION=$(yq .tap.version .config/demo-values.yaml)
    APPS_NAMESPACE=$(yq .tap.appNamespace .config/demo-values.yaml)
    #domains
    SYSTEM_SUB_DOMAIN=$(yq .tap_gui.ingressDomain .config/tap-view.yaml | cut -d'.' -f 1)
    DEV_SUB_DOMAIN=$(yq .cnrs.domain_name .config/tap-iterate.yaml | cut -d'.' -f 1)
    RUN_SUB_DOMAIN=$(yq .cnrs.domain_name .config/tap-run.yaml | cut -d'.' -f 1)
    #misc        
    GW_INSTALL_DIR=$(yq .apis.scgwInstallDirectory .config/demo-values.yaml)

#################### functions ################

    #install-all
    install-all() {

        install-tap $VIEW_CLUSTER_NAME "tap-view.yaml"

        install-tap $DEV_CLUSTER_NAME "tap-iterate.yaml"
        
        install-tap $STAGE_CLUSTER_NAME "tap-build.yaml"
        
        install-tap $PROD_CLUSTER_NAME "tap-run.yaml"
        
        post-install-configs

        #setup-scanning-rbac

        provision-data-services

        update-dns-records

        update-multi-cluster-views

    }

    #install-tap
    install-tap () {

        tap_cluster_name=$1
        tap_values_file_name=$2

        scripts/dektecho.sh info "Installing TAP on $tap_cluster_name cluster with $tap_values_file_name configs"
        
        kubectl config use-context $tap_cluster_name
        kubectl create ns tap-install
       
        tanzu secret registry add tap-registry \
            --username ${TANZU_NETWORK_USER} --password ${TANZU_NETWORK_PASSWORD} \
            --server "registry.tanzu.vmware.com" \
            --export-to-all-namespaces --yes --namespace tap-install

        tanzu package repository add tanzu-tap-repository \
            --url registry.tanzu.vmware.com/tanzu-application-platform/tap-packages:$TAP_VERSION \
            --namespace tap-install

        tanzu package install tap -p tap.tanzu.vmware.com -v $TAP_VERSION \
            --values-file .config/$tap_values_file_name \
            --namespace tap-install
    }

    #post-install-configs
    post-install-configs () {

        scripts/dektecho.sh info "Running post install configurations for $VIEW_CLUSTER_NAME cluster"
        kubectl config use-context $VIEW_CLUSTER_NAME
        kustomize build accelerators | kubectl apply -f -

        scripts/dektecho.sh info "Running post install configurations for $DEV_CLUSTER_NAME cluster"
        kubectl config use-context $DEV_CLUSTER_NAME
        setup-apps-namespace
        kubectl apply -f .config/disable-scale2zero.yaml
        kubectl apply -f .config/dekt-dev-supplychain.yaml
        kubectl apply -f .config/tekton-pipeline.yaml -n $APPS_NAMESPACE

        scripts/dektecho.sh info "Running post install configurations for $STAGE_CLUSTER_NAME cluster"
        kubectl config use-context $STAGE_CLUSTER_NAME
        setup-apps-namespace
        kubectl apply -f .config/dekt-build-supplychain.yaml
        kubectl apply -f .config/scan-policy.yaml -n $APPS_NAMESPACE
        kubectl apply -f .config/tekton-pipeline.yaml -n $APPS_NAMESPACE

        scripts/dektecho.sh info "Running post install configurations for $PROD_CLUSTER_NAME cluster"
        kubectl config use-context $PROD_CLUSTER_NAME
        kubectl apply -f .config/disable-scale2zero.yaml
        setup-apps-namespace
    }

    #setup-apps-namespace
    setup-apps-namespace() {
        
        kubectl create ns $APPS_NAMESPACE
        
        tanzu secret registry add registry-credentials --server $PRIVATE_REPO_SERVER --username $PRIVATE_REPO_USER --password $PRIVATE_REPO_PASSWORD -n $APPS_NAMESPACE
        
        kubectl apply -f .config/supplychain-rbac.yaml -n $APPS_NAMESPACE
    }

    #update-dns-records
    update-dns-records() {

        scripts/dektecho.sh info "Updating DNS records"

        kubectl config use-context $VIEW_CLUSTER_NAME
        scripts/ingress-handler.sh update-tap-dns $SYSTEM_SUB_DOMAIN

        kubectl config use-context $DEV_CLUSTER_NAME
        scripts/ingress-handler.sh update-tap-dns $DEV_SUB_DOMAIN

        kubectl config use-context $PROD_CLUSTER_NAME
        scripts/ingress-handler.sh update-tap-dns $RUN_SUB_DOMAIN
    }
    
    #update-multi-cluster-views
    update-multi-cluster-views() {

        scripts/dektecho.sh info "Configure TAP Workloads GUI plugin to support multi-clusters"
          
        kubectl config use-context $DEV_CLUSTER_NAME
        kubectl apply -f .config/tap-gui-viewer-sa-rbac.yaml
        export devClusterUrl=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
        export devClusterToken=$(kubectl -n tap-gui get secret $(kubectl -n tap-gui get sa tap-gui-viewer -o=json \
        | jq -r '.secrets[0].name') -o=json \
        | jq -r '.data["token"]' \
        | base64 --decode)

        yq '.tap_gui.app_config.kubernetes.clusterLocatorMethods.[0].clusters.[0].url = env(devClusterUrl)' .config/tap-view.yaml -i
        yq '.tap_gui.app_config.kubernetes.clusterLocatorMethods.[0].clusters.[0].serviceAccountToken = env(devClusterToken)' .config/tap-view.yaml -i

        kubectl config use-context $STAGE_CLUSTER_NAME
        kubectl apply -f .config/tap-gui-viewer-sa-rbac.yaml
        export stageClusterUrl=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
        export stageClusterToken=$(kubectl -n tap-gui get secret $(kubectl -n tap-gui get sa tap-gui-viewer -o=json \
        | jq -r '.secrets[0].name') -o=json \
        | jq -r '.data["token"]' \
        | base64 --decode)

        yq '.tap_gui.app_config.kubernetes.clusterLocatorMethods.[0].clusters.[1].url = env(stageClusterUrl)' .config/tap-view.yaml -i
        yq '.tap_gui.app_config.kubernetes.clusterLocatorMethods.[0].clusters.[1].serviceAccountToken = env(stageClusterToken)' .config/tap-view.yaml -i


        kubectl config use-context $PROD_CLUSTER_NAME
        kubectl apply -f .config/tap-gui-viewer-sa-rbac.yaml
        export prodClusterUrl=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
        export prodClusterToken=$(kubectl -n tap-gui get secret $(kubectl -n tap-gui get sa tap-gui-viewer -o=json \
        | jq -r '.secrets[0].name') -o=json \
        | jq -r '.data["token"]' \
        | base64 --decode)

        yq '.tap_gui.app_config.kubernetes.clusterLocatorMethods.[0].clusters.[2].url = env(prodClusterUrl)' .config/tap-view.yaml -i
        yq '.tap_gui.app_config.kubernetes.clusterLocatorMethods.[0].clusters.[2].serviceAccountToken = env(prodClusterToken)' .config/tap-view.yaml -i

        kubectl config use-context $VIEW_CLUSTER_NAME
        tanzu package installed update tap --package-name tap.tanzu.vmware.com --version $TAP_VERSION -n tap-install -f .config/tap-view.yaml

    } 
 

    #add-data-services
    provision-data-services() {

        scripts/dektecho.sh info "Provision data services"

        kubectl config use-context $DEV_CLUSTER_NAME
        kapp -y deploy --app rmq-operator --file https://github.com/rabbitmq/cluster-operator/releases/download/v1.9.0/cluster-operator.yml
        kubectl apply -f .config/rabbitmq-cluster-config.yaml -n $APPS_NAMESPACE
        kubectl apply -f .config/reading-rabbitmq-dev.yaml -n $APPS_NAMESPACE

        kubectl config use-context $STAGE_CLUSTER_NAME
        kapp -y deploy --app rmq-operator --file https://github.com/rabbitmq/cluster-operator/releases/download/v1.9.0/cluster-operator.yml
        kubectl apply -f .config/rabbitmq-cluster-config.yaml -n $APPS_NAMESPACE
        kubectl apply -f .config/reading-rabbitmq-prod.yaml -n $APPS_NAMESPACE

        kubectl config use-context $PROD_CLUSTER_NAME
        kapp -y deploy --app rmq-operator --file https://github.com/rabbitmq/cluster-operator/releases/download/v1.9.0/cluster-operator.yml
        kubectl apply -f .config/rabbitmq-cluster-config.yaml -n $APPS_NAMESPACE
        kubectl apply -f .config/reading-rabbitmq-prod.yaml -n $APPS_NAMESPACE
    }

    #add-apis
    add-apis () {

        kubectl create ns scgw-system

        kubectl create secret docker-registry spring-cloud-gateway-image-pull-secret \
            --docker-server=$PRIVATE_REPO_SERVER \
            --docker-username=$PRIVATE_REPO_USER \
            --docker-password=$PRIVATE_REPO_PASSWORD \
            --namespace scgw-system
 
        relocate-gw-images

        $GW_INSTALL_DIR/scripts/install-spring-cloud-gateway.sh --namespace scgw-system

        #brownfield API
        kubectl create ns brownfield-apis
        kubectl create secret generic sso-credentials --from-env-file=.config/sso-creds.txt -n api-portal
        kustomize build brownfield-apis | kubectl apply -f -

        scripts/ingress-handler.sh add-brownfield-apis $SYSTEM_SUB_DOMAIN
    }

    #relocate-images
    relocate-gw-images() {

        echo "Make sure docker deamon is running..."
        read
        
        docker login $PRIVATE_REPO_SERVER -u $PRIVATE_REPO_USER -p $PRIVATE_REPO_PASSWORD
        
        $GW_INSTALL_DIR/scripts/relocate-images.sh $PRIVATE_REPO_SERVER/$SYSTEM_REPO
    }

    #relocate-tap-images
    relocate-tap-images() {

        scripts/dektecho.sh err "Make sure docker deamon is running..."
        read
        
        docker login $PRIVATE_REPO_SERVER -u $PRIVATE_REPO_USER -p $PRIVATE_REPO_PASSWORD

        docker login registry.tanzu.vmware.com -u $TANZU_NETWORK_USER -p $TANZU_NETWORK_PASSWORD
        
        export INSTALL_REGISTRY_USERNAME=$PRIVATE_REPO_USER
        export INSTALL_REGISTRY_PASSWORD=$PRIVATE_REPO_PASSWORD
        export INSTALL_REGISTRY_HOSTNAME=$PRIVATE_REPO_SERVER
        export TAP_VERSION=$TAP_VERSION

        imgpkg copy -b registry.tanzu.vmware.com/tanzu-application-platform/tap-packages:$TAP_VERSION \
            --to-repo ${INSTALL_REGISTRY_HOSTNAME}/$SYSTEM_REPO/tap-packages

    }
    
    #install-gui-dev
    install-gui-dev() {

        kubectl apply -f .config/tap-gui-dev-package.yaml

        export INSTALL_REGISTRY_HOSTNAME=dev.registry.tanzu.vmware.com
        export INSTALL_REGISTRY_USERNAME=$TANZU_NETWORK_USER
        export INSTALL_REGISTRY_PASSWORD=$TANZU_NETWORK_PASSWORD

        tanzu secret registry add dev-registry --username ${INSTALL_REGISTRY_USERNAME} --password ${INSTALL_REGISTRY_PASSWORD} --server ${INSTALL_REGISTRY_HOSTNAME} --export-to-all-namespaces --yes --namespace tap-install

        tanzu package install tap-gui -p tap-gui.tanzu.vmware.com -v 1.1.0-build.1 --values-file .config/tap-gui-values.yaml -n tap-install

        #scripts/ingress-handler.sh gui-dev
        kubectl port-forward service/server 7000 -n tap-gui

        
       
    }
    
    #incorrect usage
    incorrect-usage() {
        
        scripts/dektecho.sh err "Incorrect usage. Please specify one of the following: "
        
        echo "  init"
        echo       
        echo "  brownfield"
        echo
        echo "  dev"
        echo
        echo "  delete"
        echo
        echo "  relocate-tap-images"
        echo
        echo "  runme [ function-name ]"
        echo
        exit
    }

#################### main ##########################

case $1 in
init)
    scripts/k8s-handler.sh create $VIEW_CLUSTER_PROVIDER $VIEW_CLUSTER_NAME $VIEW_CLUSTER_NODES
    scripts/tanzu-handler.sh add-carvel-tools
    scripts/k8s-handler.sh create $DEV_CLUSTER_PROVIDER $DEV_CLUSTER_NAME $DEV_CLUSTER_NODES
    scripts/tanzu-handler.sh add-carvel-tools
    scripts/k8s-handler.sh create $STAGE_CLUSTER_PROVIDER $STAGE_CLUSTER_NAME $STAGE_CLUSTER_NODES
    scripts/tanzu-handler.sh add-carvel-tools
    scripts/k8s-handler.sh create $PROD_CLUSTER_PROVIDER $PROD_CLUSTER_NAME $PROD_CLUSTER_NODES
    scripts/tanzu-handler.sh add-carvel-tools
    install-all
    ;;
delete)
    echo "!!!Are you sure you want to delete all clusters?"
    read
    ./demo-helper.sh cleanup-helper
    scripts/k8s-handler.sh delete $DEV_CLUSTER_PROVIDER $DEV_CLUSTER_NAME
    scripts/k8s-handler.sh delete $STAGE_CLUSTER_PROVIDER $STAGE_CLUSTER_NAME
    scripts/k8s-handler.sh delete $PROD_CLUSTER_PROVIDER $PROD_CLUSTER_NAME
    scripts/k8s-handler.sh delete $HERITAGE_CLUSTER_PROVIDER $HERITAGE_CLUSTER_NAME
    ;;
brownfield)
    scripts/k8s-handler.sh create $HERITAGE_CLUSTER_PROVIDER $HERITAGE_CLUSTER_NAME $HERITAGE_CLUSTER_NODES
    kubectl create ns brownfield-apis
    ;;
dev)
    install-gui-dev
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