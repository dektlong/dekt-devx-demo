#!/usr/bin/env bash

#################### configs #######################

    source .config/config-values.env
    
    BUILDER_NAME="online-stores-builder"
    GATEWAY_NS="scgw-system"
    API_PORTAL_NS="api-portal"
    BROWNFIELD_NS="brownfield-apis"
    
    TAP_VERSION="0.3.0"
    KAPP_CONTROLER_VERSION="v0.29.0"
    SECRET_GEN_VERSION="v0.6.0"

#################### installers ################

    #install-all
    install-all() {

        install-tap

        install-api-gateway

        install-api-portal #still needed until portal can be installed in its own ns
        
        setup-dekt-apigrid
        
        echo
        echo "Demo install completed. Enjoy your demo."
        echo

    }

     
    #install tap with 'full' profile
    install-tap () {

        echo
        echo "===> Setup TAP prerequisites.."
        echo
        
        kubectl create ns $TAP_INSTALL_NS
        kubectl create ns $DEMO_APPS_NS
        
        kapp deploy -y -a kc -f https://github.com/vmware-tanzu/carvel-kapp-controller/releases/download/$KAPP_CONTROLER_VERSION/release.yml

        kapp deploy -y -a sg -f https://github.com/vmware-tanzu/carvel-secretgen-controller/releases/download/$SECRET_GEN_VERSION/release.yml

        tanzu secret registry add tap-registry \
            --username $TANZU_NETWORK_USER --password $TANZU_NETWORK_PASSWORD \
            --server registry.tanzu.vmware.com \
            --export-to-all-namespaces --yes --namespace $TAP_INSTALL_NS

        tanzu package repository add tanzu-tap-repository \
            --url registry.tanzu.vmware.com/tanzu-application-platform/tap-packages:$TAP_VERSION \
            --namespace $TAP_INSTALL_NS

        wait-for-reconciler

        

        echo
        echo "===> Install TAP with 'full' packages profile..."
        echo

        tanzu package install tap -p tap.tanzu.vmware.com -v $TAP_VERSION  --values-file .config/tap-values.yml -n $TAP_INSTALL_NS

            #for install status use:
            #watch "kubectl get pkgi -n tap-install"

        add-tap-ingress-rules

    }

    #install-tap packages (for use without profile)
    install-tap-seperate-packages () {

        echo
        echo "===> Install Tanzu products as TAP packages..."
        echo

        #cnr
        tanzu package install cloud-native-runtimes -p cnrs.tanzu.vmware.com -v 1.0.2 -n $TAP_INSTALL_NS -f .config/cnr-values.yaml --poll-timeout 30m

        #acc
        echo
        tanzu package install app-accelerator -p accelerator.apps.tanzu.vmware.com -v 0.3.0 -n $TAP_INSTALL_NS -f .config/acc-values.yaml
        #kubectl apply -f .config/acc-ingress.yaml -n accelerator-system

        #convention service
        echo
        tanzu package install convention-controller -p controller.conventions.apps.tanzu.vmware.com -v 0.4.2 -n $TAP_INSTALL_NS

        #source controller
        echo
        tanzu package install source-controller -p controller.source.apps.tanzu.vmware.com -v 0.1.2 -n $TAP_INSTALL_NS

        #tbs
        echo
        tanzu package install tbs -p buildservice.tanzu.vmware.com -v 1.3.0 -n $TAP_INSTALL_NS -f .config/tbs-values.yaml --poll-timeout 30m
        
        #carto
        echo
        tanzu package install cartographer -p cartographer.tanzu.vmware.com -v 0.0.6 -n $TAP_INSTALL_NS
        
        #dev conventions
        echo
        tanzu package install developer-conventions -p developer-conventions.tanzu.vmware.com -v 0.2.0 -n $TAP_INSTALL_NS
        
        #alv
        echo
        tanzu package install app-live-view -p appliveview.tanzu.vmware.com -v 0.2.0 -n $TAP_INSTALL_NS -f .config/alv-values.yaml
        
        #service-binding
        echo
        tanzu package install service-bindings -p service-bindings.labs.vmware.com -v 0.5.0 -n $TAP_INSTALL_NS
        
        #service control plane
        echo
        tanzu package install scp-toolkit -p scp-toolkit.tanzu.vmware.com -v 0.3.0 -n $TAP_INSTALL_NS 

        install-tap-security-tools
       
    }

    #install-api-gateway
    install-api-gateway () {

        echo
        echo "===> Installing Spring Cloud Gateway operator using HELM..."
        echo

        kubectl create ns $GATEWAY_NS

        kubectl create secret docker-registry spring-cloud-gateway-image-pull-secret \
            --docker-server=$PRIVATE_REGISTRY_URL \
            --docker-username=$PRIVATE_REGISTRY_USER \
            --docker-password=$PRIVATE_REGISTRY_PASSWORD \
            --namespace $GATEWAY_NS

        #$GW_INSTALL_DIR/scripts/relocate-images.sh $PRIVATE_REGISTRY_URL/$PRIVATE_REGISTRY_SYSTEM_REPO
        
        $GW_INSTALL_DIR/scripts/install-spring-cloud-gateway.sh --namespace $GATEWAY_NS

        scripts/apply-ingress.sh "scg-openapi" "scg-operator" "80" $GATEWAY_NS
    }

    #install-api-portal (not via TAP)
    install-api-portal () {
    
        echo
        echo "===> Installing API portal using helm..."
        echo

        kubectl create ns $API_PORTAL_NS

        kubectl create secret docker-registry api-portal-image-pull-secret \
            --docker-server=$PRIVATE_REGISTRY_URL \
            --docker-username=$PRIVATE_REGISTRY_USER \
            --docker-password=$PRIVATE_REGISTRY_PASSWORD \
            --namespace $API_PORTAL_NS
      
        kubectl create secret generic sso-credentials --from-env-file=.config/sso-creds.txt -n $API_PORTAL_NS
        
        #$API_PORTAL_INSTALL_DIR/scripts/relocate-images.sh $PRIVATE_REGISTRY_URL/$PRIVATE_REGISTRY_SYSTEM_REPO

        $API_PORTAL_INSTALL_DIR/scripts/install-api-portal.sh
       
        kubectl set env deployment.apps/api-portal-server API_PORTAL_SOURCE_URLS_CACHE_TTL_SEC=10 -n $API_PORTAL_NS #so frontend apis will appear faster, just for this demo

        kubectl set env deployment.apps/api-portal-server API_PORTAL_SOURCE_URLS=http://scg-openapi.$APPS_SUB_DOMAIN.$DOMAIN/openapi -n $API_PORTAL_NS

        scripts/apply-ingress.sh "api-portal" "api-portal-server" "8080" $API_PORTAL_NS

    }

    #setup-dekt-apigrid
    setup-dekt-apigrid () {

        echo
        echo "===> Setup APIGrid demo examples..."
        echo

        #accelerators
            #kubectl apply -f supplychain/accelerators.yaml -n $DEMO_APPS_NS
        kubectl apply -f supplychain/accelerators.yaml

        #supplychain
        kubectl apply -f .config/supplychain-rbac.yaml -n $DEMO_APPS_NS
        tanzu secret registry add registry-credentials --server $PRIVATE_REGISTRY_URL --username $PRIVATE_REGISTRY_USER --password $PRIVATE_REGISTRY_PASSWORD -n $DEMO_APPS_NS

        #brownfield
        kubectl create ns $BROWNFIELD_NS
        kustomize build workloads/brownfield-apis | kubectl apply -f -

        #devx-mood
        tanzu apps workload apply devx-mood -f workloads//devx-mood-workload.yaml -n $DEMO_APPS_NS

        #dekt4pets
        kubectl create secret generic sso-secret --from-env-file=.config/sso-creds.txt -n $DEMO_APPS_NS
        kubectl create secret generic jwk-secret --from-env-file=.config/jwk-creds.txt -n $DEMO_APPS_NS
        kubectl create secret generic wavefront-secret --from-env-file=.config/wavefront-creds.txt -n $DEMO_APPS_NS

        kubectl apply -f workloads/dekt4pets/gateway/dekt4pets-gateway-dev.yaml -n $DEMO_APPS_NS

        scripts/apply-ingress.sh "dekt4pets-dev" "dekt4pets-gateway-dev" "80" $DEMO_APPS_NS

        create-dekt4pets-images

    }

    #create dekt4pets images
    create-dekt4pets-images () {


        frontend_image_location=$PRIVATE_REGISTRY_URL/$PRIVATE_REGISTRY_APP_REPO/$FRONTEND_TBS_IMAGE:$APP_VERSION
        backend_image_location=$PRIVATE_REGISTRY_URL/$PRIVATE_REGISTRY_APP_REPO/$BACKEND_TBS_IMAGE:$APP_VERSION

        export REGISTRY_PASSWORD=$PRIVATE_REGISTRY_PASSWORD
        kp secret create private-registry-creds \
            --registry $PRIVATE_REGISTRY_URL \
            --registry-user $PRIVATE_REGISTRY_USER \
            --namespace $DEMO_APPS_NS 
    
        echo
        echo "===> Create dekt4pets-backend TBS image..."
        echo

        kp image create $BACKEND_TBS_IMAGE -n $DEMO_APPS_NS \
        --tag $backend_image_location \
        --git $DEMO_APP_GIT_REPO  \
        --sub-path ./workloads/dekt4pets/backend \
        --git-revision main

        scripts/wait-for-tbs.sh $BACKEND_TBS_IMAGE $DEMO_APPS_NS
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
    add-tap-ingress-rules() {

        echo
        echo "===> Add ingress rules for TAP components..."
        echo

        scripts/apply-ingress.sh "acc" "acc-ui-server" "80" "accelerator-system"
        
        scripts/apply-ingress.sh "tap-gui" "server" "7000" "tap-gui"
        
        scripts/apply-ingress.sh "alv" "application-live-view-5112" "5112" "app-live-view"
        
        kubectl patch configmap/config-domain \
            --namespace knative-serving \
            --type merge \
            --patch '{"data":{"'$SERVING_SUB_DOMAIN.$DOMAIN'":""}}'
        
        scripts/update-dns.sh "envoy" "contour-external" "*.$SERVING_SUB_DOMAIN"
    }
    
    #update-tap
    update-tap () {

        tanzu package installed update tap --package-name tap.tanzu.vmware.com --version 0.3.0 -n $TAP_INSTALL_NS -f .config/tap-values.yml
    }
#################### misc ################
    
     
    #incorrect usage
    incorrect-usage() {
        
        echo
        echo "Incorrect usage. Please specify one of the following: "
        echo
        echo " init-aks"
        echo " init-eks"
        echo
        echo " cleanup-aks"
        echo " cleanup-eks"
        echo 
        echo " runme [function-name]"
        echo
    
    }

    update-tap-gui () {

        kubectl get svc -n tap-gui

        read -p "update the ip in tap-values.yaml...then hit any key"

        tanzu package installed update tap --package-name tap.tanzu.vmware.com --version 0.3.0 -n tap-install -f .config/tap-values.yml

        kubectl delete pod -l app=backstage -n tap-gui


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
init-aks)
    scripts/build-aks-cluster.sh create $CLUSTER_NAME 7 
    install-all 
    ;;
init-eks)
	scripts/build-eks-cluster.sh create $CLUSTER_NAME
    install-all 
    ;;
cleanup-aks)
    scripts/build-aks-cluster.sh delete $CLUSTER_NAME 
    ;;
cleanup-eks)
    scripts/build-eks-cluster.sh delete $CLUSTER_NAME
    ;;
runme)
    $2
    ;;
*)
    incorrect-usage
    ;;
esac