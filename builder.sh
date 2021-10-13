#!/usr/bin/env bash

#################### configs #######################

    source .config/config-values.env
    
    BUILDER_NAME="online-stores-builder"
    TAP_INSTALL_NS="tap-install"
    GATEWAY_NS="scgw-system"
    API_PORTAL_NS="api-portal"
    BROWNFIELD_NS="brownfield-apis"
    ALV_NS="app-live-view"
    TAP_VERSION="0.2.0"
    KAPP_CONTROLER_VERSION="v0.27.0"
    SECRET_GEN_VERSION="v0.5.0"
    CERT_MANAGER_VERSION="v1.5.3"
    FLUX_VERSION="v0.15.4"

#################### installers ################

    #install-standard
    install-standard() {

        setup-cluster
        
        install-tap-core

        install-tap-products

        install-gw-helm

        install-api-portal-helm

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
 
    #install tap-core
    install-tap-core () {

        echo
        echo "===> Install TAP core components..."
        echo
        
        kapp deploy -y -a kc -f https://github.com/vmware-tanzu/carvel-kapp-controller/releases/download/$KAPP_CONTROLER_VERSION/release.yml

        kapp deploy -y -a sg -f https://github.com/vmware-tanzu/carvel-secretgen-controller/releases/download/$SECRET_GEN_VERSION/release.yml

        kapp deploy -y -a cert-manager -f https://github.com/jetstack/cert-manager/releases/download/$CERT_MANAGER_VERSION/cert-manager.yaml

        #flux source controller
        kubectl create namespace flux-system
        kubectl create clusterrolebinding default-admin \
            --clusterrole=cluster-admin \
            --serviceaccount=flux-system:default
        kapp deploy -y -a flux-source-controller -n flux-system \
            -f https://github.com/fluxcd/source-controller/releases/download/$FLUX_VERSION/source-controller.crds.yaml \
            -f https://github.com/fluxcd/source-controller/releases/download/$FLUX_VERSION/source-controller.deployment.yaml
        
        tanzu imagepullsecret add tap-registry \
            --username $TANZU_NETWORK_USER --password $TANZU_NETWORK_PASSWORD \
            --registry registry.tanzu.vmware.com \
            --export-to-all-namespaces --namespace $TAP_INSTALL_NS  

        tanzu package repository add tanzu-tap-repository \
            --url registry.tanzu.vmware.com/tanzu-application-platform/tap-packages:$TAP_VERSION \
            --namespace $TAP_INSTALL_NS

        wait-for-reconciler

    }

    #install-tap prodcuts
    install-tap-products () {

        echo
        echo "===> Install Tanzu products as TAP packages..."
        echo

        #cnr
        tanzu package install cloud-native-runtimes -p cnrs.tanzu.vmware.com -v 1.0.2 -n $TAP_INSTALL_NS -f .config/cnr-values.yaml --poll-timeout 30m
        kubectl patch configmap/config-domain --namespace knative-serving --type merge --patch '{"data":{"cnr.dekt.io":""}}'
        scripts/update-dns.sh "envoy" "contour-external" "*.cnr"

        #acc
        echo
        tanzu package install app-accelerator -p accelerator.apps.tanzu.vmware.com -v 0.3.0 -n $TAP_INSTALL_NS -f .config/acc-values.yaml
        #kubectl apply -f .config/acc-ingress.yaml -n accelerator-system
        scripts/apply-ingress.sh "acc" "acc-ui-server" "80" "accelerator-system"

        #convention service
        echo
        tanzu package install convention-controller -p controller.conventions.apps.tanzu.vmware.com -v 0.4.2 -n $TAP_INSTALL_NS

        #source controller
        echo
        tanzu package install source-controller -p controller.source.apps.tanzu.vmware.com -v 0.1.2 -n $TAP_INSTALL_NS

        #tbs
        echo
        tanzu package install tbs -p buildservice.tanzu.vmware.com -v 1.3.0 -n $TAP_INSTALL_NS -f .config/tbs-values.yaml --poll-timeout 30m
        
        #supply-chain
        echo
        tanzu package install cartographer -p cartographer.tanzu.vmware.com -v 0.0.6 -n $TAP_INSTALL_NS
        tanzu package install default-supply-chain -p default-supply-chain.tanzu.vmware.com -v 0.2.0 -n $TAP_INSTALL_NS -f .config/default-supply-chain-values.yaml
        
        #dev conventions
        echo
        tanzu package install developer-conventions -p developer-conventions.tanzu.vmware.com -v 0.2.0 -n $TAP_INSTALL_NS
        
        #alv
        echo
        tanzu package install app-live-view -p appliveview.tanzu.vmware.com -v 0.2.0 -n $TAP_INSTALL_NS -f .config/alv-values.yaml
        #kubectl apply -f .config/alv-ingress.yaml -n $ALV_NS
        scripts/apply-ingress.sh "alv" "application-live-view-5112" "5112" $ALV_NS
        
        #service-binding
        echo
        tanzu package install service-bindings -p service-bindings.labs.vmware.com -v 0.5.0 -n $TAP_INSTALL_NS
        
        #service control plane
        echo
        tanzu package install scp-toolkit -p scp-toolkit.tanzu.vmware.com -v 0.3.0 -n $TAP_INSTALL_NS 
       
    }

    #install tap-security-tools
    install-tap-security-tools () {

        echo
        echo "===> Install TAP security tools..."
        echo

        #supply-chain store
        echo
        tanzu package install metadata-store -p scst-store.tanzu.vmware.com -v 1.0.0-beta.0 -n $TAP_INSTALL_NS -f .config/scst-store-values.yaml

        #supply-chain sign image policy
        echo
        tanzu package install image-policy-webhook -p image-policy-webhook.signing.run.tanzu.vmware.com -v 1.0.0-beta.0 -n $TAP_INSTALL_NS -f .config/scst-sign-values.yaml
        kubectl create secret docker-registry image-policy-secret --docker-server=$PRIVATE_REGISTRY_URL  --docker-username=$PRIVATE_REGISTRY_USER --docker-password=$PRIVATE_REGISTRY_PASSWORD --namespace image-policy-system
        kubectl apply -f .config/private-registry-sa.yaml
        kubectl apply -f .config/dev-imagepolicy.yaml

        #supply-chain scan controller
        echo
        kubectl apply -f .config/metadata-store-sa.yaml -n metadata-store 
        kubectl create namespace scan-link-system
        kubectl apply -f .config/metadata-store-secret.yaml
        tanzu package install scan-controller -p scanning.apps.tanzu.vmware.com -v 1.0.0-beta  -n $TAP_INSTALL_NS -f .config/scst-scan-controller-values.yaml

        #supply-chain Grype scanner
        echo
        tanzu package install grype-scanner -p grype.scanning.apps.tanzu.vmware.com -v 1.0.0-beta -n $TAP_INSTALL_NS 


    }

    #install-gw-helm
    install-gw-helm() {
        
        echo
        echo "===> Installing Spring Cloud Gateway operator using HELM..."
        echo
    
        kubectl create secret docker-registry spring-cloud-gateway-image-pull-secret \
            --docker-server=$PRIVATE_REGISTRY_URL \
            --docker-username=$PRIVATE_REGISTRY_USER \
            --docker-password=$PRIVATE_REGISTRY_PASSWORD \
            --namespace $GATEWAY_NS

        #$GW_INSTALL_DIR/scripts/relocate-images.sh $PRIVATE_REGISTRY_URL/$PRIVATE_REGISTRY_SYSTEM_REPO
        
        $GW_INSTALL_DIR/scripts/install-spring-cloud-gateway.sh --namespace $GATEWAY_NS

                
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
        
        #$API_PORTAL_INSTALL_DIR/scripts/relocate-images.sh $PRIVATE_REGISTRY_URL/$PRIVATE_REGISTRY_SYSTEM_REPO

        $API_PORTAL_INSTALL_DIR/scripts/install-api-portal.sh
       
        kubectl set env deployment.apps/api-portal-server API_PORTAL_SOURCE_URLS_CACHE_TTL_SEC=10 -n $API_PORTAL_NS #so frontend apis will appear faster, just for this demo

        kubectl set env deployment.apps/api-portal-server API_PORTAL_SOURCE_URLS=http://scg-openapi.$SUB_DOMAIN.$DOMAIN/openapi -n $API_PORTAL_NS
        
        #kubectl apply -f .config/api-portal-ingress.yaml -n $API_PORTAL_NS
        scripts/apply-ingress.sh "api-portal" "api-portal-server" "8080" $API_PORTAL_NS
        
        #kubectl apply -f .config/scg-openapi-ingress.yaml -n $GATEWAY_NS
        scripts/apply-ingress.sh "scg-openapi" "scg-operator" "80" $GATEWAY_NS
      
    }

#################### demo examples ################

    #setup-demo-examples
    setup-demo-examples() {

        echo
        echo "===> Setup APIGrid demo examples..."
        echo

        #used for both TBS standalone and the TAP supplychain
        export REGISTRY_PASSWORD=$PRIVATE_REGISTRY_PASSWORD
        kp secret create private-registry-creds \
            --registry $PRIVATE_REGISTRY_URL \
            --registry-user $PRIVATE_REGISTRY_USER \
            --namespace $DEMO_APPS_NS 

        kubectl apply -f .config/supplychain-rbac.yaml -n $DEMO_APPS_NS

        kubectl apply -f workloads/accelerators.yaml -n accelerator-system #must be same as .config/acc-values.yaml   watched_namespace:

        create-dekt4pets-images
        
        create-api-examples
       
    }

    #create dekt4pets images
    create-dekt4pets-images () {

        frontend_image_location=$PRIVATE_REGISTRY_URL/$PRIVATE_REGISTRY_APP_REPO/$FRONTEND_TBS_IMAGE:$APP_VERSION
        backend_image_location=$PRIVATE_REGISTRY_URL/$PRIVATE_REGISTRY_APP_REPO/$BACKEND_TBS_IMAGE:$APP_VERSION
    
        kp image create $BACKEND_TBS_IMAGE -n $DEMO_APPS_NS \
        --tag $backend_image_location \
        --git $DEMO_APP_GIT_REPO  \
        --sub-path ./workloads/dekt4pets/backend \
        --git-revision main

        scripts/wait-for-tbs.sh $BACKEND_TBS_IMAGE $DEMO_APPS_NS
        kp build logs $BACKEND_TBS_IMAGE -n $DEMO_APPS_NS
                
        kp image save $FRONTEND_TBS_IMAGE -n $DEMO_APPS_NS \
        --tag $frontend_image_location \
        --git $DEMO_APP_GIT_REPO  \
        --sub-path ./workloads/dekt4pets/frontend \
        --git-revision main 

        scripts/wait-for-tbs.sh $FRONTEND_TBS_IMAGE $DEMO_APPS_NS
        kp build logs $FRONTEND_TBS_IMAGE -n $DEMO_APPS_NS

    }
    
    #create-api-examples
    create-api-examples() {

        kustomize build workloads/brownfield-apis | kubectl apply -f -

        kubectl create secret generic sso-secret --from-env-file=.config/sso-creds.txt -n $DEMO_APPS_NS
        kubectl create secret generic jwk-secret --from-env-file=.config/jwk-creds.txt -n $DEMO_APPS_NS
        kubectl create secret generic wavefront-secret --from-env-file=.config/wavefront-creds.txt -n $DEMO_APPS_NS

        kubectl apply -f workloads/dekt4pets/gateway/dekt4pets-gateway-dev.yaml -n $DEMO_APPS_NS
        scripts/apply-ingress.sh "dekt4pets-dev" "dekt4pets-gateway-dev" "80" $DEMO_APPS_NS

    }
    
    
#################### misc ################
    
     
    #incorrect usage
    incorrect-usage() {
        
        echo
        echo "Incorrect usage. Please specify one of the following: "
        echo
        echo " init"
        echo " add-DevSecOps"
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
    standard
    ;;
add-DevSecOps)
    install-tap-security-tools
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