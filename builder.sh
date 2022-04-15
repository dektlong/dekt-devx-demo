#!/usr/bin/env bash

#################### configs #######################

    source .config/config-values.env
    PRIVATE_REPO=$(yq .ootb_supply_chain_basic.registry.server .config/tap-values-full.yaml)
    PRIVATE_REPO_USER=$(yq .buildservice.kp_default_repository_username .config/tap-values-full.yaml)
    PRIVATE_REPO_PASSWORD=$(yq .buildservice.kp_default_repository_password .config/tap-values-full.yaml)
    TANZU_NETWORK_USER=$(yq .buildservice.tanzunet_username .config/tap-values-full.yaml)
    TANZU_NETWORK_PASSWORD=$(yq .buildservice.tanzunet_password .config/tap-values-full.yaml)
    SYSTEM_SUB_DOMAIN=$(yq .tap_gui.ingressDomain .config/tap-values-full.yaml | cut -d'.' -f 1)
    DEV_SUB_DOMAIN=$(yq .cnrs.domain_name .config/tap-values-full.yaml | cut -d'.' -f 1)
    RUN_SUB_DOMAIN=$(yq .cnrs.domain_name .config/tap-values-run.yaml | cut -d'.' -f 1)
    
    
    GATEWAY_NS="scgw-system"
    BROWNFIELD_NS="brownfield-apis"
    
#################### installers ################

    #install-all-clusters
    install-all() {

        install-full

        install-build

        install-run

        add-multi-cluster-views

    }

    #install-full
    install-full() {

        echo
        echo "==========================================================="
        echo "Installing TAP full profile on $FULL_CLUSTER_NAME cluster ..."
        echo "==========================================================="
        echo

        kubectl config use-context $FULL_CLUSTER_NAME
        
        install-tap "tap-values-full.yaml"

        setup-app-ns

        add-custom-sc

        scripts/ingress-handler.sh update-tap-dns $SYSTEM_SUB_DOMAIN
        scripts/ingress-handler.sh update-tap-dns $DEV_SUB_DOMAIN
    }

    #install-build
    install-build() {

        echo
        echo "==========================================================="
        echo "Installing TAP build profile on $BUILD_CLUSTER_NAME cluster ..."
        echo "==========================================================="
        echo
        
        kubectl config use-context $BUILD_CLUSTER_NAME

        install-tap "tap-values-build.yaml"

        setup-app-ns

        #add-custom-sc

     }

    #install-run
    install-run() {

        echo
        echo "==========================================================="
        echo "Installing TAP run profile on $RUN_CLUSTER_NAME cluster ..."
        echo "==========================================================="
        echo
        kubectl config use-context $RUN_CLUSTER_NAME

        install-tap "tap-values-run.yaml"

        setup-app-ns

        scripts/ingress-handler.sh update-tap-dns $RUN_SUB_DOMAIN

    }


    #install-localhost
    install-localhost() {

        install-tap-registry

        tanzu package install tap -p tap.tanzu.vmware.com -v $TAP_VERSION  --values-file .config/tap-values-localhost.yaml-n tap-install

        setup-app-ns

        add-custom-sc

        echo
        echo "update gui LB IP values in tap-values-run. hit any key.."
        read

        tanzu package installed update tap --package-name tap.tanzu.vmware.com --version $TAP_VERSION -n tap-install -f .config/tap-values-localhost.yaml
    }



    #install-tap
    install-tap () {

        tap_values_file_name=$1

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

    #add-multi-cluster-views
    add-multi-cluster-views() {

       echo
       echo "Configure TAP Workloads GUI plugin to support multi-clusters ..."
       echo
       
       kubectl config use-context $BUILD_CLUSTER_NAME
       kubectl apply -f .config/tap-gui-viewer-sa-rbac.yaml
       export buildClusterUrl=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
       export buildClusterToken=$(kubectl -n tap-gui get secret $(kubectl -n tap-gui get sa tap-gui-viewer -o=json \
        | jq -r '.secrets[0].name') -o=json \
        | jq -r '.data["token"]' \
        | base64 --decode)

       yq '.tap_gui.app_config.kubernetes.clusterLocatorMethods.[0].clusters.[0].url = env(buildClusterUrl)' .config/tap-values-full.yaml -i
       yq '.tap_gui.app_config.kubernetes.clusterLocatorMethods.[0].clusters.[0].serviceAccountToken = env(buildClusterToken)' .config/tap-values-full.yaml -i


       kubectl config use-context $FULL_CLUSTER_NAME
       kubectl apply -f .config/tap-gui-viewer-sa-rbac.yaml
       export devClusterUrl=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
       export devClusterToken=$(kubectl -n tap-gui get secret $(kubectl -n tap-gui get sa tap-gui-viewer -o=json \
        | jq -r '.secrets[0].name') -o=json \
        | jq -r '.data["token"]' \
        | base64 --decode)

       yq '.tap_gui.app_config.kubernetes.clusterLocatorMethods.[0].clusters.[1].url = env(devClusterUrl)' .config/tap-values-full.yaml -i
       yq '.tap_gui.app_config.kubernetes.clusterLocatorMethods.[0].clusters.[1].serviceAccountToken = env(devClusterToken)' .config/tap-values-full.yaml -i

       tanzu package installed update tap --package-name tap.tanzu.vmware.com --version $TAP_VERSION -n tap-install -f .config/tap-values-full.yaml

   } 
   
   
    #setup-defaults for apps ns
    setup-app-ns () {
 
        #setup apps namespace
        kubectl create ns $DEMO_APPS_NS
        
        tanzu secret registry add registry-credentials --server $PRIVATE_REPO --username $PRIVATE_REPO_USER --password $PRIVATE_REPO_PASSWORD -n $DEMO_APPS_NS
        kubectl apply -f .config/supplychain-rbac.yaml -n $DEMO_APPS_NS
    }

    add-custom-sc() {
        
        kubectl apply -f .config/disable-scale2zero.yaml

        #accelerators 
        kustomize build accelerators | kubectl apply -f -

        #dekt-path2prod custom supply chain
        kubectl apply -f .config/dekt-path2prod.yaml

        #scan policy
        kubectl apply -f .config/scan-policy.yaml -n $DEMO_APPS_NS

        #testing pipeline
        kubectl apply -f .config/tekton-pipeline.yaml -n $DEMO_APPS_NS

        #rabbitmq 
        kapp -y deploy --app rmq-operator --file https://github.com/rabbitmq/cluster-operator/releases/download/v1.9.0/cluster-operator.yml
        kubectl apply -f .config/rabbitmq-cluster-config.yaml -n $DEMO_APPS_NS
        kubectl apply -f .config/reading-rabbitmq-instance.yaml -n $DEMO_APPS_NS
    }
    
    #add-apis
    add-apis () {

        kubectl create ns $GATEWAY_NS

        kubectl create secret docker-registry spring-cloud-gateway-image-pull-secret \
            --docker-server=$PRIVATE_REPO \
            --docker-username=$PRIVATE_REPO_USER \
            --docker-password=$PRIVATE_REPO_PASSWORD \
            --namespace $GATEWAY_NS
 
        $GW_INSTALL_DIR/scripts/install-spring-cloud-gateway.sh --namespace $GATEWAY_NS

        #brownfield API
        kubectl create ns $BROWNFIELD_NS
        kubectl create secret generic sso-credentials --from-env-file=.config/sso-creds.txt -n api-portal
        kustomize build workloads/brownfield-apis | kubectl apply -f -

        scripts/ingress-handler.sh apis
    }

    #relocate-images
    relocate-gw-images() {

        echo "Make sure docker deamon is running..."
        read
        
        docker login $PRIVATE_REPO -u $PRIVATE_REPO_USER -p $PRIVATE_REPO_PASSWORD
        
        $GW_INSTALL_DIR/scripts/relocate-images.sh $PRIVATE_REPO/$SYSTEM_REPO
    }

    #relocate-tap-images
    relocate-tap-images() {

        echo "Make sure docker deamon is running..."
        read
        
        docker login $PRIVATE_REPO -u $PRIVATE_REPO_USER -p $PRIVATE_REPO_PASSWORD

        docker login registry.tanzu.vmware.com -u $TANZU_NETWORK_USER -p $TANZU_NETWORK_PASSWORD
        
        export INSTALL_REGISTRY_USERNAME=$PRIVATE_REPO_USER
        export INSTALL_REGISTRY_PASSWORD=$PRIVATE_REPO_PASSWORD
        export INSTALL_REGISTRY_HOSTNAME=$PRIVATE_REPO
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
        
        echo
        echo "Incorrect usage. Please specify one of the following: "
        echo
        echo
        echo "  init [ aks / eks / laptop / localhost ]"
        echo
        echo "  apis"
        echo
        echo "  dev"
        echo
        echo "  cleanup [ aks / eks / laptop / localhost ]"
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
    case $2 in
    aks)
        scripts/aks-handler.sh create $FULL_CLUSTER_NAME 3
        scripts/aks-handler.sh create $BUILD_CLUSTER_NAME 2
        scripts/aks-handler.sh create $RUN_CLUSTER_NAME 2
        install-all
        ;;
    eks)
        scripts/eks-handler.sh create $FULL_CLUSTER_NAME 3
        scripts/eks-handler.sh create $BUILD_CLUSTER_NAME 2
        scripts/eks-handler.sh create $RUN_CLUSTER_NAME 2
        install-all
        ;;
    laptop)
        scripts/minikube-handler.sh create
        install-full
        ;;
    localhost)
        scripts/aks-handler.sh create $FULL_CLUSTER_NAME 3
        scripts/aks-handler.sh create $BUILD_CLUSTER_NAME 2
        scripts/aks-handler.sh create $RUN_CLUSTER_NAME 2
        install-localhost
        ;;
    *)
        incorrect-usage
        ;;
    esac
    ;;
cleanup)
    ./demo-helper.sh cleanup-helper
    case $2 in
    aks)
        scripts/aks-handler.sh delete $FULL_CLUSTER_NAME
        scripts/aks-handler.sh delete $BUILD_CLUSTER_NAME
        scripts/aks-handler.sh delete $RUN_CLUSTER_NAME
        ;;
    eks)
        scripts/eks-handler.sh delete $FULL_CLUSTER_NAME
        scripts/eks-handler.sh delete $BUILD_CLUSTER_NAME
        scripts/eks-handler.sh delete $RUN_CLUSTER_NAME
        ;;
    laptop)
        scripts/minikube-handler.sh delete
        ;;
    *)
        incorrect-usage
        ;;
    esac
    ;;
apis)
    add-apis
    ;;
dev)
    install-gui-dev
    ;;
relocate-tap-images)
    relocate-tap-images
    ;;
runme)
    $2
    ;;
*)
    incorrect-usage
    ;;
esac