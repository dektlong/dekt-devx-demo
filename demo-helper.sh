#!/usr/bin/env bash

#################### load configs from values yaml  ################

    VIEW_CLUSTER=$(yq .view-cluster.name .config/demo-values.yaml)
    DEV_CLUSTER=$(yq .dev-cluster.name .config/demo-values.yaml)
    STAGE_CLUSTER=$(yq .stage-cluster.name .config/demo-values.yaml)
    PROD_CLUSTER=$(yq .prod-cluster.name .config/demo-values.yaml)
    BROWNFIELD_CLUSTER=$(yq .brownfield-cluster.name .config/demo-values.yaml)
    PORTAL_WORKLOAD="mood-portal"
    SENSORS_WORKLOAD="mood-sensors"
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
        
        scripts/dektecho.sh info "Cluster topology"
        
        kubectl config use-context $VIEW_CLUSTER
        kubectl cluster-info | grep 'control plane' --color=never

        kubectl config use-context $DEV_CLUSTER 
        kubectl cluster-info | grep 'control plane' --color=never
        
        kubectl config use-context $STAGE_CLUSTER 
        kubectl cluster-info | grep 'control plane' --color=never

        kubectl config use-context $PROD_CLUSTER 
        kubectl cluster-info | grep 'control plane' --color=never

        kubectl config use-context $BROWNFIELD_CLUSTER 
        kubectl cluster-info | grep 'control plane' --color=never

    }

    #view-cluster
    view-cluster() {

        scripts/dektecho.sh info "TAP 'view' profile, installed on $VIEW_CLUSTER cluster"
        
        kubectl config use-context $VIEW_CLUSTER
        tanzu package installed list -n tap-install
    }

    #dev-cluster
    dev-cluster() {

        scripts/dektecho.sh info "TAP 'iterate' profile, installed on $DEV_CLUSTER cluster"
        
        kubectl config use-context $DEV_CLUSTER
        tanzu package installed list -n tap-install
    }

    #stage-cluster
    stage-cluster() {

        scripts/dektecho.sh info "TAP 'build' profile, installed on $STAGE_CLUSTER cluster"
        
        kubectl config use-context $STAGE_CLUSTER
        tanzu package installed list -n tap-install
    }

    #prod-cluster
    prod-cluster() {
        
        scripts/dektecho.sh info "TAP 'run' profile, installed on $PROD_CLUSTER cluster"
        
        kubectl config use-context $PROD_CLUSTER
        tanzu package installed list -n tap-install
    }

    #deploy-workloads
    deploy-workloads() {

        kubectl config use-context $DEV_CLUSTER

        scripts/dektecho.sh cmd "tanzu apps workload create -f workloads/mood-portal.yaml -y -n $APPS_NAMESPACE"
        
        tanzu apps workload create -f workloads/mood-portal.yaml -y -n $APPS_NAMESPACE

        scripts/dektecho.sh cmd "tanzu apps workload create -f workloads/mood-sensors.yaml -y -n $APPS_NAMESPACE"
        
        tanzu apps workload create -f workloads/mood-sensors.yaml -y -n $APPS_NAMESPACE
    }

    #promote-staging
    promote-staging() {

        scripts/dektecho.sh info "Promoting workloads (integration branch) to staging cluster"
        kubectl config use-context $STAGE_CLUSTER
        
        tanzu apps workload create -f workloads/mood-portal-integrate.yaml -y -n $APPS_NAMESPACE

        tanzu apps workload create -f workloads/mood-sensors-integrate.yaml -y -n $APPS_NAMESPACE
    }
  
    #promote-production
    promote-production () {

        scripts/dektecho.sh info "Promoting scanned images to pre-prod cluster"
        kubectl config use-context $STAGE_CLUSTER

        scripts/dektecho.sh cmd "kubectl get deliverable $PORTAL_WORKLOAD -n $APPS_NAMESPACE -oyaml > $PORTAL_DELIVERABLE"

        kubectl get deliverable $PORTAL_WORKLOAD -n $APPS_NAMESPACE -oyaml > $PORTAL_DELIVERABLE
        
        echo "$PORTAL_DELIVERABLE generated."
        yq e 'del(.status)' $PORTAL_DELIVERABLE -i 
        yq e 'del(.metadata.ownerReferences)' $PORTAL_DELIVERABLE -i 

        scripts/dektecho.sh cmd "kubectl get deliverable $SENSORS_WORKLOAD -n $APPS_NAMESPACE -oyaml > $SENSORS_DELIVERABLE"

        kubectl get deliverable $SENSORS_WORKLOAD -n $APPS_NAMESPACE -oyaml > $SENSORS_DELIVERABLE
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

    #track-sensors
    track-sensors () {

        scripts/dektecho.sh cmd "tanzu apps workload get $SENSORS_WORKLOAD -n $APPS_NAMESPACE"
        
        tanzu apps workload get $SENSORS_WORKLOAD -n $APPS_NAMESPACE

        
        if [ "$1" == "logs" ]; then
            scripts/dektecho.sh cmd "tanzu apps workload tail $SENSORS_WORKLOAD --since 100m --timestamp  -n $APPS_NAMESPACE"
            
            tanzu apps workload tail $SENSORS_WORKLOAD --since 100m --timestamp  -n $APPS_NAMESPACE
        fi
    }

    #track-portal
    track-portal () {

        scripts/dektecho.sh cmd "tanzu apps workload get $PORTAL_WORKLOAD -n $APPS_NAMESPACE"
        
        tanzu apps workload get $PORTAL_WORKLOAD -n $APPS_NAMESPACE

        if [ "$1" == "logs" ]; then
            scripts/dektecho.sh cmd "tanzu apps workload tail $PORTAL_WORKLOAD --since 100m --timestamp  -n $APPS_NAMESPACE"
            
            tanzu apps workload tail $PORTAL_WORKLOAD --since 100m --timestamp  -n $APPS_NAMESPACE
        fi

    }    

    
    #scanning-results
    scan-results () {

        scripts/dektecho.sh info "Scanning results"

        kubectl describe imagescan.scanning.apps.tanzu.vmware.com/$SENSORS_WORKLOAD -n $APPS_NAMESPACE

    }
        

    #soft reset of all clusters configurations
    reset() {

        kubectl config use-context $STAGE_CLUSTER
        tanzu apps workload delete $PORTAL_WORKLOAD -n $APPS_NAMESPACE -y
        tanzu apps workload delete $SENSORS_WORKLOAD -n $APPS_NAMESPACE -y

        kubectl config use-context $PROD_CLUSTER
        kubectl delete -f $PORTAL_DELIVERABLE
        kubectl delete -f $SENSORS_DELIVERABLE

        kubectl config use-context $DEV_CLUSTER
        tanzu apps workload delete $PORTAL_WORKLOAD -n $APPS_NAMESPACE -y
        tanzu apps workload delete $SENSORS_WORKLOAD -n $APPS_NAMESPACE -y
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
        echo "  innerloop [tap / deploy / behappy]"
        echo
        echo "  outerloop [tap / staging / production]"
        echo
        echo "  supplychains"
        echo "  track-sensors [logs]"
        echo "  track-portal [logs]"
        echo "  scan-results"
        echo
        echo "  reset"
        exit
    }

#################### main ##########################

case $1 in
info)
    info
    ;;
innerloop)
    case $2 in
    tap)
        view-cluster
        dev-cluster
        ;;
    deploy)
        deploy-workloads
        ;;
    behappy)
        toggle-dog happy
        ;;
    *)
        incorrect-usage
        ;;
    esac
    ;;
outerloop)
    case $2 in
    tap)
        stage-cluster
        prod-cluster
        ;;
    staging)
        promote-staging
        ;;
    production)
        promote-production
        ;;
    *)
        incorrect-usage
        ;;
    esac
    ;;
track-sensors)
    track-sensors $2
    ;;
track-portal)
    track-portal $2
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
