#!/usr/bin/env bash

PRIVATE_REPO_SERVER=$(yq .ootb_supply_chain_basic.registry.server .config/tap-profiles/tap-iterate.yaml)
PRIVATE_REPO_USER=$(yq .buildservice.kp_default_repository_username .config/tap-profiles//tap-iterate.yaml)
PRIVATE_REPO_PASSWORD=$(yq .buildservice.kp_default_repository_password .config/tap-profiles//tap-iterate.yaml)
SYSTEM_REPO=$(yq .tap.systemRepo .config/demo-values.yaml)
CARVEL_BUNDLE=$(yq .tap.carvel_bundle .config/demo-values.yaml)
TANZU_NETWORK_USER=$(yq .buildservice.tanzunet_username .config/tap-profiles/tap-iterate.yaml)
TANZU_NETWORK_PASSWORD=$(yq .buildservice.tanzunet_password .config/tap-profiles/tap-iterate.yaml)

#relocate-carvel-bundle
relocate-carvel-bundle() {

    scripts/dektecho.sh prompt "Make sure docker deamon is running before proceeding"
        
    docker login $PRIVATE_REPO_SERVER -u $PRIVATE_REPO_USER -p $PRIVATE_REPO_PASSWORD

    docker login registry.tanzu.vmware.com -u $TANZU_NETWORK_USER -p $TANZU_NETWORK_PASSWORD
        
    export IMGPKG_REGISTRY_HOSTNAME=$PRIVATE_REPO_SERVER
    export IMGPKG_REGISTRY_USERNAME=$PRIVATE_REPO_USER
    export IMGPKG_REGISTRY_PASSWORD=$PRIVATE_REPO_PASSWORD
    export TAP_VERSION=$TAP_VERSION

    imgpkg copy \
        --bundle registry.tanzu.vmware.com/tanzu-cluster-essentials/$CARVEL_BUNDLE \
        --to-tar carvel-bundle.tar \
        --include-non-distributable-layers

    imgpkg copy \
        --tar carvel-bundle.tar \
        --to-repo $IMGPKG_REGISTRY_HOSTNAME/$SYSTEM_REPO/cluster-essentials-bundle \
        --include-non-distributable-layers
    }

#add-carvel
add-carvel () {

    scripts/dektecho.sh status "Add Carvel tools to cluster $(kubectl config current-context)"

    pushd scripts/carvel
    
    INSTALL_BUNDLE=$PRIVATE_REPO_SERVER/$SYSTEM_REPO/$CARVEL_BUNDLE \
    INSTALL_REGISTRY_HOSTNAME=$PRIVATE_REPO_SERVER \
    INSTALL_REGISTRY_USERNAME=$PRIVATE_REPO_USER \
    INSTALL_REGISTRY_PASSWORD=$PRIVATE_REPO_PASSWORD \
    ./install.sh --yes

    pushd
}

#remove-carvel
remove-carvel () {

    pushd scripts/carvel

    ./uninstall.sh --yes

    pushd
}

#install-nginx
install-nginx ()
{
    scripts/dektecho.sh status "Install nginx ingress controller"

    # Add the ingress-nginx repository
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx

    kubectl create ns nginx-system

    # Use Helm to deploy an NGINX ingress controller
    helm install dekt ingress-nginx/ingress-nginx \
        --namespace nginx-system \
        --set controller.replicaCount=2 \
        --set controller.nodeSelector."beta\.kubernetes\.io/os"=linux \
        --set defaultBackend.nodeSelector."beta\.kubernetes\.io/os"=linux \
        --set controller.admissionWebhooks.patch.nodeSelector."beta\.kubernetes\.io/os"=linux
}
#################### main #######################

#incorrect-usage
incorrect-usage() {
    scripts/dektecho.sh err "Incorrect usage. Please specify: add-carvel-tools / remove-carvel-tools / add-nginx"
    exit
}

case $1 in
relocate-carvel-bundle)
    relocate-carvel-bundle
    ;;
add-carvel-tools )
  	add-carvel
    ;;
remove-carvel-tools)
    remove-carvel
    ;;
add-nginx)
    install-nginx
    ;;
*)
	incorrect-usage
	;;
esac