#!/usr/bin/env bash

export IMGPKG_REGISTRY_HOSTNAME=$(yq .private_registry.host .config/demo-values.yaml)
export IMGPKG_REGISTRY_USERNAME=$(yq .private_registry.username .config/demo-values.yaml)
export IMGPKG_REGISTRY_PASSWORD=$(yq .private_registry.password .config/demo-values.yaml)
SYSTEM_REPO=$(yq .repositories.system .config/demo-values.yaml)
CARVEL_BUNDLE=$(yq .tap.carvelBundle .config/demo-values.yaml)
TANZU_NETWORK_USER=$(yq .tanzu_network.username .config/demo-values.yaml)
TANZU_NETWORK_PASSWORD=$(yq .tanzu_network.password .config/demo-values.yaml)
export TAP_VERSION=$(yq .tap.version .config/demo-values.yaml)
TDS_VERSION=$(yq .data_services.tdsVersion .config/demo-values.yaml)
GW_INSTALL_DIR=$(yq .apis.scgwInstallDirectory .config/demo-values.yaml)

#relocate-tap-images
relocate-tap-images() {

    scripts/dektecho.sh status "relocating TAP $TAP_VERSION images to $IMGPKG_REGISTRY_HOSTNAME/$SYSTEM_REPO/tap-packages"

    imgpkg copy \
        --bundle registry.tanzu.vmware.com/tanzu-application-platform/tap-packages:$TAP_VERSION \
        --to-tar tap-packages-$TAP_VERSION.tar \
        --include-non-distributable-layers

    imgpkg copy \
        --tar tap-packages-$TAP_VERSION.tar \
        --to-repo $IMGPKG_REGISTRY_HOSTNAME/$SYSTEM_REPO/tap-packages \
        --include-non-distributable-layers

    rm -f tap-packages-$TAP_VERSION.tar
            
}

#relocate-carvel-bundle
relocate-carvel-bundle() {

    scripts/dektecho.sh status "relocating Carvel Bundle to $IMGPKG_REGISTRY_HOSTNAME/$SYSTEM_REPO/cluster-essentials-bundle"

    imgpkg copy \
        --bundle registry.tanzu.vmware.com/tanzu-cluster-essentials/$CARVEL_BUNDLE \
        --to-tar carvel-bundle.tar \
        --include-non-distributable-layers

    imgpkg copy \
        --tar carvel-bundle.tar \
        --to-repo $IMGPKG_REGISTRY_HOSTNAME/$SYSTEM_REPO/cluster-essentials-bundle \
        --include-non-distributable-layers

    rm -f carvel-bundle.tar
}

#relocate-gw-images
relocate-scgw-images() {

    scripts/dektecho.sh status "relocating Spring Cloud Gateway images $IMGPKG_REGISTRY_HOSTNAME/$SYSTEM_REPO"

    $GW_INSTALL_DIR/scripts/relocate-images.sh $IMGPKG_REGISTRY_HOSTNAME/$SYSTEM_REPO
}

#relocate-tds-images
relocate-tds-images() {

    scripts/dektecho.sh status "relocating Tanzu Data Services $TDS_VERSION to $IMGPKG_REGISTRY_HOSTNAME/$SYSTEM_REPO/tds-packages"
        
    imgpkg copy \
        --bundle registry.tanzu.vmware.com/packages-for-vmware-tanzu-data-services/tds-packages:$TDS_VERSION \
        --to-repo $IMGPKG_REGISTRY_HOSTNAME/$SYSTEM_REPO/tds-packages
}
#add-carvel
add-carvel () {

    scripts/dektecho.sh status "Add Carvel tools to cluster $(kubectl config current-context)"

    pushd scripts/carvel
    
    INSTALL_BUNDLE=$IMGPKG_REGISTRY_HOSTNAME/$SYSTEM_REPO/$CARVEL_BUNDLE \
    INSTALL_REGISTRY_HOSTNAME=$IMGPKG_REGISTRY_HOSTNAME \
    INSTALL_REGISTRY_USERNAME=$IMGPKG_REGISTRY_USERNAME \
    INSTALL_REGISTRY_PASSWORD=$IMGPKG_REGISTRY_PASSWORD \
    ./install.sh --yes

    pushd
}

#remove-carvel
remove-carvel () {

    pushd scripts/carvel

    ./uninstall.sh --yes

    pushd
}

#generate-config-yamls
generate-config-yamls() {

    scripts/dektecho.sh status "Generating demo configuration yamls"

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
    scripts/dektecho.sh err "Incorrect usage."
    exit
}

case $1 in
relocate-tanzu-images)
    scripts/dektecho.sh prompt "Make sure docker deamon is running before proceeding"
    docker login $IMGPKG_REGISTRY_HOSTNAME -u $IMGPKG_REGISTRY_USERNAME -p $IMGPKG_REGISTRY_PASSWORD
    docker login registry.tanzu.vmware.com -u $TANZU_NETWORK_USER -p $TANZU_NETWORK_PASSWORD
    relocate-carvel-bundle
    relocate-tap-images
    relocate-tds-images
    relocate-scgw-images
    ;;
add-carvel-tools )
  	add-carvel
    ;;
remove-carvel-tools)
    remove-carvel
    ;;
generate-config-yamls)
    generate-config-yamls
    ;;
add-nginx)
    install-nginx
    ;;
*)
	incorrect-usage
	;;
esac