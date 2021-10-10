#!/usr/bin/env bash

#################### configs #######################

    source .config/config-values.env
    
    BACKEND_TBS_IMAGE="dekt4pets-backend"
    FRONTEND_TBS_IMAGE="dekt4pets-frontend"
    ADOPTER_CHECK_TBS_IMAGE="adopter-check"
    BUILDER_NAME="online-stores-builder"
    TAP_INSTALL_NS="tap-install"
    GATEWAY_NS="scgw-system"
    API_PORTAL_NS="api-portal"
    BROWNFIELD_NS="brownfield-apis"
    ALV_NS="app-live-view"

#################### installers ################

    #install-all
    install-all() {

        setup-cluster
        
        install-tap-core

        install-apigrid

        install-tap-supplychain

        setup-demo-examples

        echo
        echo "Demo install completed. Enjoy your demo."
        echo

    }

    #setup-cluster
    setup-cluster () {

        scripts/build-aks-cluster.sh create $CLUSTER_NAME 7

        scripts/install-nginx.sh

        kubectl create ns $TAP_INSTALL_NS
        kubectl create ns $GATEWAY_NS
        kubectl create ns $API_PORTAL_NS 
        kubectl create ns $ALV_NS #same as in .config/alv-values.yaml server_namespace
        kubectl create ns $DEMO_APPS_NS
        kubectl create ns $BROWNFIELD_NS

    }
    #install-tap-core
    install-tap-core () {

        echo
        echo "===> Install TAP core components..."
        echo

        TAP_VERSION=0.2.0

        kapp deploy -y -a kc -f https://github.com/vmware-tanzu/carvel-kapp-controller/releases/download/v0.25.0/release.yml

        kapp deploy -y -a sg -f https://github.com/vmware-tanzu/carvel-secretgen-controller/releases/download/v0.5.0/release.yml

        kapp deploy -y -a cert-manager -f https://github.com/jetstack/cert-manager/releases/download/v1.5.3/cert-manager.yaml

        kubectl create clusterrolebinding default-admin \
            --clusterrole=cluster-admin \
            --serviceaccount=flux-system:default

        kubectl create namespace flux-system
        kapp deploy -y -a flux-source-controller -n flux-system \
            -f https://github.com/fluxcd/source-controller/releases/download/v0.15.4/source-controller.crds.yaml \
            -f https://github.com/fluxcd/source-controller/releases/download/v0.15.4/source-controller.deployment.yaml
        
        tanzu imagepullsecret add tap-registry \
            --username $TANZU_NETWORK_USER --password $TANZU_NETWORK_PASSWORD \
            --registry registry.tanzu.vmware.com \
            --export-to-all-namespaces --namespace $TAP_INSTALL_NS  

        tanzu package repository add tanzu-tap-repository \
            --url registry.tanzu.vmware.com/tanzu-application-platform/tap-packages:$TAP_VERSION \
            --namespace $TAP_INSTALL_NS

        wait-for-reconciler
      
        #Export a secret for storing container images to all namespaces
        tanzu imagepullsecret add registry-credentials --registry $PRIVATE_REGISTRY_URL --username $PRIVATE_REGISTRY_USER --password $PRIVATE_REGISTRY_PASSWORD --export-to-all-namespaces --namespace $TAP_INSTALL_NS
    }

    #install-tap-products
    install-apigrid () {


        echo
        echo "===> Install APIGrid components ..."
        echo

        #cnr
        tanzu package install cloud-native-runtimes -p cnrs.tanzu.vmware.com -v 1.0.2 -n $TAP_INSTALL_NS -f .config/cnr-values.yaml --poll-timeout 30m
        scripts/update-dns.sh "envoy" "contour-external" "*.cnr"

        #acc
        tanzu package install app-accelerator -p accelerator.apps.tanzu.vmware.com -v 0.3.0 -n $TAP_INSTALL_NS -f .config/acc-values.yaml
        kubectl apply -f .config/acc-ingress.yaml -n accelerator-system

        #tbs
        tanzu package install tbs -p buildservice.tanzu.vmware.com -v 1.3.0 -n $TAP_INSTALL_NS -f .config/tbs-values.yaml --poll-timeout 30m

        #alv
        tanzu package install app-live-view -p appliveview.tanzu.vmware.com -v 0.2.0 -n $TAP_INSTALL_NS -f .config/alv-values.yaml
        kubectl apply -f .config/alv-ingress.yaml -n $ALV_NS

        #gateway
        install-gw-helm
        
        #api-portal
        install-api-portal-helm
            #tanzu package install api-portal -p api-portal.tanzu.vmware.com -v 1.0.2 -n $TAP_INSTALL_NS -f .config/api-portal-values.yaml
            #TEMP until portal installed in its own ns
            #kubectl apply -f .config/api-portal-ingress.yaml -n $TAP_INSTALL_NS 
            #  kubectl set env deployment.apps/api-portal-server API_PORTAL_SOURCE_URLS=http://scg-openapi.$SUB_DOMAIN.$DOMAIN/openapi -n $TAP_INSTALL_NS 
            # kubectl set env deployment.apps/api-portal-server API_PORTAL_SOURCE_URLS_CACHE_TTL_SEC=10 -n $TAP_INSTALL_NS

    }

    #install-supply-chain
    install-tap-supplychain () {

        echo
        echo "===> Install TAP supllychain components..."
        echo

        tanzu package install source-controller -p controller.source.apps.tanzu.vmware.com -v 0.1.2 -n $TAP_INSTALL_NS
        
        tanzu package install convention-controller -p controller.conventions.apps.tanzu.vmware.com -v 0.4.2 -n $TAP_INSTALL_NS
        
        tanzu package install cartographer -p cartographer.tanzu.vmware.com -v 0.0.6 -n $TAP_INSTALL_NS
        
        tanzu package install default-supply-chain -p default-supply-chain.tanzu.vmware.com -v 0.2.0 -n $TAP_INSTALL_NS -f .config/default-supply-chain-values.yaml
        
        tanzu package install metadata-store -p scst-store.tanzu.vmware.com -v 1.0.0-beta.0 -n $TAP_INSTALL_NS -f .config/scst-store-values.yaml

        tanzu package install developer-conventions -p developer-conventions.tanzu.vmware.com -v 0.2.0 -n $TAP_INSTALL_NS

        tanzu package install service-bindings -p service-bindings.labs.vmware.com -v 0.5.0 -n $TAP_INSTALL_NS
    }
    
#################### demo examples ################

    #setup-demo-examples
    setup-demo-examples() {

        echo
        echo "===> Setup APIGrid demo examples..."
        echo

        kubectl apply -f .config/carto-secrets.yaml -n $DEMO_APPS_NS

        kubectl apply -f workloads/dekt4pets/accelerators.yaml -n accelerator-system #must be same as .config/acc-values.yaml   watched_namespace:

        create-dekt4pets-images
        
        create-adopter-check-image

        create-api-examples
       
    }

    #create dekt4pets images
    create-dekt4pets-images () {

        frontend_image_location=$PRIVATE_REGISTRY_URL/$PRIVATE_REGISTRY_APP_REPO/$FRONTEND_TBS_IMAGE:$APP_VERSION
        backend_image_location=$PRIVATE_REGISTRY_URL/$PRIVATE_REGISTRY_APP_REPO/$BACKEND_TBS_IMAGE:$APP_VERSION
    

        export REGISTRY_PASSWORD=$PRIVATE_REGISTRY_PASSWORD
        kp secret create imagereg-secret \
            --registry $PRIVATE_REGISTRY_URL \
            --registry-user $PRIVATE_REGISTRY_USER \
            --namespace $DEMO_APPS_NS 
        
        kp image create $BACKEND_TBS_IMAGE -n $DEMO_APPS_NS \
        --tag $backend_image_location \
        --git $DEMO_APP_GIT_REPO  \
        --sub-path ./workloads/dekt4pets/backend \
        --git-revision main \
        --wait
        
        kp image save $FRONTEND_TBS_IMAGE -n $DEMO_APPS_NS \
        --tag $frontend_image_location= \
        --git $DEMO_APP_GIT_REPO  \
        --sub-path ./workloads/dekt4pets/frontend \
        --git-revision main \
        --wait


    }
    
    #create adopter-check image
    create-adopter-check-image () {

        adopter_image_location=$PRIVATE_REGISTRY_URL/$PRIVATE_REGISTRY_APP_REPO/$ADOPTER_CHECK_TBS_IMAGE:$APP_VERSION
        
        kp image save $ADOPTER_CHECK_TBS_IMAGE -n $DEMO_APPS_NS \
            --tag $adopter_image_location \
            --git https://github.com/dektlong/adopter-check \
            --wait #\
            #--sub-path ./workloads/dekt4pets/adopter-check/java-native \
            #--env BP_BOOT_NATIVE_IMAGE=1 \
            #--env BP_JVM_VERSION=11 \
            #--env BP_MAVEN_BUILD_ARGUMENTS="-Dmaven.test.skip=true package spring-boot:repackage" \
            #--env BP_BOOT_NATIVE_IMAGE_BUILD_ARGUMENTS="-Dspring.spel.ignore=true -Dspring.xml.ignore=true -Dspring.native.remove-yaml-support=true --enable-all-security-services" \
            
    }

    #create-api-examples
    create-api-examples() {

        kubectl apply -f .config/scg-openapi-ingress.yaml -n $GATEWAY_NS
        
        kustomize build workloads/brownfield-apis | kubectl apply -f -

        kubectl create secret generic sso-secret --from-env-file=.config/sso-creds.txt -n $DEMO_APPS_NS
        kubectl create secret generic jwk-secret --from-env-file=.config/jwk-creds.txt -n $DEMO_APPS_NS
        kubectl create secret generic wavefront-secret --from-env-file=.config/wavefront-creds.txt -n $DEMO_APPS_NS

        kustomize build workloads/dekt4pets/gateway | kubectl apply -f -




    }
    

#################### pre-tap installers ################
    
    #install-gw-helm
    install-gw-helm() {
        
        echo
        echo "===> Installing Spring Cloud Gateway operator using HELM..."
        echo
    
        
        
        #scgw
        kubectl create secret docker-registry spring-cloud-gateway-image-pull-secret \
            --docker-server=$PRIVATE_REGISTRY_URL \
            --docker-username=$PRIVATE_REGISTRY_USER \
            --docker-password=$PRIVATE_REGISTRY_PASSWORD \
            --namespace $GATEWAY_NS

        $GW_INSTALL_DIR/scripts/install-spring-cloud-gateway.sh --namespace $GATEWAY_NS

                
    }

    #install TBS
    install-tbs() {
        
        ytt -f $TBS_INSTALL_DIR/values.yaml \
            -f $TBS_INSTALL_DIR/manifests/ \
            -v docker_repository="$PRIVATE_REGISTRY_URL/$PRIVATE_REGISTRY_SYSTEM_REPO/build-service" \
            -v docker_username="$PRIVATE_REGISTRY_USER" \
            -v docker_password="$PRIVATE_REGISTRY_PASSWORD" \
            | kbld -f $TBS_INSTALL_DIR/images-relocated.lock -f- \
            | kapp deploy -a tanzu-build-service -f- -y

        kp import -f tbs/descriptor-full.yaml

    }

    #install-api-portal-helm
    install-api-portal-helm() {

        echo
        echo "===> Installing API portal using helm..."
        echo

        kubectl create secret docker-registry api-portal-image-pull-secret \
            --docker-server=$PRIVATE_REGISTRY_URL \
            --docker-username=$PRIVATE_REGISTRY_USER \
            --docker-password=$PRIVATE_REGISTRY_PASSWORD \
            --namespace $API_PORTAL_NS
      
        kubectl create secret generic sso-credentials --from-env-file=.config/sso-creds.txt -n $API_PORTAL_NS
        
        $API_PORTAL_INSTALL_DIR/scripts/install-api-portal.sh
        
        kubectl set env deployment.apps/api-portal-server API_PORTAL_SOURCE_URLS=http://scg-openapi.$SUB_DOMAIN.$DOMAIN/openapi -n $API_PORTAL_NS

        kubectl set env deployment.apps/api-portal-server API_PORTAL_SOURCE_URLS_CACHE_TTL_SEC=10 -n $API_PORTAL_NS #so frontend apis will appear faster, just for this demo

        kubectl apply -f .config/api-portal-ingress.yaml -n $API_PORTAL_NS
      
    }
    
#################### misc ################
    
     
    #incorrect usage
    incorrect-usage() {
        
        echo
        echo "Incorrect usage. Please specify one of the following: "
        echo
        echo " init"
        echo " cleanup"
        echo " runme"
        echo
    
    }

    #wait-for-tap
    wait-for-reconciler () {
        #wait for Reconcile to complete 
        status=""
        printf "Waiting for tanzu package repository list to reconcile ."
        while [ "$status" == "" ]
        do
            printf "."
            status="$(tanzu package repository get tanzu-tap-repository --namespace $TAP_INSTALL_NS  -o=json | grep 'succeeded')" 
            sleep 1
        done
        echo
    }


#################### main ##########################

case $1 in
init)
    install-all
    ;;
cleanup)
	scripts/build-aks-cluster.sh delete $CLUSTER_NAME 
    ;;
runme)
    $2
    ;;
*)
    incorrect-usage
    ;;
esac