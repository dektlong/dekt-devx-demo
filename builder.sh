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

    #install-remote
    install-remote() {

        install-tap-prereq

        tanzu package install tap -p tap.tanzu.vmware.com -v $TAP_VERSION  --values-file .config/tap-values.yaml -n tap-install

        setup-supplychain

        scripts/ingress-handler.sh tap

        update-tap

    }

     #install-local
    install-local() {

        install-tap-prereq

        tanzu package install tap -p tap.tanzu.vmware.com -v $TAP_VERSION  --values-file .config/tap-values-local.yaml -n tap-install

        tanzu secret registry add registry-credentials --server $PRIVATE_REPO --username $PRIVATE_REPO_USER --password $PRIVATE_REPO_PASSWORD -n $DEMO_APPS_NS
        
        kubectl apply -f .config/supplychain-rbac.yaml -n $DEMO_APPS_NS

    }

    #install-tap-prereq
    install-tap-prereq () {

        export INSTALL_BUNDLE=registry.tanzu.vmware.com/tanzu-cluster-essentials/cluster-essentials-bundle@sha256:82dfaf70656b54dcba0d4def85ccae1578ff27054e7533d08320244af7fb0343
        export INSTALL_REGISTRY_HOSTNAME=registry.tanzu.vmware.com
        export INSTALL_REGISTRY_USERNAME=$TANZU_NETWORK_USER
        export INSTALL_REGISTRY_PASSWORD=$TANZU_NETWORK_PASSWORD
        pushd tanzu-cluster-essentials
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

        update-tap

    }

    #setup-supplychain
    setup-supplychain () {
 
        #setup apps namespace
        tanzu secret registry add registry-credentials --server $PRIVATE_REPO --username $PRIVATE_REPO_USER --password $PRIVATE_REPO_PASSWORD -n $DEMO_APPS_NS
        kubectl apply -f .config/supplychain-rbac.yaml -n $DEMO_APPS_NS
        kubectl apply -f .config/disable-scale2zero.yaml

        #accelerators 
        kustomize build accelerators | kubectl apply -f -

        #dekt-path2prod custom supply chain
        kubectl apply -f .config/dekt-path2prod.yaml

        #scan policy
        kubectl apply -f .config/scan-policy.yaml -n $DEMO_APPS_NS

        #testing pipeline
        kubectl apply -f .config/tekton-pipeline.yaml -n $DEMO_APPS_NS

        #rabbitmq service
        kapp -y deploy --app rmq-operator --file https://github.com/rabbitmq/cluster-operator/releases/download/v1.9.0/cluster-operator.yml
        kubectl apply -f .config/rabbitmq-cluster-config.yaml -n $DEMO_APPS_NS
        kubectl apply -f .config/reading-rabbitmq-instance.yaml -n $DEMO_APPS_NS
    }
    
    #reset demo apps
    reset() {

        tanzu apps workload delete mood-portal -n $DEMO_APPS_NS -y
        tanzu apps workload delete mood-sensors -n $DEMO_APPS_NS -y
        kubectl delete pod -l app=backstage -n tap-gui
        kubectl -n app-live-view delete pods -l=name=application-live-view-connector
        update-tap
        toggle-dog sad
    }

    #toggle the ALWAYS_HAPPY flag in mood-portal
    toggle-dog () {

        pushd ../mood-portal

        case $1 in
        happy)
            sed -i '' 's/false/true/g' main.go
            git commit -a -m "always happy"      
            ;;
        sad)
            sed -i '' 's/true/false/g' main.go
            git commit -a -m "usually sad"
            ;;
        *)      
            echo "!!!incorrect-usage. please specify happy / sad"
            ;;
        esac
        
        git push
        pushd
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
    
    #update-tap
    update-tap() {

        tanzu package installed update tap --package-name tap.tanzu.vmware.com --version $TAP_VERSION -n tap-install -f .config/tap-values.yaml
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
        echo "  init [ aks / eks / local ]"
        echo
        echo "  apis"
        echo
        echo "  reset"
        echo
        echo "  dev"
        echo
        echo "  cleanup [ aks / eks / local ]"
        echo
        echo "  relocate-tap-images"
        echo
        echo "  runme [ function-name ]"
        echo
        exit
    }

#################### main ##########################

case $1 in
relocate-tap-images)
    relocate-tap-images
    ;;
init)
    case $2 in
    aks)
        scripts/aks-handler.sh create
        install-remote
        ;;
    eks)
        scripts/eks-handler.sh create
        install-remote
        ;;
    local)
        scripts/minikube-handler.sh create
        install-local
        ;;
    *)
        incorrect-usage
        ;;
    esac   
    ;;
cleanup)
    toggle-dog sad
    case $2 in
    aks)
        scripts/aks-handler.sh delete
        ;;
    eks)
        scripts/eks-handler.sh delete
        ;;
    local)
        scripts/minikube-handler.sh delete
        ;;
    *)
        incorrect-usage
        ;;
    esac
    ;;
reset)
    reset
    ;;
apis)
    add-apis
    ;;
always-happy)
    toggle-dog happy
    ;;
dev)
    install-gui-dev
    ;;
runme)
    $2
    ;;
*)
    incorrect-usage
    ;;
esac