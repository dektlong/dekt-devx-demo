#!/usr/bin/env bash


#create-backend 
create-backend() {

    echo "Syncing local code with remote git..."
    echo "$DEMO_APP_GIT_REPO/backend remote git synced (no change)"
    echo
    #git-push "local-development-completed"
    #codechanges=$?

    kp image patch $BACKEND_TBS_IMAGE -n $DEMO_APPS_NS
    
    echo
    echo "Apply backend app, service and routes ..."
    kustomize build workloads/dekt4pets/backend | kubectl apply -f -
    
}

#create-frontend 
create-frontend() {
	
    echo "Syncing local code with remote git..."
    echo "$DEMO_APP_GIT_REPO/frontend remote git synced (no change)"
    echo

    kp image patch $FRONTEND_TBS_IMAGE -n $DEMO_APPS_NS

    echo
    echo "Apply frontend app, service and routes ..."
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
    echo "${bold}Dekt4pets supply-chain components${normal}"
    echo "-------------------------------------"

    supply-chain-components

    echo
    echo "${bold}Hit any key to start deploying dekt4pets workloads to production...${normal}"
    echo
    read

    echo
    echo "=========> dekt4pets-backend route mapping change to production gateway ..."
    echo
    kubectl apply -f workloads/dekt4pets/backend/routes/dekt4pets-backend-mapping.yaml -n $DEMO_APPS_NS

    echo
    echo "=========> dekt4pets-frontend route mapping change to production gateway..."
    echo
    kubectl apply -f workloads/dekt4pets/frontend/routes/dekt4pets-frontend-mapping.yaml -n $DEMO_APPS_NS

    echo
    echo "=========> dekt4pets micro-gateway (w/ external traffic)..."
    echo
    kubectl apply -f workloads/dekt4pets/gateway/dekt4pets-gateway.yaml -n $DEMO_APPS_NS
    scripts/apply-ingress.sh "dekt4pets" "dekt4pets-gateway" "80" $DEMO_APPS_NS
}

#deploy-fitness app
create-fitness () {

    pushd workloads/dektFitness

    kustomize build kubernetes-manifests/ | kubectl apply -f -
}

#adopter-check-workload
adopter-check () {

    echo
    echo "=========> Create adopte-check TAP workload and deploy via default supply-chain ..."
    echo

    tanzu apps workload create adopter-check -f workloads/dekt4pets/adopter-check-workload.yaml -y -n $DEMO_APPS_NS

    sleep 5

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

    echo
    echo "=========> Remove all workloads..."
    echo

    #kustomize build workloads/dekt4pets/gateway | kubectl delete -f -  
    kustomize build workloads/dekt4pets/backend | kubectl delete -f -  
    kustomize build workloads/dekt4pets/frontend | kubectl delete -f -  
    kubectl delete -f workloads/dekt4pets/backend/routes/dekt4pets-backend-mapping.yaml -n $DEMO_APPS_NS
    kubectl delete -f workloads/dekt4pets/frontend/routes/dekt4pets-frontend-mapping.yaml -n $DEMO_APPS_NS

    kustomize build workloads/dektFitness/kubernetes-manifests/ | kubectl delete -f -  

    tanzu apps workload delete adopter-check -y -n $DEMO_APPS_NS 

}

#usage
usage() {

    echo
	echo "A mockup script to illustrate upcoming App Stack concepts. Please specify one of the following:"
	echo
    echo "${bold}backend${normal} - deploy the dekt4pets backend service and APIs"
    echo "          (use -u for update)"
    echo
    echo "${bold}frontend${normal} - deploy the dekt4pets frotend service and APIs"
    echo
    echo "${bold}dekt4pets${normal} - run end-to-end supplychain for dekt4pets deployment to production"
    echo
    echo "${bold}adopter-check${normal} - deploy the adopter-check TAP workload using the default supply-chain"
    echo
    echo "${bold}fitness${normal} - deploy the Fitenss app, services and APIs"
    echo 
  	exit   
 
}

#supplychain-dekt4pets
supply-chain-components() {

    echo
    echo "${bold}Supply chain(s)${normal}"
    echo
    tanzu apps cluster-supply-chain list
    echo

    echo "${bold}Workloads${normal}"
    echo
    echo "NAME                      GIT"
    echo "dekt4pets-backend         https://github.com/dektlong/dekt4pets-backend"     
    echo "dekt4pets-frontend        https://github.com/dektlong/dekt4pets-frontend" 
    echo "adopter-check             https://github.com/dektlong/adopter-check"
    echo
    echo "${bold}Workload Images${normal}"
    echo
    kp images list -n $DEMO_APPS_NS
    echo "${bold}API Delivery Flow${normal}"
    echo
    echo "NAME                          KIND                PATH"
    echo "dekt4pets-backend             app                 workloads/dekt4pets/backend/dekt4pets-backend.yaml"
    echo "dekt4pets-backend-routes      api-routes          workloads/dekt4pets/backend/routes/dekt4pets-backend-routes.yaml"
    echo "dekt4pets-backend-mapping     route-mapping       workloads/dekt4pets/backend/routes/dekt4pets-backend-mapping.yaml"
    echo
    echo "dekt4pets-frontend            app                 workloads/dekt4pets/frontend/dekt4pets-frontend.yaml"
    echo "dekt4pets-frontend-routes     api-routes          workloads/dekt4pets/frontend/routes/dekt4pets-frontend-routes.yaml"
    echo "dekt4pets-frontend-mapping    route-mapping       workloads/dekt4pets/frontend/routes/dekt4pets-frontend-mapping.yaml"
    echo
    echo "dekt4pets-gateway             gateway-config      workloads/dekt4pets/gateway/dekt4pets-gateway.yaml"
    echo "dekt4pets-ingress             ingress-rule        workloads/dekt4pets/gateway/dekt4pets-ingress.yaml"
    echo
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
fitness)
	create-fitness $2
    ;;
cleanup)
    delete-workloads
    ;;
*)
  	usage
  	;;
esac
