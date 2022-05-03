#!/usr/bin/env bash

PRIVATE_REPO=$(yq e .ootb_supply_chain_basic.registry.server .config/tap-values-full.yaml)
PRIVATE_REPO_USER=$(yq e .buildservice.kp_default_repository_username .config/tap-values-full.yaml)
PRIVATE_REPO_PASSWORD=$(yq e .buildservice.kp_default_repository_password .config/tap-values-full.yaml)
DEMO_APP_GIT_REPO="https://github.com/dektlong/APIGridDemo"
BUILDER_NAME="online-stores-builder"
BACKEND_TBS_IMAGE="dekt4pets-backend"
FRONTEND_TBS_IMAGE="dekt4pets-frontend"
APPS_NAMESPACE=$(yq .tap.appNamespace .config/demo-values.yaml)
DEV_SUB_DOMAIN=$(yq .cnrs.domain_name .config/tap-values-full.yaml | cut -d'.' -f 1)

#init (assumes api-portal and api-gw are installed)
init() {

        echo "!!! currently only working on AKS due to SCGW issue. Hit any key to continue..."
        read
        #dekt4pets images
        frontend_image_location=$PRIVATE_REPO/$PRIVATE_REGISTRY_APP_REPO/$FRONTEND_TBS_IMAGE:0.0.1
        backend_image_location=$PRIVATE_REPO/$PRIVATE_REGISTRY_APP_REPO/$BACKEND_TBS_IMAGE:0.0.1

        export REGISTRY_PASSWORD=$PRIVATE_REPO_PASSWORD
        kp secret create private-registry-creds \
            --registry $PRIVATE_REPO \
            --registry-user $PRIVATE_REPO_USER \
            --namespace $APPS_NAMESPACE 

    
        kp image create $BACKEND_TBS_IMAGE -n $APPS_NAMESPACE \
        --tag $backend_image_location \
        --git $DEMO_APP_GIT_REPO  \
        --sub-path ./workloads/dekt4pets/backend \
        --git-revision main \
        --wait
       

        kp image save $FRONTEND_TBS_IMAGE -n $APPS_NAMESPACE \
        --tag $frontend_image_location \
        --git $DEMO_APP_GIT_REPO  \
        --sub-path ./workloads/dekt4pets/frontend \
        --git-revision main \
        --wait

        #dekt4pets secrets
        kubectl create secret generic sso-secret --from-env-file=.config/sso-creds.txt -n $APPS_NAMESPACE
        kubectl create secret generic jwk-secret --from-env-file=.config/jwk-creds.txt -n $APPS_NAMESPACE
        kubectl create secret generic wavefront-secret --from-env-file=.config/wavefront-creds.txt -n $APPS_NAMESPACE

        #dev gateway and apps
        kubectl apply -f workloads/dekt4pets/gateway/dekt4pets-gateway-dev.yaml -n $APPS_NAMESPACE
        create-backend
        create-frontend

        #ingress rules
        scripts/ingress-handler.sh add-scgw-ingress $DEV_SUB_DOMAIN

}

#create-backend 
create-backend() {

    echo
    echo "${bold}Deploy dekt4pets-backend (inner loop)${normal}"
    echo "------------------------------------------"
    echo
   
    echo
    echo "=========> 1. Commit code changes to $DEMO_APP_GIT_REPO"
    echo            
    
    touch dummy-commit.me

    git add .
    git commit -q -m "done backend inner-loop" dummy-commit.me
    git push

    echo
    echo "=========> 2. Apply development routes, mapping and micro-gateway"
    echo

    kubectl apply -f workloads/dekt4pets/backend/routes/dekt4pets-backend-mapping-dev.yaml -n $APPS_NAMESPACE
    kubectl apply -f workloads/dekt4pets/backend/routes/dekt4pets-backend-route-config.yaml -n $APPS_NAMESPACE
    #dekt4pets-dev gateway instances created as part of demo build to save time

    echo
    echo "=========> 3. Create backend app via src-to-img supply-chain"
    echo

    #kp image patch $BACKEND_TBS_IMAGE -n $APPS_NAMESPACE

    #wait-for-tbs $BACKEND_TBS_IMAGE $APPS_NAMESPACE

    echo
    echo "Starting to tail build logs ..."
    echo
    
    kp build logs $BACKEND_TBS_IMAGE -n $APPS_NAMESPACE
    
    kubectl apply -f workloads/dekt4pets/backend/dekt4pets-backend.yaml -n $APPS_NAMESPACE
}

#create-frontend 
create-frontend() {
	
    echo
    echo "=========> Create dekt4pets-frontend (inner loop) ..."
    echo "           1. Deploy app via src-to-img supply-chain"
    echo "           2. Apply development routes, mapping and micro-gateway"
    echo

    kp image patch $FRONTEND_TBS_IMAGE -n $APPS_NAMESPACE
    
	kustomize build workloads/dekt4pets/frontend | kubectl apply -f -

}

#patch-backend
patch-backend() {
    
    echo
    echo "=========> Commit code changes to $DEMO_APP_GIT_REPO  ..."
    echo
    
    commit-adopter-check-api

    wait-for-tbs $BACKEND_TBS_IMAGE $APPS_NAMESPACE

    echo
    echo "Starting to tail build logs ..."
    echo
    
    kp build logs $BACKEND_TBS_IMAGE -n $APPS_NAMESPACE
    
    echo
    echo "=========> Apply changes to backend app, service and routes ..."
    echo
    
    kubectl delete -f workloads/dekt4pets/backend/dekt4pets-backend.yaml -n $APPS_NAMESPACE
    kubectl apply -f workloads/dekt4pets/backend/dekt4pets-backend.yaml -n $APPS_NAMESPACE
    kubectl apply -f workloads/dekt4pets/backend/routes/dekt4pets-backend-route-config.yaml -n $APPS_NAMESPACE

}

#dekt4pets
dekt4pets() {

    echo
    echo "=========> Promote dekt4pets-backend to production (outer loop) ..."
    echo "           1. Deploy app via src-to-img supply-chain"
    echo "           2. Apply production routes, mapping and micro-gateway"
    echo
    kubectl apply -f workloads/dekt4pets/backend/routes/dekt4pets-backend-mapping.yaml -n $APPS_NAMESPACE

    echo
    echo "=========> Promote dekt4pets-frontend to production (outer loop) ..."
    echo "           1. Deploy app via src-to-img supply-chain"
    echo "           2. Apply production routes, mapping and micro-gateway"
    echo
    kubectl apply -f workloads/dekt4pets/frontend/routes/dekt4pets-frontend-mapping.yaml -n $APPS_NAMESPACE

    echo
    echo "=========> Create dekt4pets micro-gateway (w/ external traffic)..."
    echo
    kubectl apply -f workloads/dekt4pets/gateway/dekt4pets-gateway.yaml -n $APPS_NAMESPACE

}

#adopter-check-workload
adopter-check () {

    echo
    echo "=========> Apply adopter-check TAP workload and deploy via src-to-url supply-chain ..."
    echo

    tanzu apps workload apply adopter-check -f adopter-check-workload.yaml -y -n $APPS_NAMESPACE

    #tanzu apps workload tail adopter-check --since 10m --timestamp  -n dekt-apps

    tanzu apps workload get adopter-check -n dekt-apps

}

#commit-adopter-check-api
commit-adopter-check-api () {

    git commit -m "add check-adpoter api route" workloads/dekt4pets/backend/routes/dekt4pets-backend-route-config.yaml

    git commit -m "add check-adpoter function" workloads/dekt4pets/backend/src/main/java/io/spring/cloud/samples/animalrescue/backend/AnimalController.java

    git push
}

#cleanup
cleanup() {

    kp secret delete private-registry-creds -n $APPS_NAMESPACE
    kubectl delete secret sso-secret -n $APPS_NAMESPACE
    kubectl delete secret jwk-secret -n $APPS_NAMESPACE
    kubectl delete secret wavefront-secret -n $APPS_NAMESPACE
    kp image delete $BACKEND_TBS_IMAGE -n $APPS_NAMESPACE
    kp image delete $FRONTEND_TBS_IMAGE -n $APPS_NAMESPACE
    kubectl delete -f workloads/dekt4pets/backend/dekt4pets-backend.yaml -n $APPS_NAMESPACE
    kubectl delete -f workloads/dekt4pets/backend/routes/dekt4pets-backend-mapping.yaml -n $APPS_NAMESPACE
    kubectl delete -f workloads/dekt4pets/frontend/routes/dekt4pets-frontend-mapping.yaml -n $APPS_NAMESPACE
    kubectl delete -f workloads/dekt4pets/gateway/dekt4pets-gateway.yaml -n $APPS_NAMESPACE
    kubectl delete -f workloads/dekt4pets/gateway/dekt4pets-gateway-dev.yaml -n $APPS_NAMESPACE
    kubectl delete -f workloads/dekt4pets/backend/routes/dekt4pets-backend-mapping-dev.yaml -n $APPS_NAMESPACE
    kubectl delete -f workloads/dekt4pets/backend/routes/dekt4pets-backend-route-config.yaml -n $APPS_NAMESPACE
    kustomize build workloads/dekt4pets/frontend | kubectl delete -f -


    rm dummy-commit.me

}

#wait4tbs
wait-for-tbs() {
    image_name=$1
    namespace=$2

    status=""
    printf "Waiting for tanzu build service to start building $image_name image in namespace $namespace"
    while [ "$status" == "" ]
    do
        printf "."
        status="$(kp image status $image_name -n $namespace | grep 'Building')" 
        sleep 1
    done
    echo
}

#usage
usage() {

    echo
	echo "Incorrect usage. Please specify one of the following:"
	echo
    echo "${bold}init${normal} - deploy the dekt4pets api-grid core components and dekt4petsdev instances"
    echo
    echo "${bold}describe${normal} - describe the dekt4pets api-grid configs"
    echo
    echo "${bold}prod-deploy${normal} - run end-to-end dekt4pets deployment to production"
    echo
    echo "${bold}patch-backend${normal} - update the dekt4pets backend service and APIs"
    echo
    echo "${bold}adopter-check${normal} - deploy the adopter-check TAP workload using the default supply-chain"
    echo
    echo "${bold}cleanup${normal} - remove the dekt4pets api-grid core components, dekt4pets dev and prod instances"
    echo
    echo 
  	exit   
 
}

#describe-apigrid
describe-apigrid() {

    echo
    echo "${bold}Dekt4pets api-grid components${normal}"
    echo "-------------------------------------"
    echo
    echo
    echo "${bold}Workload Images${normal}"
    echo
    kp images list -n $APPS_NAMESPACE
    echo "${bold}API Routes${normal}"
    echo
    kubectl get SpringCloudGatewayRouteConfig -n $APPS_NAMESPACE 
    echo
    echo "${bold}API Mappings${normal}"
    echo
    kubectl get SpringCloudGatewayMapping -n $APPS_NAMESPACE 
    echo
    echo "${bold}API Gateways${normal}"
    echo
    
    echo
    echo "${bold}Ingress rules${normal}"
    kubectl get ingress --field-selector metadata.name=dekt4pets-ingress -n $APPS_NAMESPACE
    echo
}

#################### main #######################

bold=$(tput bold)
normal=$(tput sgr0)

case $1 in

init)
    init
    ;;
prod-deploy)
    prod-deploy
    ;;
patch-backend)
	patch-backend
    ;;
adopter-check)
	adopter-check
    ;;
describe)
    describe-apigrid
    ;;
cleanup)
    cleanup
    ;;
*)
  	usage
  	;;
esac
