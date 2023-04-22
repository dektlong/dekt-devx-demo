#!/usr/bin/env bash

export IMGPKG_REGISTRY_HOSTNAME=$(yq .private_registry.host .config/demo-values.yaml)
export IMGPKG_REGISTRY_USERNAME=$(yq .private_registry.username .config/demo-values.yaml)
export IMGPKG_REGISTRY_PASSWORD=$(yq .private_registry.password .config/demo-values.yaml)
SYSTEM_REPO=$(yq .private_registry.repo .config/demo-values.yaml)
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
    ytt -f config-templates/tap-profiles/tap-stage.yaml --data-values-file=.config/demo-values.yaml > .config/tap-profiles/tap-stage.yaml
    ytt -f config-templates/tap-profiles/tap-run1.yaml --data-values-file=.config/demo-values.yaml > .config/tap-profiles/tap-run1.yaml
    ytt -f config-templates/tap-profiles/tap-run2.yaml --data-values-file=.config/demo-values.yaml > .config/tap-profiles/tap-run2.yaml

    #secrets
    mkdir -p .config/secrets
    cp -a config-templates/secrets/ .config/secrets
    ytt -f config-templates/secrets/carbonblack-creds.yaml --data-values-file=.config/demo-values.yaml > .config/secrets/carbonblack-creds.yaml
    ytt -f config-templates/secrets/snyk-creds.yaml --data-values-file=.config/demo-values.yaml > .config/secrets/snyk-creds.yaml
    cp config-templates/secrets/viewer-rbac.yaml .config/secrets/viewer-rbac.yaml

    #crossplane
    mkdir -p .config/crossplane
    ytt -f config-templates/crossplane/inventory-db-composition.yml --data-values-file=.config/demo-values.yaml > .config/crossplane/inventory-db-composition.yml
    cp config-templates/crossplane/aws-rds-psql-rbac.yaml .config/crossplane/aws-rds-psql-rbac.yaml
    cp config-templates/crossplane/rds-class.yaml .config/crossplane/rds-class.yaml
    cp config-templates/crossplane/inventory-db-xrd.yaml .config/crossplane/inventory-db-xrd.yaml

    mkdir -p .config/workloads
    cp -a config-templates/workloads/ .config/workloads/
}

#intall-tanzu-package
install-tanzu-package() {

    package_full_name=$1
    package_display_name=$2
    value_file_path=$3

    tanzu package available list -n tap-install $package_full_name -o yaml | sed 's/- /  /' > .config/package_info.yaml
    package_version=$(yq .version .config/package_info.yaml)
    rm .config/package_info.yaml
    
    scripts/dektecho.sh status "Installing tanzu package $package_display_name with discoverd version $package_version"

    if [ "$value_file" == "" ]
    then    
        tanzu package install $package_display_name \
            --package $package_full_name \
            --version  $package_version \
            --namespace tap-install
    else
        tanzu package install $package_display_name \
            --package $package_full_name \
            --version $package_version\
            --namespace tap-install \
            --values-file $value_file_path  
    fi

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
    echo "  install-tanzu-package package-full-name,package-display-name,(optional)value-file-path"
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
install-tanzu-package)
    install-tanzu-package $2 $3 $4
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