#!/usr/bin/env bash


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
    git commit -a -m "done backend inner-loop"
    git push

    echo
    echo "=========> 2. Apply development routes, mapping and micro-gateway"
    echo

    kubectl apply -f workloads/dekt4pets/backend/routes/dekt4pets-backend-mapping-dev.yaml -n $DEMO_APPS_NS
    kubectl apply -f workloads/dekt4pets/backend/routes/dekt4pets-backend-route-config.yaml -n $DEMO_APPS_NS
    #dekt4pets-dev gateway instances created as part of demo build to save time

    echo
    echo "=========> 3. Create backend app via src-to-img supply-chain"
    echo

    #kp image patch $BACKEND_TBS_IMAGE -n $DEMO_APPS_NS

    scripts/wait-for-tbs.sh $BACKEND_TBS_IMAGE $DEMO_APPS_NS

    echo
    echo "Starting to tail build logs ..."
    echo
    
    kp build logs $BACKEND_TBS_IMAGE -n $DEMO_APPS_NS
    
    kubectl apply -f workloads/dekt4pets/backend/dekt4pets-backend.yaml -n $DEMO_APPS_NS
}

#create-frontend 
create-frontend() {
	
    echo
    echo "=========> Create dekt4pets-frontend (inner loop) ..."
    echo "           1. Deploy app via src-to-img supply-chain"
    echo "           2. Apply development routes, mapping and micro-gateway"
    echo

    kp image patch $FRONTEND_TBS_IMAGE -n $DEMO_APPS_NS
    
	kustomize build workloads/dekt4pets/frontend | kubectl apply -f -

}

#patch-backend
patch-backend() {
    
    echo
    echo "=========> Commit code changes to $DEMO_APP_GIT_REPO  ..."
    echo
    
    commit-adopter-check-api

    scripts/wait-for-tbs.sh $BACKEND_TBS_IMAGE $DEMO_APPS_NS

    echo
    echo "Starting to tail build logs ..."
    echo
    
    kp build logs $BACKEND_TBS_IMAGE -n $DEMO_APPS_NS
    
    echo
    echo "=========> Apply changes to backend app, service and routes ..."
    echo
    
    kubectl delete -f workloads/dekt4pets/backend/dekt4pets-backend.yaml -n $DEMO_APPS_NS
    kubectl apply -f workloads/dekt4pets/backend/dekt4pets-backend.yaml -n $DEMO_APPS_NS
    kubectl apply -f workloads/dekt4pets/backend/routes/dekt4pets-backend-route-config.yaml -n $DEMO_APPS_NS

}

#dekt4pets
dekt4pets() {

    echo
    echo "=========> Promote dekt4pets-backend to production (outer loop) ..."
    echo "           1. Deploy app via src-to-img supply-chain"
    echo "           2. Apply production routes, mapping and micro-gateway"
    echo
    kubectl apply -f workloads/dekt4pets/backend/routes/dekt4pets-backend-mapping.yaml -n $DEMO_APPS_NS

    echo
    echo "=========> Promote dekt4pets-frontend to production (outer loop) ..."
    echo "           1. Deploy app via src-to-img supply-chain"
    echo "           2. Apply production routes, mapping and micro-gateway"
    echo
    kubectl apply -f workloads/dekt4pets/frontend/routes/dekt4pets-frontend-mapping.yaml -n $DEMO_APPS_NS

    echo
    echo "=========> Create dekt4pets micro-gateway (w/ external traffic)..."
    echo
    kubectl apply -f workloads/dekt4pets/gateway/dekt4pets-gateway.yaml -n $DEMO_APPS_NS
    scripts/apply-ingress.sh "dekt4pets" "dekt4pets-gateway" "80" $DEMO_APPS_NS

    adopter-check
}

#deploy-fitness app
create-fitness () {

    pushd workloads/dektFitness

    kustomize build kubernetes-manifests/ | kubectl apply -f -
}

#adopter-check-workload
adopter-check () {

    echo
    echo "=========> Apply adopter-check TAP workload and deploy via src-to-url supply-chain ..."
    echo

    tanzu apps workload apply adopter-check -f workloads/dekt4pets/adopter-check-workload.yaml -y -n $DEMO_APPS_NS

    #tanzu apps workload tail adopter-check --since 10m --timestamp  -n dekt-apps

    tanzu apps workload get adopter-check -n dekt-apps

}

update-adopter-check-pre-TAP () {

    echo

    wait-for-tbs $ADOPTER_CHECK_TBS_IMAGE

    echo
    echo "Starting to tail build logs ..."
    echo

    kp build logs $ADOPTER_CHECK_TBS_IMAGE -n $APP_NAMESPACE

    kn service update $ADOPTER_CHECK_TBS_IMAGE \
        --image $ADOPTER_CHECK_IMAGE_LOCATION \
        --env REV="2.0" \
        --revision-name adopter-check-v2 \
        --traffic adopter-check-v2=70,adopter-check-v1=30 \
        --namespace $APP_NAMESPACE

    kn service describe adopter-check -n $APP_NAMESPACE
}

#commit-adopter-check-api
commit-adopter-check-api () {

    git commit -m "add check-adpoter api route" workloads/dekt4pets/backend/routes/dekt4pets-backend-route-config.yaml

    git commit -m "add check-adpoter function" workloads/dekt4pets/backend/src/main/java/io/spring/cloud/samples/animalrescue/backend/AnimalController.java

    git push
}

#cleanup
cleanup() {

    echo
    echo "=========> Remove all workloads..."
    echo

    #kustomize build workloads/dekt4pets/gateway | kubectl delete -f -  
    kubectl delete -f workloads/dekt4pets/backend/routes/dekt4pets-backend-mapping-dev.yaml -n $DEMO_APPS_NS
    kubectl delete -f workloads/dekt4pets/backend/routes/dekt4pets-backend-route-config.yaml -n $DEMO_APPS_NS
    kubectl delete -f workloads/dekt4pets/backend/dekt4pets-backend.yaml -n $DEMO_APPS_NS

    kustomize build workloads/dekt4pets/frontend | kubectl delete -f -  
    kubectl delete -f workloads/dekt4pets/backend/routes/dekt4pets-backend-mapping.yaml -n $DEMO_APPS_NS
    kubectl delete -f workloads/dekt4pets/frontend/routes/dekt4pets-frontend-mapping.yaml -n $DEMO_APPS_NS

    kustomize build workloads/dektFitness/kubernetes-manifests/ | kubectl delete -f -  

    tanzu apps workload delete adopter-check -y -n $DEMO_APPS_NS 

}

#usage
usage() {

    echo
	echo "Incorrect usage. Please specify one of the following:"
	echo
    echo "${bold}describe${normal} - deploy the dekt4pets supply chain components"
    echo
    echo "${bold}backend${normal} - deploy the dekt4pets backend service and APIs"
    echo "          (use -u for update)"
    echo
    echo "${bold}frontend${normal} - deploy the dekt4pets frotend service and APIs"
    echo
    echo "${bold}dekt4pets${normal} - run end-to-end dekt4pets deployment to production"
    echo
    echo "${bold}adopter-check${normal} - deploy the adopter-check TAP workload using the default supply-chain"
    echo
    echo "${bold}fitness${normal} - deploy the Fitenss app, services and APIs"
    echo 
  	exit   
 
}

#describe-supplychain
describe-supplychain() {

    echo
    echo "${bold}Dekt4pets supply-chain components${normal}"
    echo "-------------------------------------"
    echo
    echo "${bold}Installed TAP packages${normal}"
    echo
    kubectl get pkgi -n $TAP_INSTALL_NS
    echo
    echo "${bold}Supply chains${normal}"
    echo
    tanzu apps cluster-supply-chain list
    echo
    echo "${bold}Workload Images${normal}"
    echo
    kp images list -n $DEMO_APPS_NS
    echo
    echo "${bold}API configs${normal}"
    echo
    echo "NAME                              KIND                "
    echo "dekt4pets-backend-routes          api-routes          "
    echo "dekt4pets-backend-mapping-dev     route-mapping       "
    echo "dekt4pets-backend-mapping         route-mapping       "
    echo
    echo "dekt4pets-frontend-routes         api-routes          "
    echo "dekt4pets-frontend-mapping-dev    route-mapping       "
    echo "dekt4pets-frontend-mapping        route-mapping       "
    echo
    echo "dekt4pets-gateway-dev             gateway-config      "
    echo "dekt4pets-gateway                 gateway-config      "
    echo "dekt4pets-ingress                 ingress-rule        "
    echo
    echo "dekt4pets-openapi                 ingress-rule        "
    echo "brownfield-openapi                ingress-rule        "
}

#describe-apigrid
describe-apigrid() {

    echo
    echo "${bold}Dekt4pets api-grid components${normal}"
    echo "-------------------------------------"
    echo
    echo "${bold}API Routes${normal}"
    echo
    kubectl get SpringCloudGatewayRouteConfig -n $DEMO_APPS_NS 
    echo
    echo "${bold}API Mappings${normal}"
    echo
    kubectl get SpringCloudGatewayMapping -n $DEMO_APPS_NS 
    echo
    echo "${bold}API Gateways${normal}"
    echo
    
    echo
    echo "${bold}Ingress rules${normal}"
    kubectl get ingress --field-selector metadata.name=dekt4pets-ingress -n $DEMO_APPS_NS
    echo
}

#################### main #######################

source .config/config-values.env

bold=$(tput bold)
normal=$(tput sgr0)

case $1 in
backend)
	if [ "$2" == "-u" ]
    then
        patch-backend
    else
        create-backend
    fi
    ;;
frontend)
	create-frontend
    ;;
dekt4pets)
    dekt4pets
    ;;
adopter-check)
	adopter-check
    ;;
describe)
    describe-supplychain
    ;;
fitness)
	create-fitness $2
    ;;
cleanup)
    cleanup
    ;;
*)
  	usage
  	;;
esac
