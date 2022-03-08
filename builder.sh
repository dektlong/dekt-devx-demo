#!/usr/bin/env bash

#################### configs #######################

    source .config/config-values.env
    PRIVATE_REPO=$(yq e .ootb_supply_chain_basic.registry.server .config/tap-values.yaml)
    PRIVATE_REPO_USER=$(yq e .buildservice.kp_default_repository_username .config/tap-values.yaml)
    PRIVATE_REPO_PASSWORD=$(yq e .buildservice.kp_default_repository_password .config/tap-values.yaml)
    TANZU_NETWORK_USER=$(yq e .buildservice.tanzunet_username .config/tap-values.yaml)
    TANZU_NETWORK_PASSWORD=$(yq e .buildservice.tanzunet_password .config/tap-values.yaml)
    
    GATEWAY_NS="scgw-system"
    BROWNFIELD_NS="brownfield-apis"
    
#################### installers ################

    #install
    install() {

        install-tap-prereq

        tanzu package install tap -p tap.tanzu.vmware.com -v $TAP_VERSION  --values-file .config/tap-values.yaml -n tap-install

           install-api-gateway #temp until GW is available as a TAP package 
        
        setup-demo-examples

        scripts/ingress-handler.sh tap

        tanzu package installed update tap --package-name tap.tanzu.vmware.com --version $TAP_VERSION -n tap-install -f .config/tap-values.yaml

    }

    #install-tap-prereq
    install-tap-prereq () {

        export INSTALL_BUNDLE=registry.tanzu.vmware.com/tanzu-cluster-essentials/cluster-essentials-bundle@sha256:82dfaf70656b54dcba0d4def85ccae1578ff27054e7533d08320244af7fb0343
        export INSTALL_REGISTRY_HOSTNAME=registry.tanzu.vmware.com
        export INSTALL_REGISTRY_USERNAME=$TANZU_NETWORK_USER
        export INSTALL_REGISTRY_PASSWORD=$TANZU_NETWORK_PASSWORD
        pushd config-templates/tanzu-cluster-essentials
        ./install.sh
        pushd

        kubectl create ns tap-install
        kubectl create ns $DEMO_APPS_NS
        
        tanzu secret registry add tap-registry \
            --username ${INSTALL_REGISTRY_USERNAME} --password ${INSTALL_REGISTRY_PASSWORD} \
            --server ${INSTALL_REGISTRY_HOSTNAME} \
            --export-to-all-namespaces --yes --namespace tap-install

        tanzu package repository add tanzu-tap-repository \
            --url registry.tanzu.vmware.com/tanzu-application-platform/tap-packages:$TAP_VERSION \
            --namespace tap-install
    }

    #install-api-gateway
    install-api-gateway () {

        kubectl create ns $GATEWAY_NS

        kubectl create secret docker-registry spring-cloud-gateway-image-pull-secret \
            --docker-server=$PRIVATE_REPO \
            --docker-username=$PRIVATE_REPO_USER \
            --docker-password=$PRIVATE_REPO_PASSWORD \
            --namespace $GATEWAY_NS
 
        $GW_INSTALL_DIR/scripts/install-spring-cloud-gateway.sh --namespace $GATEWAY_NS

    }

    #setup-demo-examples
    setup-demo-examples () {
 
        #accelerators 
        kustomize build supplychain/accelerators | kubectl apply -f -

        #supplychain (default + web-backend 'dummy')
        tanzu secret registry add registry-credentials --server $PRIVATE_REPO --username $PRIVATE_REPO_USER --password $PRIVATE_REPO_PASSWORD -n $DEMO_APPS_NS
        kubectl apply -f .config/supplychain-rbac.yaml -n $DEMO_APPS_NS
        kubectl apply -f supplychain/supplychain-src-to-api.yaml

        #cluster wide disable scale2zero
        kubectl apply -f config-templates/disable-scale2zero.yaml 

        #brownfield API
        kubectl create ns $BROWNFIELD_NS
        kubectl create secret generic sso-credentials --from-env-file=.config/sso-creds.txt -n api-portal
        kustomize build workloads/brownfield-apis | kubectl apply -f -

        #rabbitmq (operator and instance)
        kapp -y deploy --app rmq-operator --file https://github.com/rabbitmq/cluster-operator/releases/download/v1.9.0/cluster-operator.yml
        kubectl apply -f supplychain/templates/rabbitmq-clusterrole.yaml
        kubectl apply -f workloads/devx-mood/rabbitmq-instance.yaml -n $DEMO_APPS_NS
    }
    
    #deploy demo workloads
    deploy() {

        tanzu apps workload create -f workloads/devx-mood/mood-sensors.yaml -y
        tanzu apps workload create -f workloads/devx-mood/mood-portal.yaml -y
    }

    #reset demo apps
    reset() {

        tanzu apps workload delete portal -n $DEMO_APPS_NS -y
        tanzu apps workload delete sensors -n $DEMO_APPS_NS -y
        kubectl delete pod -l app=backstage -n tap-gui
        kubectl -n app-live-view delete pods -l=name=application-live-view-connector
        tanzu package installed update tap --package-name tap.tanzu.vmware.com --version $TAP_VERSION -n tap-install -f .config/tap-values.yaml
    }

    #incorrect usage
    incorrect-usage() {
        
        echo
        echo "Incorrect usage. Please specify one of the following: "
        echo
        echo "  init [aks / eks]"
        echo
        echo "  deploy"
        echo
        echo "  reset"
        echo
        echo "  cleanup [aks / eks]"
        echo
        echo "  runme [function-name]"
        echo
        exit
    
    }

    #relocate-images
    relocate-gw-images() {

        echo "Make sure docker deamon is running..."
        read
        
        docker login $PRIVATE_REPO -u $PRIVATE_REPO_USER -p $PRIVATE_REPO_PASSWORD
        
        $GW_INSTALL_DIR/scripts/relocate-images.sh $PRIVATE_REPO/dekt-system
    }

    #install-gui-dev
    install-gui-dev() {

        kubectl apply -f .config/tap-gui-dev-package.yaml

        export INSTALL_REGISTRY_HOSTNAME=dev.registry.tanzu.vmware.com
        export INSTALL_REGISTRY_USERNAME=$TANZU_NETWORK_USER
        export INSTALL_REGISTRY_PASSWORD=$TANZU_NETWORK_PASSWORD

        tanzu secret registry add dev-registry --username ${INSTALL_REGISTRY_USERNAME} --password ${INSTALL_REGISTRY_PASSWORD} --server ${INSTALL_REGISTRY_HOSTNAME} --export-to-all-namespaces --yes --namespace tap-install

        tanzu package install tap-gui -p tap-gui.tanzu.vmware.com -v 1.1.0-build.1 --values-file .config/tap-gui-values.yaml -n tap-install

        kubectl port-forward service/server 7000 -n tap-gui #access gui on localhost:7000
       
    }

#################### main ##########################

case $1 in
init)
    case $2 in
    aks)
        scripts/aks-handler.sh create
        ;;
    eks)
        scripts/eks-handler.sh create
        ;;
    *)
        incorrect-usage
        ;;
    esac
    install
    ;;
cleanup)
    case $2 in
    aks)
        scripts/aks-handler.sh delete
        ;;
    eks)
        scripts/eks-handler.sh delete
        ;;
    *)
        incorrect-usage
        ;;
    esac
    rm ~/Downloads/workload.yaml
    ;;
reset)
    reset
    ;;
deploy)
    deploy
    ;;
runme)
    $2
    ;;
*)
    incorrect-usage
    ;;
esac