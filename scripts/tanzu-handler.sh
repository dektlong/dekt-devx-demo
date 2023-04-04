#!/usr/bin/env bash

export IMGPKG_REGISTRY_HOSTNAME=$(yq .private_registry.host .config/demo-values.yaml)
export IMGPKG_REGISTRY_USERNAME=$(yq .private_registry.username .config/demo-values.yaml)
export IMGPKG_REGISTRY_PASSWORD=$(yq .private_registry.password .config/demo-values.yaml)
SYSTEM_REPO=$(yq .repositories.system .config/demo-values.yaml)
CARVEL_BUNDLE=$(yq .tap.carvelBundle .config/demo-values.yaml)
TANZU_NETWORK_REGISTRY="registry.tanzu.vmware.com"
TANZU_NETWORK_USER=$(yq .tanzu_network.username .config/demo-values.yaml)
TANZU_NETWORK_PASSWORD=$(yq .tanzu_network.password .config/demo-values.yaml)
TAP_VERSION=$(yq .tap.tapVersion .config/demo-values.yaml)
TDS_VERSION=$(yq .data_services.tdsVersion .config/demo-values.yaml)
GW_INSTALL_DIR=$(yq .brownfield_apis.scgwInstallDirectory .config/demo-values.yaml)
TMC_API_TOKEN_VALUE=$(yq .tmc.apiToken .config/demo-values.yaml)
TMC_CLUSTER_GROUP=$(yq .tmc.clusterGroup .config/demo-values.yaml)

#relocate-tap-images
relocate-tap-images() {

    scripts/dektecho.sh status "relocating TAP $TAP_VERSION images to $IMGPKG_REGISTRY_HOSTNAME/$SYSTEM_REPO/tap-packages"

    imgpkg copy \
        --bundle $TANZU_NETWORK_REGISTRY/tanzu-application-platform/tap-packages:$TAP_VERSION \
        --to-tar .config/tap-packages-$TAP_VERSION.tar \
        --include-non-distributable-layers

    imgpkg copy \
        --tar .config/tap-packages-$TAP_VERSION.tar \
        --to-repo $IMGPKG_REGISTRY_HOSTNAME/$SYSTEM_REPO/tap-packages \
        --include-non-distributable-layers

    rm -f .config/tap-packages-$TAP_VERSION.tar
            
}

#relocate-carvel-bundle
relocate-carvel-bundle() {

    scripts/dektecho.sh status "relocating cluster-essentials to $IMGPKG_REGISTRY_HOSTNAME/$SYSTEM_REPO/cluster-essentials-bundle"

    imgpkg copy \
        --bundle $TANZU_NETWORK_REGISTRY/tanzu-cluster-essentials/cluster-essentials-bundle@$CARVEL_BUNDLE \
        --to-tar .config/carvel-bundle.tar \
        --include-non-distributable-layers

    imgpkg copy \
        --tar .config/carvel-bundle.tar \
        --to-repo $IMGPKG_REGISTRY_HOSTNAME/$SYSTEM_REPO/cluster-essentials-bundle \
        --include-non-distributable-layers

    rm -f .config/carvel-bundle.tar
}

#relocate-tbs-images
relocate-tbs-images() {

    #check if there is an tap=repo available on cluster
    
    tbs_package=$(tanzu package available list -n tap-install | grep 'buildservice' > /dev/null)
    tbs_version=$(echo ${tbs_package: -20} | sed 's/[[:space:]]//g')
    
    scripts/dektecho.sh status "relocating TBS $tbs_version images to $IMGPKG_REGISTRY_HOSTNAME/$SYSTEM_REPO/tbs-full-deps"

    imgpkg copy \
        --bundle $TANZU_NETWORK_REGISTRY/tanzu-application-platform/full-tbs-deps-package-repo:$tbs_version \
        --to-tar=.config/tbs-full-deps.tar
    
    imgpkg copy \
        --tar .config/tbs-full-deps.tar \
        --to-repo=$IMGPKG_REGISTRY_HOSTNAME/$SYSTEM_REPO/tbs-full-deps

    rm -f .config/tbs-full-deps.tar

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
        --bundle $TANZU_NETWORK_REGISTRY/packages-for-vmware-tanzu-data-services/tds-packages:$TDS_VERSION \
        --to-repo $IMGPKG_REGISTRY_HOSTNAME/$SYSTEM_REPO/tds-packages
}
#add-carvel
add-carvel () {

    scripts/dektecho.sh status "Add Carvel tools to cluster $(kubectl config current-context)"

    pushd scripts/carvel
    
    INSTALL_BUNDLE=$IMGPKG_REGISTRY_HOSTNAME/$SYSTEM_REPO/cluster-essentials-bundle@$CARVEL_BUNDLE \
    INSTALL_REGISTRY_HOSTNAME=$IMGPKG_REGISTRY_HOSTNAME \
    INSTALL_REGISTRY_USERNAME=$IMGPKG_REGISTRY_USERNAME \
    INSTALL_REGISTRY_PASSWORD=$IMGPKG_REGISTRY_PASSWORD \
    ./install.sh --yes

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
    ytt -f config-templates/supply-chains/dekt-img-config.yaml --data-values-file=.config/demo-values.yaml > .config/supply-chains/dekt-img-config.yaml
    ytt -f config-templates/supply-chains/dekt-img-scan-config.yaml --data-values-file=.config/demo-values.yaml > .config/supply-chains/dekt-img-scan-config.yaml
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
    cp -a config-templates/cluster-configs/ .config/cluster-configs/
    
    #data-services (WIP)
    cp -R config-templates/data-services .config
    ytt -f config-templates/data-services/rds-postgres/crossplane-xrd-composition.yaml --data-values-file=.config/demo-values.yaml > .config/data-services/rds-postgres/crossplane-xrd-composition.yaml

    #workloads
    mkdir -p .config/workloads
    cp -a config-templates/workloads/ .config/workloads/
    ytt -f config-templates/workloads/mood-predictor.yaml --data-values-file=.config/demo-values.yaml > .config/workloads/mood-predictor.yaml
    
}

#attach TMC cluster
attach-tmc-cluster() {
    
    cluster_name=$1

    scripts/dektecho.sh status "Attaching $cluster_name cluster to TMC"

    export TMC_API_TOKEN=$TMC_API_TOKEN_VALUE
    tmc login -n devxdemo-tmc -c

    kubectl config use-context $cluster_name
    tmc cluster attach -n $cluster_name -g $TMC_CLUSTER_GROUP
    kubectl apply -f k8s-attach-manifest.yaml
    rm -f k8s-attach-manifest.yaml
}

#delete-tmc-cluster
remove-tmc-cluster() {

    cluster_name=$1

    scripts/dektecho.sh status "Removing $cluster_name cluster from TMC"

    export TMC_API_TOKEN=$TMC_API_TOKEN_VALUE
    tmc login -n devxdemo-tmc -c

    tmc cluster delete $cluster_name -f -m attached -p attached
    
}

#################### main #######################

#incorrect-usage
incorrect-usage() {
    scripts/dektecho.sh err "Incorrect usage. Use one of the following: "
    echo "  relocate-tanzu-images tap|tbs|tds|scgw"
    echo 
    echo "  add-carvel-tools"
    echo 
    echo "  add-aria-monitoring"
    echo 
    echo "  tmc-cluster attach|remove"
    echo 
    echo "  generate-configs"
    echo
}

case $1 in
relocate-tanzu-images)
    docker login $IMGPKG_REGISTRY_HOSTNAME -u $IMGPKG_REGISTRY_USERNAME -p $IMGPKG_REGISTRY_PASSWORD
    docker login registry.tanzu.vmware.com -u $TANZU_NETWORK_USER -p $TANZU_NETWORK_PASSWORD
    case $2 in
    tap)
        relocate-carvel-bundle
        relocate-tap-images
        ;;
    tbs)
        scripts/dektecho.sh prompt  "Verfiy tanzu registry is installed on this k8s cluster. Continue?" && [ $? -eq 0 ] || exit
        relocate-tbs-images 
        ;;
    tds)    
        relocate-tds-images
        ;;
    scgw)
        relocate-scgw-images
        ;;
    *)
	    incorrect-usage
	    ;;
    esac
    ;;
add-carvel-tools)
  	add-carvel
    ;;
tmc-cluster)
    case $2 in
    attach)
        attach-tmc-cluster $3
        ;;
    remove)
        remove-tmc-cluster $3
        ;;
    *)
	    incorrect-usage
	    ;;
    esac
    ;;
generate-configs)
    generate-config-yamls
    ;;
*)
	incorrect-usage
	;;
esac