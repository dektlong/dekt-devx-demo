#!/usr/bin/env bash

#################### configs #######################

    source secrets/config-values.env
    
    DET4PETS_FRONTEND_IMAGE_LOCATION=$PRIVATE_REGISTRY_URL/$PRIVATE_REGISTRY_APP_REPO/$FRONTEND_TBS_IMAGE:$APP_VERSION
    DET4PETS_BACKEND_IMAGE_LOCATION=$PRIVATE_REGISTRY_URL/$PRIVATE_REGISTRY_APP_REPO/$BACKEND_TBS_IMAGE:$APP_VERSION
    ADOPTER_CHECK_IMAGE_LOCATION=$PRIVATE_REGISTRY_URL/$PRIVATE_REGISTRY_APP_REPO/$ADOPTER_CHECK_TBS_IMAGE:$APP_VERSION
    TAP_INSTALL_NS="tap-install"
    GW_NAMESPACE="scgw-system"
    CARTO_NAMESPACE="cartographer-system"
    API_PORTAL_NAMESPACE="api-portal"
    BROWNFIELD_NAMESPACE="brownfield-apis"
    ALV_NS="app-live-view"

#################### TAP installers ################

    #build-all
    build-all() {

        platform/scripts/build-aks-cluster.sh create $CLUSTER_NAME 7

        platform/scripts/install-nginx.sh
      
        update-config-values #remove when all is via carvel

        install-tap-core

        install-tap-products

        install-gw-helm

        install-api-portal-helm

        setup-demo-examples

        echo
        echo "Demo install completed. Enjoy your demo."
        echo

    }

    #install-tap-core
    install-tap-core () {

        echo
        echo "===> Install TAP core components..."
        echo

        
        kubectl create ns $TAP_INSTALL_NS
        
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
        
        tanzu package available list --namespace $TAP_INSTALL_NS

        tanzu package install source-controller -p controller.source.apps.tanzu.vmware.com -v 0.1.2 -n $TAP_INSTALL_NS

        tanzu package install convention-controller -p controller.conventions.apps.tanzu.vmware.com -v 0.4.2 -n $TAP_INSTALL_NS

        tanzu package install service-bindings -p service-bindings.labs.vmware.com -v 0.5.0 -n $TAP_INSTALL_NS

        #Export a secret for storing container images to all namespaces
        tanzu imagepullsecret add registry-credentials --registry $PRIVATE_REGISTRY_URL --username $PRIVATE_REGISTRY_USER --password $PRIVATE_REGISTRY_PASSWORD --export-to-all-namespaces --namespace $TAP_INSTALL_NS
    }

    #install-tap-products
    install-tap-products() {


        echo
        echo "===> Install TAP products ..."
        echo

        #cnr
        tanzu package install cloud-native-runtimes -p cnrs.tanzu.vmware.com -v 1.0.2 -n $TAP_INSTALL_NS -f secrets/cnr-values.yaml --poll-timeout 30m
        platform/scripts/update-dns.sh "envoy" "contour-external" "*.cnr"

        #acc
        tanzu package install app-accelerator -p accelerator.apps.tanzu.vmware.com -v 0.3.0 -n $TAP_INSTALL_NS -f secrets/acc-values.yaml
        kubectl apply -f secrets/acc-ingress.yaml -n accelerator-system

        #tbs
        tanzu package install tbs -p buildservice.tanzu.vmware.com -v 1.3.0 -n $TAP_INSTALL_NS -f secrets/tbs-values.yaml --poll-timeout 30m

        #supply chain
        tanzu package install cartographer -p cartographer.tanzu.vmware.com -v 0.0.6 -n $TAP_INSTALL_NS
        tanzu package install default-supply-chain -p default-supply-chain.tanzu.vmware.com -v 0.2.0 -n $TAP_INSTALL_NS -f secrets/default-supply-chain-values.yaml
        tanzu package install metadata-store -p scst-store.tanzu.vmware.com -v 1.0.0-beta.0 -n $TAP_INSTALL_NS -f secrets/scst-store-values.yaml

        #dev convenstions
        tanzu package install developer-conventions -p developer-conventions.tanzu.vmware.com -v 0.2.0 -n $TAP_INSTALL_NS

        #alv
        kubectl create ns $ALV_NS #same as in secrets/alv-values.yaml server_namespace
        tanzu package install app-live-view -p appliveview.tanzu.vmware.com -v 0.2.0 -n $TAP_INSTALL_NS -f secrets/alv-values.yaml
        kubectl apply -f secrets/alv-ingress.yaml -n $ALV_NS

        #api-portal
        #tanzu package install api-portal -p api-portal.tanzu.vmware.com -v 1.0.2 -n $TAP_INSTALL_NS -f secrets/api-portal-values.yaml
        #TEMP until portal installed in its own ns
        #kubectl apply -f secrets/api-portal-ingress.yaml -n $TAP_INSTALL_NS 
          #  kubectl set env deployment.apps/api-portal-server API_PORTAL_SOURCE_URLS=http://scg-openapi.$SUB_DOMAIN.$DOMAIN/openapi -n $TAP_INSTALL_NS 
           # kubectl set env deployment.apps/api-portal-server API_PORTAL_SOURCE_URLS_CACHE_TTL_SEC=10 -n $TAP_INSTALL_NS

        #api-gw - STILL STAND ALONE INSTALL
        #$GW_INSTALL_DIR/scripts/install-spring-cloud-gateway.sh --namespace $GW_NAMESPACE
        #kubectl apply -f secrets/scg-openapi-ingress.yaml -n $GW_NAMESPACE

    }
    
#################### demo apps ################

    #setup-demo-examples
    setup-demo-examples() {

        echo
        echo "===> Setup APIGrid demo examples..."
        echo

        kubectl create ns $APP_NAMESPACE
        kubectl apply -f secrets/carto-secrets.yaml -n $APP_NAMESPACE

        kubectl apply -f workloads/dekt4pets/accelerators.yaml -n accelerator-system #must be same as secrets/acc-values.yaml   watched_namespace:

        create-dekt4pets-images
        
        create-adopter-check-image

        create-api-examples
       
    }

    #create dekt4pets images
    create-dekt4pets-images () {

        export REGISTRY_PASSWORD=$PRIVATE_REGISTRY_PASSWORD
        kp secret create imagereg-secret \
            --registry $PRIVATE_REGISTRY_URL \
            --registry-user $PRIVATE_REGISTRY_USER \
            --namespace $APP_NAMESPACE 
        
        kp image create $BACKEND_TBS_IMAGE -n $APP_NAMESPACE \
        --tag $DET4PETS_BACKEND_IMAGE_LOCATION \
        --git $DEMO_APP_GIT_REPO  \
        --sub-path ./workloads/dekt4pets/backend \
        --git-revision main \
        --wait
        
        kp image save $FRONTEND_TBS_IMAGE -n $APP_NAMESPACE \
        --tag $DET4PETS_FRONTEND_IMAGE_LOCATION \
        --git $DEMO_APP_GIT_REPO  \
        --sub-path ./workloads/dekt4pets/frontend \
        --git-revision main \
        --wait


    }
    
    #create adopter-check image
    create-adopter-check-image () {

        
        kp image save $ADOPTER_CHECK_TBS_IMAGE -n $APP_NAMESPACE \
            --tag $ADOPTER_CHECK_IMAGE_LOCATION \
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

        kubectl create ns $BROWNFIELD_NAMESPACE
        kustomize build workloads/brownfield-apis | kubectl apply -f -

        kubectl create secret generic sso-secret --from-env-file=secrets/sso-creds.txt -n $APP_NAMESPACE
        kubectl create secret generic jwk-secret --from-env-file=secrets/jwk-creds.txt -n $APP_NAMESPACE
        kubectl create secret generic wavefront-secret --from-env-file=secrets/wavefront-creds.txt -n $APP_NAMESPACE

        kustomize build workloads/dekt4pets/gateway | kubectl apply -f -




    }
    #frontend-image workaround
    create-frontend-image () {
        docker pull springcloudservices/animal-rescue-frontend
        docker tag springcloudservices/animal-rescue-frontend:latest $DET4PETS_FRONTEND_IMAGE_LOCATION
        docker push $DET4PETS_FRONTEND_IMAGE_LOCATION
    }



#################### pre-tap installers ################
    
    #install-gw-helm
    install-gw-helm() {
        
        echo
        echo "===> Installing Spring Cloud Gateway operator using HELM..."
        echo
    
        kubectl create ns $GW_NAMESPACE
        
        #scgw
        kubectl create secret docker-registry spring-cloud-gateway-image-pull-secret \
            --docker-server=$PRIVATE_REGISTRY_URL \
            --docker-username=$PRIVATE_REGISTRY_USER \
            --docker-password=$PRIVATE_REGISTRY_PASSWORD \
            --namespace $GW_NAMESPACE

        $GW_INSTALL_DIR/scripts/install-spring-cloud-gateway.sh --namespace $GW_NAMESPACE

                
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

        kp import -f platform/tbs/descriptor-full.yaml

    }

    #install-api-portal-helm
    install-api-portal-helm() {

        echo
        echo "===> Installing API portal using helm..."
        echo

        kubectl create ns $API_PORTAL_NAMESPACE 

        kubectl create secret docker-registry api-portal-image-pull-secret \
            --docker-server=$PRIVATE_REGISTRY_URL \
            --docker-username=$PRIVATE_REGISTRY_USER \
            --docker-password=$PRIVATE_REGISTRY_PASSWORD \
            --namespace $API_PORTAL_NAMESPACE 
      
        kubectl create secret generic sso-credentials --from-env-file=secrets/sso-creds.txt -n $API_PORTAL_NAMESPACE
        
        $API_PORTAL_INSTALL_DIR/scripts/install-api-portal.sh
        
        kubectl set env deployment.apps/api-portal-server API_PORTAL_SOURCE_URLS=http://scg-openapi.$SUB_DOMAIN.$DOMAIN/openapi -n $API_PORTAL_NAMESPACE

        kubectl set env deployment.apps/api-portal-server API_PORTAL_SOURCE_URLS_CACHE_TTL_SEC=10 -n $API_PORTAL_NAMESPACE #so frontend apis will appear faster, just for this demo

        kubectl apply -f platform/api-portal/config/api-portal-ingress.yaml -n $API_PORTAL_NAMESPACE

        kubectl apply -f platform/api-portal/config/scg-openapi-ingress.yaml -n $GW_NAMESPACE
    }
    
#################### misc ################

    #update-core-images
    update-core-images () {

        echo "Make sure the docker desktop deamon is running. Press any key to continue..."
        read
        docker login -u $PRIVATE_REGISTRY_USER -p $PRIVATE_REGISTRY_PASSWORD $PRIVATE_REGISTRY_URL
        
        case $1 in
        gateway)
            $GW_INSTALL_DIR/scripts/relocate-images.sh $PRIVATE_REGISTRY_URL/$PRIVATE_REGISTRY_SYSTEM_REPO
            ;;
        acc)
            imgpkg pull -b $ACC_INSTALL_BUNDLE -o /tmp/acc-install-bundle
            ;;
        tbs)
            kbld relocate -f $TBS_INSTALL_DIR/images.lock --lock-output $TBS_INSTALL_DIR/images-relocated.lock --repository $PRIVATE_REGISTRY_URL/$PRIVATE_REGISTRY_SYSTEM_REPO/build-service
            
            ;;
        api-portal)
            $API_PORTAL_INSTALL_DIR/scripts/relocate-images.sh $PRIVATE_REGISTRY_URL/$PRIVATE_REGISTRY_SYSTEM_REPO
            ;;
        alv)
            imgpkg pull -b dev.registry.pivotal.io/app-live-view/application-live-view-install-bundle:0.2.0-SNAPSHOT\
                -o $ALV_INSTALL_DIR
            ;;
        cnr)
            imgpkg copy --lock $CNR_INSTALL_DIR/cloud-native-runtimes-1.0.1.lock --to-repo $PRIVATE_REGISTRY_URL/$PRIVATE_REGISTRY_SYSTEM_REPO/cnr --lock-output $CNR_INSTALL_DIR/relocated.lock --registry-verify-certs=false 
            imgpkg pull --lock $CNR_INSTALL_DIR/relocated.lock -o $CNR_INSTALL_DIR
            ;;
        configs)
            update-configs
            ;;
        *)
            incorrect-usage
            ;;
        esac
    }
    
    #create-namespaces-secrets
    create-ns-secrets () {

        echo
        echo "===> Creating namespaces and secrets..."
        echo
        
        #namespaces
        kubectl create ns $TAP_INSTALL_NAMESPACE
        kubectl create ns $APP_NAMESPACE
        kubectl create ns $GW_NAMESPACE
        kubectl create ns $CARTO_NAMESPACE
        kubectl create ns $API_PORTAL_NAMESPACE
        kubectl create ns $BROWNFIELD_NAMESPACE
        kubectl create ns acme-fitness
        
        #tap secret
        kubectl create secret docker-registry tap-registry \
            -n $TAP_INSTALL_NAMESPACE \
            --docker-server=$TANZU_NETWORK_REGISTRY \
            --docker-username=$TANZU_NETWORK_USER \
            --docker-password=$TANZU_NETWORK_PASSWORD
        kubectl create secret docker-registry imagereg-secret \
            --docker-server=$PRIVATE_REGISTRY_URL \
            --docker-username=$PRIVATE_REGISTRY_USER \
            --docker-password=$PRIVATE_REGISTRY_PASSWORD \
            --namespace $TAP_INSTALL_NAMESPACE  
        kubectl create secret docker-registry private-registry-credentials \
            --docker-server=$PRIVATE_REGISTRY_URL \
            --docker-username=$PRIVATE_REGISTRY_USER \
            --docker-password=$PRIVATE_REGISTRY_PASSWORD \
            --namespace $CARTO_NAMESPACE  
  
        #apps secret        
        export REGISTRY_PASSWORD=$PRIVATE_REGISTRY_PASSWORD
        kp secret create imagereg-secret \
            --registry $PRIVATE_REGISTRY_URL \
            --registry-user $PRIVATE_REGISTRY_USER \
            --namespace $APP_NAMESPACE 
          kp secret create imagereg-secret \
            --registry $PRIVATE_REGISTRY_URL \
            --registry-user $PRIVATE_REGISTRY_USER \
            --namespace $BROWNFIELD_NAMESPACE 
        
        #scgw
        kubectl create secret docker-registry spring-cloud-gateway-image-pull-secret \
            --docker-server=$PRIVATE_REGISTRY_URL \
            --docker-username=$PRIVATE_REGISTRY_USER \
            --docker-password=$PRIVATE_REGISTRY_PASSWORD \
            --namespace $GW_NAMESPACE
        
        #api-portal
        kubectl create secret docker-registry api-portal-image-pull-secret \
            --docker-server=$PRIVATE_REGISTRY_URL \
            --docker-username=$PRIVATE_REGISTRY_USER \
            --docker-password=$PRIVATE_REGISTRY_PASSWORD \
            --namespace $API_PORTAL_NAMESPACE
      
        #sso secret for gatwway and portal
        kubectl create secret generic sso-secret --from-env-file=secrets/sso-creds.txt -n $APP_NAMESPACE
        kubectl create secret generic sso-credentials --from-env-file=secrets/sso-creds.txt -n $API_PORTAL_NAMESPACE


        #jwt secret for dekt4pets backend app
        kubectl create secret generic jwk-secret --from-env-file=secrets/jwk-creds.txt -n $APP_NAMESPACE

        #wavefront secret for dekt4pets and acme-fitness app
        kubectl create secret generic wavefront-secret --from-env-file=secrets/wavefront-creds.txt -n $APP_NAMESPACE
        kubectl create secret generic wavefront-secret --from-env-file=secrets/wavefront-creds.txt -n acme-fitness
    }

    
    #incorrect usage
    incorrect-usage() {
        
        echo
        echo "Incorrect usage. Please specify one of the following: init, cleanup, runme"
    
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

    #update-config-values
    update-config-values () {

        echo
        echo "===> Updating runtime configurations..."
        echo

        hostName=$SUB_DOMAIN.$DOMAIN

        #acc
        platform/scripts/replace-tokens.sh "platform/acc" "acc-ingress.yaml" "{HOST_NAME}" "$hostName"
        #api-portal
        platform/scripts/replace-tokens.sh "platform/api-portal" "scg-openapi-ingress.yaml" "{HOST_NAME}" "$hostName"
        platform/scripts/replace-tokens.sh "platform/api-portal" "api-portal-ingress.yaml" "{HOST_NAME}" "$hostName"
        #alv
        platform/scripts/replace-tokens.sh "platform/alv" "alv-ingress.yaml" "{HOST_NAME}" "$hostName"
        #dekt4pets
        platform/scripts/replace-tokens.sh "workloads/dekt4pets/backend" "dekt4pets-backend.yaml" "{BACKEND_IMAGE}" "$DET4PETS_BACKEND_IMAGE_LOCATION"
        #platform/scripts/replace-tokens.sh "workloads/dekt4pets/frontend" "dekt4pets-frontend.yaml" "{FRONTEND_IMAGE}" "$DET4PETS_FRONTEND_IMAGE_LOCATION" 
        platform/scripts/replace-tokens.sh "workloads/dekt4pets/frontend" "dekt4pets-frontend.yaml" "{FRONTEND_IMAGE}" "springcloudservices/animal-rescue-frontend" 
        platform/scripts/replace-tokens.sh "workloads/dekt4pets/gateway" "dekt4pets-gateway.yaml" "{HOST_NAME}" "$hostName"
        platform/scripts/replace-tokens.sh "workloads/dekt4pets/gateway" "dekt4pets-gateway-dev.yaml" "{HOST_NAME}" "$hostName"
        platform/scripts/replace-tokens.sh "workloads/dekt4pets/gateway" "dekt4pets-ingress.yaml" "{HOST_NAME}" "$hostName"
        platform/scripts/replace-tokens.sh "workloads/dekt4pets/gateway" "dekt4pets-ingress-dev.yaml" "{HOST_NAME}" "$hostName"
        
    
    }



#################### main ##########################

case $1 in
init)
    build-all
    ;;
cleanup)
	platform/scripts/build-aks-cluster.sh delete $CLUSTER_NAME 
    ;;
runme)
    $2
    ;;
*)
    incorrect-usage
    ;;
esac