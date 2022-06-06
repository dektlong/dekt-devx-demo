#!/usr/bin/env bash

export INSTALL_BUNDLE=registry.tanzu.vmware.com/tanzu-cluster-essentials/cluster-essentials-bundle@sha256:ab0a3539da241a6ea59c75c0743e9058511d7c56312ea3906178ec0f3491f51d
export INSTALL_REGISTRY_HOSTNAME=registry.tanzu.vmware.com
export INSTALL_REGISTRY_USERNAME=$(yq .buildservice.tanzunet_username .config/tap-values-full.yaml)
export INSTALL_REGISTRY_PASSWORD=$(yq .buildservice.tanzunet_password .config/tap-values-full.yaml)

#add-carvel
add-carvel () {

    scripts/dektecho.sh info "Add Carvel tools to cluster $(kubectl config current-context)"

    pushd scripts/carvel

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
    scripts/dektecho.sh info "Install nginx ingress controller"

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