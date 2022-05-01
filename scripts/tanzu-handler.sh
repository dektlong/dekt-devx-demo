#!/usr/bin/env bash

export INSTALL_BUNDLE=registry.tanzu.vmware.com/tanzu-cluster-essentials/cluster-essentials-bundle@sha256:ab0a3539da241a6ea59c75c0743e9058511d7c56312ea3906178ec0f3491f51d
export INSTALL_REGISTRY_HOSTNAME=registry.tanzu.vmware.com
export INSTALL_REGISTRY_USERNAME=$(yq .buildservice.tanzunet_username .config/tap-values-full.yaml)
export INSTALL_REGISTRY_PASSWORD=$(yq .buildservice.tanzunet_password .config/tap-values-full.yaml)

#add-carvel
add-carvel () {

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
    echo
    echo "=========> Install nginx ingress controller ..."
    echo

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
    echo "Incorrect usage. Please specify: add-carvel-tools / remove-carvel-tools / add-nginx"
    exit
}

case $1 in
add-carvel-tools )
  	add-carvel
    ;;
remove-carvel-tools)
    remove-carvel
    ;;
*)
	incorrect-usage
	;;
esac