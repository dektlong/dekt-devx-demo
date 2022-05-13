#!/usr/bin/env bash

#################### load configs from values yaml  ################

    VIEW_CLUSTER=$(yq .view-cluster.name .config/demo-values.yaml)
    DEV_CLUSTER=$(yq .dev-cluster.name .config/demo-values.yaml)
    STAGE_CLUSTER=$(yq .stage-cluster.name .config/demo-values.yaml)
    PROD_CLUSTER=$(yq .prod-cluster.name .config/demo-values.yaml)
    BROWNFIELD_CLUSTER=$(yq .brownfield-cluster.name .config/demo-values.yaml)
    PORTAL_WORKLOAD_DEV="myportal"
    PORTAL_WORKLOAD_PROD="mood-portal"
    SENSORS_WORKLOAD_DEV="mysensors"
    SENSORS_WORKLOAD_PROD="mood-sensors"
    PORTAL_DELIVERABLE="portal-prod-golden-config.yaml"
    SENSORS_DELIVERABLE="sensors-prod-golden-config.yaml"
    TAP_VERSION=$(yq .tap.version .config/demo-values.yaml)
    SYSTEM_REPO=$(yq .tap.systemRepo .config/demo-values.yaml)
    APPS_NAMESPACE=$(yq .tap.appNamespace .config/demo-values.yaml)
    

#################### functions ################

    #info
    info () {

        scripts/dektecho.sh info "One API Install"
        
        echo "  tanzu package install tap"
        echo "      --package tap.tanzu.vmware.com"
        echo "      --version $TAP_VERSION"
        echo "      --values-file .config/tap_values.yaml"
        echo "      --namespace tap-install"
        
        scripts/dektecho.sh info "View cluster (TAP 'view' profile)"
        kubectl config use-context $VIEW_CLUSTER
        kubectl cluster-info | grep 'control plane' --color=never
        tanzu package installed list -n tap-install

        scripts/dektecho.sh info "Dev-Test cluster (TAP 'intereate' profile)"
        kubectl config use-context $DEV_CLUSTER 
        kubectl cluster-info | grep 'control plane' --color=never
        tanzu package installed list -n tap-install
        
        scripts/dektecho.sh info "Staging cluster (TAP 'build' profile)"
        kubectl config use-context $STAGE_CLUSTER 
        kubectl cluster-info | grep 'control plane' --color=never
        tanzu package installed list -n tap-install

        scripts/dektecho.sh info "Production cluster (TAP 'run' profile)"
        kubectl config use-context $PROD_CLUSTER 
        kubectl cluster-info | grep 'control plane' --color=never
        tanzu package installed list -n tap-install

        scripts/dektecho.sh info "Brownfield cluster (Tanzu Service Mesh)"
        kubectl config use-context $BROWNFIELD_CLUSTER 
        kubectl cluster-info | grep 'control plane' --color=never
        kubectl get pods -n brownfield-apis

    }

    #create-workloads
    create-workloads() {

        case $1 in
        dev)
            portalWorkload=$PORTAL_WORKLOAD_DEV
            sensorsWorkload=$SENSORS_WORKLOAD_DEV
            gitBranch="dev"
            kubectl config use-context $DEV_CLUSTER
            ;;
        stage)
            portalWorkload=$PORTAL_WORKLOAD_PROD
            sensorsWorkload=$SENSORS_WORKLOAD_PROD
            gitBranch="integrate"
            kubectl config use-context $STAGE_CLUSTER
            ;;
        esac

        scripts/dektecho.sh cmd "tanzu apps workload create $portalWorkload --git-repo https://github.com/dektlong/mood-portal --git-branch $gitBranch -y -n $APPS_NAMESPACE"
        
        tanzu apps workload create $portalWorkload \
            --git-repo https://github.com/dektlong/mood-portal \
            --git-branch $gitBranch \
            --type web \
            --label app.kubernetes.io/part-of=devx-mood \
            --yes \
            --namespace $APPS_NAMESPACE

        scripts/dektecho.sh cmd "tanzu apps workload create $sensorsWorkload --git-repo https://github.com/dektlong/mood-sensors --git-branch $gitBranch -y -n $APPS_NAMESPACE"

        tanzu apps workload create $sensorsWorkload \
            --git-repo https://github.com/dektlong/mood-sensors \
            --git-branch $gitBranch \
            --type web-backend \
            --label app.kubernetes.io/part-of=devx-mood \
            --label apps.tanzu.vmware.com/has-tests=true \
            --service-ref rabbitmq-claim=rabbitmq.com/v1beta1:RabbitmqCluster:reading \
            --yes \
            --namespace $APPS_NAMESPACE
        
    }

    #prod-roleout
    prod-roleout () {

        scripts/dektecho.sh info "Promoting scanned images to pre-prod cluster"
        kubectl config use-context $STAGE_CLUSTER

        scripts/dektecho.sh cmd "kubectl get deliverable $PORTAL_WORKLOAD_PROD -n $APPS_NAMESPACE -oyaml > $PORTAL_DELIVERABLE"

        kubectl get deliverable $PORTAL_WORKLOAD_PROD -n $APPS_NAMESPACE -oyaml > $PORTAL_DELIVERABLE
        
        echo "$PORTAL_DELIVERABLE generated."
        yq e 'del(.status)' $PORTAL_DELIVERABLE -i 
        yq e 'del(.metadata.ownerReferences)' $PORTAL_DELIVERABLE -i 

        scripts/dektecho.sh cmd "kubectl get deliverable $SENSORS_WORKLOAD_PROD -n $APPS_NAMESPACE -oyaml > $SENSORS_DELIVERABLE"

        kubectl get deliverable $SENSORS_WORKLOAD_PROD -n $APPS_NAMESPACE -oyaml > $SENSORS_DELIVERABLE
        echo "$SENSORS_DELIVERABLE generated."
        yq e 'del(.status)' $SENSORS_DELIVERABLE -i 
        yq e 'del(.metadata.ownerReferences)' $SENSORS_DELIVERABLE -i 
        
        scripts/dektecho.sh err "Hit any key to go production!"
        read

        kubectl config use-context $PROD_CLUSTER

        scripts/dektecho.sh cmd "kubectl apply -f $PORTAL_DELIVERABLE -n $APPS_NAMESPACE"
        kubectl apply -f $PORTAL_DELIVERABLE -n $APPS_NAMESPACE

        scripts/dektecho.sh cmd "kubectl apply -f $SENSORS_DELIVERABLE -n $APPS_NAMESPACE"
        kubectl apply -f $SENSORS_DELIVERABLE -n $APPS_NAMESPACE

        kubectl get deliverables -n $APPS_NAMESPACE

    }

    
    #supplychains
    supplychains () {

        scripts/dektecho.sh cmd "tanzu apps cluster-supply-chain list"
        
        tanzu apps cluster-supply-chain list
    }

    #track-workload
    track-workload () {

        workloadName=$1

        scripts/dektecho.sh cmd "tanzu apps workload get $workloadName-n $APPS_NAMESPACE"
        
        tanzu apps workload get $workloadName -n $APPS_NAMESPACE

        
        if [ "$1" == "logs" ]; then
            scripts/dektecho.sh cmd "tanzu apps workload tail $workloadName --since 100m --timestamp  -n $APPS_NAMESPACE"
            
            tanzu apps workload tail $workloadName --since 100m --timestamp  -n $APPS_NAMESPACE
        fi
    }

    
    #scanning-results
    scan-results () {

        scripts/dektecho.sh info "Scanning results"

        kubectl describe imagescan.scanning.apps.tanzu.vmware.com/$SENSORS_WORKLOAD-build -n $APPS_NAMESPACE

    }
        

    #soft reset of all clusters configurations
    reset() {

        kubectl config use-context $STAGE_CLUSTER
        tanzu apps workload delete $PORTAL_WORKLOAD_PROD -n $APPS_NAMESPACE -y
        tanzu apps workload delete $SENSORS_WORKLOAD_PROD -n $APPS_NAMESPACE -y

        kubectl config use-context $PROD_CLUSTER
        kubectl delete -f $PORTAL_DELIVERABLE
        kubectl delete -f $SENSORS_DELIVERABLE

        kubectl config use-context $DEV_CLUSTER
        tanzu apps workload delete $PORTAL_WORKLOAD_DEV -n $APPS_NAMESPACE -y
        tanzu apps workload delete $SENSORS_WORKLOAD_DEV -n $APPS_NAMESPACE -y
        kubectl delete pod -l app=backstage -n tap-gui
        kubectl -n app-live-view delete pods -l=name=application-live-view-connector
        tanzu package installed update tap --package-name tap.tanzu.vmware.com --version $TAP_VERSION -n tap-install -f .config/tap-values-full.yaml

        toggle-dog sad
        rm -f $PORTAL_DELIVERABLE
        rm -f $SENSORS_DELIVERABLE
    }

    #toggle the BYPASS_BACKEND flag in mood-portal
    toggle-dog () {

        pushd ../mood-portal

        case $1 in
        happy)
            sed -i '' 's/false/true/g' main.go
            git commit -a -m "always happy"      
            ;;
        sad)
            sed -i '' 's/true/false/g' main.go
            git commit -a -m "usually sad"
            ;;
        *)      
            echo "!!!incorrect-usage. please specify happy / sad"
            ;;
        esac
        
        git push
        pushd
    }

    #cleanup-helper
    cleanup-helper() {
        toggle-dog sad
        rm -f $PORTAL_DELIVERABLE
    }
    #incorrect usage
    incorrect-usage() {
        
        echo
        scripts/dektecho.sh err "Incorrect usage. Please specify one of the following: "
        echo
        echo "  info"
        echo
        echo "  dev"
        echo
        echo "  stage"
        echo
        echo "  prod"
        echo
        echo "  supplychains"
        echo "  track workload-name [ logs ]"
        echo "  scan-results"
        echo "  behappy"
        echo
        echo "  reset"
        exit
    }

#################### main ##########################

case $1 in
info)
    info
    ;;
dev)
    create-workloads "dev"
    ;;
stage)
    create-workloads "stage"
    ;;
prod)
    prod-roleout
    ;;
behappy)
    toggle-dog happy
    ;;   
supplychains)
    supplychains
    ;;
track)
    track-workload $2 $3
    ;;
scan-results)
    scan-results
    ;;
behappy)
    toggle-dog happy
    ;;
reset)
    reset
    ;;
cleanup-helper)
    cleanup-helper
    ;;
*)
    incorrect-usage
    ;;
esac
