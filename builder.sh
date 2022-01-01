#!/usr/bin/env bash

#################### configs #######################

    source .config/config-values.env
    PRIVATE_REPO=$(yq e .ootb_supply_chain_basic.registry.server .config/tap-values.yaml)
    PRIVATE_REPO_USER=$(yq e .buildservice.kp_default_repository_username .config/tap-values.yaml)
    PRIVATE_REPO_PASSWORD=$(yq e .buildservice.kp_default_repository_password .config/tap-values.yaml)
    
    BUILDER_NAME="online-stores-builder"
    GATEWAY_NS="scgw-system"
    API_PORTAL_NS="api-portal"
    BROWNFIELD_NS="brownfield-apis"
    
    TAP_VERSION="0.4.0"
  
#################### installers ################

    #install-core
    install-core() {

        install-tap-prereq

        tanzu package install tap -p tap.tanzu.vmware.com -v $TAP_VERSION  --values-file .config/tap-values.yaml -n tap-install

        setup-dekt-tap-examples

    }

    #add-api-grid
    add-api-grid() {

        install-api-gateway

        install-api-portal

        setup-dekt-apigrid-examples


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

        echo
        echo "===> Installing Spring Cloud Gateway operator using HELM..."
        echo

        kubectl create ns $GATEWAY_NS

        kubectl create secret docker-registry spring-cloud-gateway-image-pull-secret \
            --docker-server=$PRIVATE_REPO \
            --docker-username=$PRIVATE_REPO_USER \
            --docker-password=$PRIVATE_REPO_PASSWORD \
            --namespace $GATEWAY_NS
 
        $GW_INSTALL_DIR/scripts/install-spring-cloud-gateway.sh --namespace $GATEWAY_NS

    }

    #install-api-portal (not via TAP)
    install-api-portal () {
    
        echo
        echo "===> Installing API portal using helm..."
        echo

        kubectl create ns $API_PORTAL_NS

        kubectl create secret docker-registry api-portal-image-pull-secret \
            --docker-server=$PRIVATE_REPO \
            --docker-username=$PRIVATE_REPO_USER \
            --docker-password=$PRIVATE_REPO_PASSWORD \
            --namespace $API_PORTAL_NS
      
        kubectl create secret generic sso-credentials --from-env-file=.config/sso-creds.txt -n $API_PORTAL_NS
        
        $API_PORTAL_INSTALL_DIR/scripts/install-api-portal.sh
       
        kubectl set env deployment.apps/api-portal-server API_PORTAL_SOURCE_URLS_CACHE_TTL_SEC=10 -n $API_PORTAL_NS #so frontend apis will appear faster, just for this demo

        kubectl set env deployment.apps/api-portal-server API_PORTAL_SOURCE_URLS=http://scg-openapi.$GW_SUB_DOMAIN.$DOMAIN/openapi -n $API_PORTAL_NS

    }

    #setup-dekt-tap-examples
    setup-dekt-tap-examples () {

        echo
        echo "===> Setup TAP demo examples..."
        echo

        #accelerators 
        kustomize build supplychain/accelerators | kubectl apply -f -

        #supplychain (default + web-backend 'dummy')
        tanzu secret registry add registry-credentials --server $PRIVATE_REPO --username $PRIVATE_REPO_USER --password $PRIVATE_REPO_PASSWORD -n $DEMO_APPS_NS
        kubectl apply -f .config/supplychain-rbac.yaml -n $DEMO_APPS_NS
        kubectl apply -f supplychain/supplychain-src-to-api.yaml

        #rabbitmq operator
        kapp -y deploy --app rmq-operator --file https://github.com/rabbitmq/cluster-operator/releases/download/v1.9.0/cluster-operator.yml
        kubectl apply -f supplychain/templates/rabbitmq-clusterrole.yaml
        #rabbitmq instance
        kubectl apply -f workloads/devx-mood/rabbitmq-instance.yaml -n $DEMO_APPS_NS

        #devx-mood-backend without scale2zero (no rabbitMQ)
        tanzu apps workload apply devx-mood-backend \
            --type web \
            --git-repo https://github.com/dektlong/devx-mood-backend \
            --git-branch main \
            --label autoscaling.knative.dev/minScale=2 \
            --namespace $DEMO_APPS_NS \
            --yes

        add-tap-ingress
    }

    #setup-taapigrid-examples
    setup-dekt-apigrid-examples () {
        add-apigrid-ingress
        
        #brownfield
        kubectl create ns $BROWNFIELD_NS
        kustomize build workloads/brownfield-apis | kubectl apply -f -

        #dekt4pets
        kubectl create secret generic sso-secret --from-env-file=.config/sso-creds.txt -n $DEMO_APPS_NS
        kubectl create secret generic jwk-secret --from-env-file=.config/jwk-creds.txt -n $DEMO_APPS_NS
        kubectl create secret generic wavefront-secret --from-env-file=.config/wavefront-creds.txt -n $DEMO_APPS_NS

        kubectl apply -f workloads/dekt4pets/gateway/dekt4pets-gateway-dev.yaml -n $DEMO_APPS_NS

        create-dekt4pets-images

        

    }

    #create dekt4pets images
    create-dekt4pets-images () {


        frontend_image_location=$PRIVATE_REPO/$PRIVATE_REGISTRY_APP_REPO/$FRONTEND_TBS_IMAGE:$APP_VERSION
        backend_image_location=$PRIVATE_REPO/$PRIVATE_REGISTRY_APP_REPO/$BACKEND_TBS_IMAGE:$APP_VERSION

        export REGISTRY_PASSWORD=$PRIVATE_REPO_PASSWORD
        kp secret create private-registry-creds \
            --registry $PRIVATE_REPO \
            --registry-user $PRIVATE_REPO_USER \
            --namespace $DEMO_APPS_NS 
    
        echo
        echo "===> Create dekt4pets-backend TBS image..."
        echo

        kp image create $BACKEND_TBS_IMAGE -n $DEMO_APPS_NS \
        --tag $backend_image_location \
        --git $DEMO_APP_GIT_REPO  \
        --sub-path ./workloads/dekt4pets/backend \
        --git-revision main

        #scripts/wait-for-tbs.sh $BACKEND_TBS_IMAGE $DEMO_APPS_NS
        kp build logs $BACKEND_TBS_IMAGE -n $DEMO_APPS_NS
                
        echo
        echo "===> Create dekt4pets-frontend TBS image..."
        echo

        kp image save $FRONTEND_TBS_IMAGE -n $DEMO_APPS_NS \
        --tag $frontend_image_location \
        --git $DEMO_APP_GIT_REPO  \
        --sub-path ./workloads/dekt4pets/frontend \
        --git-revision main 

        scripts/wait-for-tbs.sh $FRONTEND_TBS_IMAGE $DEMO_APPS_NS
        kp build logs $FRONTEND_TBS_IMAGE -n $DEMO_APPS_NS

    }

    #add-tap-ingress-rules
    add-tap-ingress() {

        echo
        echo "===> Add ingress rules for TAP components..."
        echo

        scripts/update-dns.sh

        scripts/add-gw-ingress.sh "acc" "acc-server" "80" "accelerator-system"
        
        scripts/add-gw-ingress.sh "alv" "application-live-view-5112" "5112" "app-live-view"
        
#        kubectl patch configmap/config-domain \
 #           --namespace knative-serving \
  #          --type merge \
   #         --patch '{"data":{"'$CNR_SUB_DOMAIN.$DOMAIN'":""}}'

    }

    #add-apigrid-ingress-rules
    add-apigrid-ingress() {

        scripts/add-gw-ingress.sh "api-portal" "api-portal-server" "8080" $API_PORTAL_NS

        scripts/add-gw-ingress.sh "scg-openapi" "scg-operator" "80" $GATEWAY_NS

        scripts/add-gw-ingress.sh "dekt4pets-dev" "dekt4pets-gateway-dev" "80" $DEMO_APPS_NS
    }    
    
      
#################### misc ################
    
     
    #incorrect usage
    incorrect-usage() {
        
        echo
        echo "Incorrect usage. Please specify one of the following: "
        echo
        echo "  init"
        echo
        echo "  api-grid"
        echo
        echo "  cleanup"
        echo
        echo "  relocate-images"
        echo 
        echo "  runme [function-name]"
        echo
    
    }

    update-tap-gui () {

        kubectl delete pod -l app=backstage -n tap-gui

        update-tap
    }

    #update-tap
    update-tap () {

        tanzu package installed update tap --package-name tap.tanzu.vmware.com --version $TAP_VERSION -n tap-install -f .config/tap-values.yaml
    }

    #relocate-images
    relocate-images() {

        echo "Make sure docker deamon is running..."
        read
        
        docker login $PRIVATE_REPO -u $PRIVATE_REPO_USER -p $PRIVATE_REPO_PASSWORD
        
        $GW_INSTALL_DIR/scripts/relocate-images.sh $PRIVATE_REPO/$PRIVATE_REGISTRY_SYSTEM_REPO

        $API_PORTAL_INSTALL_DIR/scripts/relocate-images.sh $PRIVATE_REPO/$PRIVATE_REGISTRY_SYSTEM_REPO
    }

    #wait-for-tap
    wait-for-reconciler () {
        #wait for Reconcile to complete 
        status=""
        printf "Waiting for tanzu package repository list to reconcile ."
        while [ "$status" == "" ]
        do
            printf "."
            status="$(tanzu package repository get tanzu-tap-repository --namespace tap-install  -o=json | grep 'succeeded')" 
            sleep 1
        done
        echo
    }

#################### main ##########################

case $1 in
init)
    case $K8S_DIALTONE in
        aks)
            scripts/build-aks-cluster.sh create $CLUSTER_NAME 7 
            install-core
            ;;
        eks)
	        scripts/build-eks-cluster.sh create $CLUSTER_NAME
            install-core
            ;;
        *)
            echo
            echo "Invalid K8S Dialtone. Supported dialtones are: aks, eks, tkg"
            echo
            ;;
    esac
    ;;
api-grid)
    add-api-grid
    ;;
relocate-images)
    relocate-images
    ;;
cleanup)
    case $K8S_DIALTONE in
        aks)
            scripts/build-aks-cluster.sh delete $CLUSTER_NAME
            ;;
        eks)
	        scripts/build-eks-cluster.sh delete $CLUSTER_NAME
            ;;
        *)
            echo
            echo "Invalid K8S Dialtone. Supported dialtones are: aks, eks, tkg"
            echo
            ;;
    esac
    ;;
runme)
    $2
    ;;
*)
    incorrect-usage
    ;;
esac