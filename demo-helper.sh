#!/usr/bin/env bash

#################### configs ################

    source .config/config-values.env
    DELIVERABLE_FILE_NAME="portal-prod-golden-config.yaml"
    PORTAL_WORKLOAD_NAME="mood-portal"
    SENSORS_WORKLOAD_NAME="mood-sensors"
    DEV_CLUSTER=$DEV_CLUSTER_NAME-$K8S_PROVIDER
    STAGE_CLUSTER=$STAGE_CLUSTER_NAME-$K8S_PROVIDER
    PROD_CLUSTER=$PROD_CLUSTER_NAME-$K8S_PROVIDER

#################### functions ################

    #dev-cluster
    dev-cluster() {

        echo
        echo "One API to install TAP on any kubectl:"
        echo
        echo "  tanzu package install tap"
        echo "      --package tap.tanzu.vmware.com"
        echo "      --version $TAP_VERSION"
        echo "      --values-file .config/tap_values.yaml"
        echo "      --namespace tap-install"
        echo
        echo "==========================================================="
        echo "TAP packages installed on $DEV_CLUSTER cluster ..."
        echo "==========================================================="
        echo
        kubectl config use-context $DEV_CLUSTER
        tanzu package installed list -n tap-install
    }

    #stage-cluster
    stage-cluster() {

        echo
        echo "==========================================================="
        echo "TAP packages installed on $STAGE_CLUSTER cluster ..."
        echo "==========================================================="
        echo
        kubectl config use-context $STAGE_CLUSTER
        tanzu package installed list -n tap-install
    }

    #prod-cluster
    prod-cluster() {
        
        echo
        echo "==========================================================="
        echo "TAP packages installed on $PROD_CLUSTER cluster ..."
        echo "==========================================================="
        echo
        kubectl config use-context $PROD_CLUSTER
        tanzu package installed list -n tap-install
    }

    #deploy-workloads
    deploy-workloads() {

        kubectl config use-context $DEV_CLUSTER

        echo
        echo "tanzu apps workload create -f ../mood-portal/workload.yaml -y -n $DEMO_APPS_NS"
        echo        
        tanzu apps workload create -f ../mood-portal/workload.yaml -y -n $DEMO_APPS_NS
        
        echo
        echo "tanzu apps workload create -f ../mood-sensors/workload.yaml -y -n $DEMO_APPS_NS"
        echo
        tanzu apps workload create -f ../mood-sensors/workload.yaml -y -n $DEMO_APPS_NS

    }

    #promote-staging
    promote-staging() {

        kubectl config use-context $STAGE_CLUSTER
        tanzu apps workload create $PORTAL_WORKLOAD_NAME \
            --git-repo https://github.com/dektlong/mood-portal \
            --git-branch integrate \
            --type web \
            --label app.kubernetes.io/part-of=devx-mood \
            --yes \
            --namespace $DEMO_APPS_NS 
    }
    
    #promote-production
    promote-production () {

        kubectl config use-context $STAGE_CLUSTER

        echo
        echo "kubectl get deliverable $PORTAL_WORKLOAD_NAME -n $DEMO_APPS_NS -oyaml > $DELIVERABLE_FILE_NAME"
        echo 
        
        kubectl get deliverable $PORTAL_WORKLOAD_NAME -n $DEMO_APPS_NS -oyaml > $DELIVERABLE_FILE_NAME
        echo "$DELIVERABLE_FILE_NAME generated."
        yq e 'del(.status)' $DELIVERABLE_FILE_NAME -i 
        yq e 'del(.metadata.ownerReferences)' $DELIVERABLE_FILE_NAME -i 
        
        
        echo
        echo "Hit any key to go production! ..."
        read

        kubectl config use-context $PROD_CLUSTER
        echo
        echo "kubectl apply -f $DELIVERABLE_FILE_NAME -n $DEMO_APPS_NS"
        echo 
        
        kubectl apply -f $DELIVERABLE_FILE_NAME -n $DEMO_APPS_NS
        kubectl get deliverables -n $DEMO_APPS_NS

    }

    
    #supplychains
    supplychains () {

        echo
        echo "tanzu apps cluster-supply-chain list"
        echo
        tanzu apps cluster-supply-chain list
    }

    #track-sensors
    track-sensors () {

        echo
        echo "tanzu apps workload get $SENSORS_WORKLOAD_NAME -n $DEMO_APPS_NS"
        echo
        tanzu apps workload get $SENSORS_WORKLOAD_NAME -n $DEMO_APPS_NS

    }

    #track-portal
    track-portal () {

        echo
        echo "tanzu apps workload get $PORTAL_WORKLOAD_NAME -n $DEMO_APPS_NS"
        echo
        tanzu apps workload get $PORTAL_WORKLOAD_NAME -n $DEMO_APPS_NS

    }    

    #tail-sensors-logs
    tail-sensors-logs () {

          tanzu apps workload tail $SENSORS_WORKLOAD_NAME --since 100m --timestamp  -n $DEMO_APPS_NS
    }

    #tail-portal-logs
    tail-portal-logs () {

        tanzu apps workload tail $PORTAL_WORKLOAD_NAME --since 100m --timestamp  -n $DEMO_APPS_NS

    }

    #scanning-results
    scanning-results () {

        kubectl describe imagescan.scanning.apps.tanzu.vmware.com/$SENSORS_WORKLOAD_NAME -n $DEMO_APPS_NS

    }
        

    #soft reset of all clusters configurations
    reset() {

        kubectl config use-context $STAGE_CLUSTER
        tanzu apps workload delete $PORTAL_WORKLOAD_NAME -n $DEMO_APPS_NS -y

        kubectl config use-context $PROD_CLUSTER
        kubectl delete -f $DELIVERABLE_FILE_NAME

        kubectl config use-context $DEV_CLUSTER
        tanzu apps workload delete $PORTAL_WORKLOAD_NAME -n $DEMO_APPS_NS -y
        tanzu apps workload delete $SENSORS_WORKLOAD_NAME -n $DEMO_APPS_NS -y
        kubectl delete pod -l app=backstage -n tap-gui
        kubectl -n app-live-view delete pods -l=name=application-live-view-connector
        tanzu package installed update tap --package-name tap.tanzu.vmware.com --version $TAP_VERSION -n tap-install -f .config/tap-values-full.yaml

        toggle-dog sad
        rm -f $DELIVERABLE_FILE_NAME

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
        rm -f $DELIVERABLE_FILE_NAME
    }
    #incorrect usage
    incorrect-usage() {
        
        echo
        echo "Incorrect usage. Please specify one of the following: "
        echo
        echo
        echo "  dev-cluster"
        echo "  deploy-workloads"
        echo "  behappy"
        echo
        echo "  stage-cluster"
        echo "  promote-staging"
        echo
        echo "  prod-cluster"
        echo "  promote-production"
        echo
        echo "  supplychains"
        echo "  track-sensors"
        echo "  track-portal"
        echo "  tail-sensors-logs"
        echo "  tail-portal-logs"
        echo "  scanning-results"
        echo
        echo "  reset"
        exit
    }

#################### main ##########################

case $1 in
dev-cluster)
    dev-cluster
    ;;
stage-cluster)
    stage-cluster
    ;;
prod-cluster)
    prod-cluster
    ;;
deploy-workloads)
    deploy-workloads
    ;;
promote-staging)
    promote-staging
    ;;
promote-production)
    promote-production
    ;;
supplychains)
    supplychains
    ;;
track-sensors)
    track-sensors
    ;;
track-portal)
    track-portal
    ;;
tail-sensors-logs)
    tail-sensors-logs
    ;;
tail-portal-logs)
    tail-portal-logs
    ;;
scanning-results)
    scanning-results
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
