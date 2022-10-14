#!/usr/bin/env bash

PRIVATE_REPO_SERVER=$(yq .private_registry.host .config/demo-values.yaml)
PRIVATE_REPO_USER=$(yq .private_registry.username .config/demo-values.yaml)
PRIVATE_REPO_PASSWORD=$(yq .private_registry.password .config/demo-values.yaml)
SYSTEM_REPO=$(yq .repositories.system .config/demo-values.yaml)
CARVEL_BUNDLE=$(yq .tap.carvelBundle .config/demo-values.yaml)
TANZU_NETWORK_USER=$(yq .tanzu_network.username .config/demo-values.yaml)
TANZU_NETWORK_PASSWORD=$(yq .tanzu_network.password .config/demo-values.yaml)
export TAP_VERSION=$(yq .tap.version .config/demo-values.yaml)
GW_INSTALL_DIR=$(yq .apis.scgwInstallDirectory .config/demo-values.yaml)

#relocate-tap-images
relocate-tap-images() {

    docker login $PRIVATE_REPO_SERVER -u $PRIVATE_REPO_USER -p $PRIVATE_REPO_PASSWORD

    docker login registry.tanzu.vmware.com -u $TANZU_NETWORK_USER -p $TANZU_NETWORK_PASSWORD
        
    export IMGPKG_REGISTRY_HOSTNAME=$PRIVATE_REPO_SERVER
    export IMGPKG_REGISTRY_USERNAME=$PRIVATE_REPO_USER
    export IMGPKG_REGISTRY_PASSWORD=$PRIVATE_REPO_PASSWORD

    imgpkg copy \
        --bundle registry.tanzu.vmware.com/tanzu-application-platform/tap-packages:$TAP_VERSION \
        --to-tar tap-packages-$TAP_VERSION.tar \
        --include-non-distributable-layers

    imgpkg copy \
        --tar tap-packages-$TAP_VERSION.tar \
        --to-repo $IMGPKG_REGISTRY_HOSTNAME/$SYSTEM_REPO/tap-packages \
        --include-non-distributable-layers
            
}

#relocate-carvel-bundle
relocate-carvel-bundle() {

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

#relocate-gw-images
relocate-gw-images() {

    docker login $PRIVATE_REPO_SERVER -u $PRIVATE_REPO_USER -p $PRIVATE_REPO_PASSWORD
        
    $GW_INSTALL_DIR/scripts/relocate-images.sh $PRIVATE_REPO_SERVER/$SYSTEM_REPO
}

#relocate-tds-images
relocate-tds-images() {

        #docker login $PRIVATE_REPO_SERVER -u $PRIVATE_REPO_USER -p $PRIVATE_REPO_PASSWORD
        #docker login registry.tanzu.vmware.com -u $TANZU_NETWORK_USER -p $TANZU_NETWORK_PASSWORD
        
        #imgpkg copy -b registry.tanzu.vmware.com/packages-for-vmware-tanzu-data-services/tds-packages:1.0.0 \
        #    --to-repo $PRIVATE_REPO_SERVER/$SYSTEM_REPO/tds-packages

        tanzu package repository add tanzu-data-services-repository --url $PRIVATE_REPO_SERVER/$SYSTEM_REPO/tds-packages:1.0.0 -n tap-install
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

#update-demo-values
update-demo-values() {

    scripts/dektecho.sh status "Generating demo configuration files"

    #tap-profiles
    mkdir -p .config/tap-profiles
    ytt -f config-templates/tap-profiles/tap-view.yaml --data-values-file=.config/demo-values.yaml > .config/tap-profiles/tap-view.yaml
    ytt -f config-templates/tap-profiles/tap-iterate.yaml --data-values-file=.config/demo-values.yaml > .config/tap-profiles/tap-iterate.yaml
    ytt -f config-templates/tap-profiles/tap-build.yaml --data-values-file=.config/demo-values.yaml > .config/tap-profiles/tap-build.yaml
    ytt -f config-templates/tap-profiles/tap-run.yaml --data-values-file=.config/demo-values.yaml > .config/tap-profiles/tap-run.yaml

    #supply-chains
    mkdir -p .config/supply-chains
    ytt -f config-templates/supply-chains/dekt-src-config.yaml --data-values-file=.config/demo-values.yaml > .config/supply-chains/dekt-src-config.yaml
    ytt -f config-templates/supply-chains/dekt-src-scan-config.yaml --data-values-file=.config/demo-values.yaml > .config/supply-chains/dekt-src-scan-config.yaml
    ytt -f config-templates/supply-chains/dekt-src-test-api-config.yaml --data-values-file=.config/demo-values.yaml > .config/supply-chains/dekt-src-test-api-config.yaml
    ytt -f config-templates/supply-chains/dekt-src-test-scan-api-config.yaml --data-values-file=.config/demo-values.yaml > .config/supply-chains/dekt-src-test-scan-api-config.yaml
    ytt -f config-templates/supply-chains/gitops-creds.yaml --data-values-file=.config/demo-values.yaml > .config/supply-chains/gitops-creds.yaml
    cp config-templates/supply-chains/tekton-pipeline-dotnet.yaml .config/supply-chains/tekton-pipeline-dotnet.yaml
    cp config-templates/supply-chains/tekton-pipeline.yaml .config/supply-chains/tekton-pipeline.yaml

    #scanners
    mkdir -p .config/scanners
    ytt -f config-templates/scanners/carbonblack-creds.yaml --data-values-file=.config/demo-values.yaml > .config/scanners/carbonblack-creds.yaml
    ytt -f config-templates/scanners/carbonblack-values.yaml --data-values-file=.config/demo-values.yaml > .config/scanners/carbonblack-values.yaml
    ytt -f config-templates/scanners/snyk-creds.yaml --data-values-file=.config/demo-values.yaml > .config/scanners/snyk-creds.yaml
    ytt -f config-templates/scanners/snyk-values.yaml --data-values-file=.config/demo-values.yaml > .config/scanners/snyk-values.yaml
    cp config-templates/scanners/scan-policy.yaml .config/scanners/scan-policy.yaml

    #cluster-configs
    mkdir -p .config/cluster-configs
    ytt -f config-templates/cluster-configs/containerd-ng.yaml --data-values-file=.config/demo-values.yaml > .config/cluster-configs/containerd-ng.yaml
    cp config-templates/cluster-configs/reader-accounts.yaml .config/cluster-configs/reader-accounts.yaml
    cp config-templates/cluster-configs/single-user-access.yaml .config/cluster-configs/single-user-access.yaml
    cp config-templates/cluster-configs/store-auth-token.yaml .config/cluster-configs/store-auth-token.yaml
    cp config-templates/cluster-configs/store-ca-cert.yaml .config/cluster-configs/store-ca-cert.yaml
    cp config-templates/cluster-configs/store-secrets-export.yaml .config/cluster-configs/store-secrets-export.yaml

    #data-services (WIP)
    cp -R config-templates/data-services .config

    #workloads
    mkdir -p .config/workloads
    cp config-templates/workloads/mood-analyzer.yaml .config/workloads/mood-analyzer.yaml
    cp config-templates/workloads/mood-portal.yaml .config/workloads/mood-portal.yaml
    cp config-templates/workloads/mood-sensors-openapi.yaml .config/workloads/mood-sensors-openapi.yaml
    cp config-templates/workloads/mood-sensors.yaml .config/workloads/mood-sensors.yaml
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
relocate-tap-images)
    relocate-tap-images
    ;;
add-carvel-tools )
  	add-carvel
    ;;
remove-carvel-tools)
    remove-carvel
    ;;
update-demo-values)
    update-demo-values
    ;;
add-nginx)
    install-nginx
    ;;
*)
	incorrect-usage
	;;
esac