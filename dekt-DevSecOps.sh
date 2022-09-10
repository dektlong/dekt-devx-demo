#!/usr/bin/env bash

#################### load configs from values yaml  ################

    #clusters
    VIEW_CLUSTER=$(yq .view-cluster.name .config/demo-values.yaml)
    DEV_CLUSTER=$(yq .dev-cluster.name .config/demo-values.yaml)
    STAGE_CLUSTER=$(yq .stage-cluster.name .config/demo-values.yaml)
    PROD_CLUSTER=$(yq .prod-cluster.name .config/demo-values.yaml)
    BROWNFIELD_CLUSTER=$(yq .brownfield-cluster.name .config/demo-values.yaml)
    #workloads (must match the names in samples/workloads)
    PORTAL_WORKLOAD="mood-portal"
    SENSORS_WORKLOAD="mood-sensors"
    LEGACY_WORKLOAD="legacy-mood"
    DEV_WORKLOAD="mysensors"
    #deliverables
    PORTAL_DELIVERABLE=".gitops/portal_deliverable.yaml"
    LEGACY_DELIVERABLE=".gitops/legacy_deliverable.yaml"
    SENSORS_DELIVERABLE=".gitops/sensors_deliverable.yaml"
    #tap
    TAP_VERSION=$(yq .tap.version .config/demo-values.yaml)
    SYSTEM_REPO=$(yq .tap.systemRepo .config/demo-values.yaml)
    #apps-namespaces
    DEV_NAMESPACE=$(yq .apps-namespaces.dev .config/demo-values.yaml)
    TEAM_NAMESPACE=$(yq .apps-namespaces.team .config/demo-values.yaml)
    STAGEPROD_NAMESPACE=$(yq .apps-namespaces.stageProd .config/demo-values.yaml)
    PROD_AUDIT_FILE=.gitops/$(yq .tap.prodAuditFile .config/demo-values.yaml)
    
    

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

        addBrownfield=$(kubectl config get-contexts | grep $BROWNFIELD_CLUSTER)
        if [ -z "$addBrownfield" ]
        then
            echo ""
        else
            scripts/dektecho.sh info "Brownfield cluster (Tanzu Service Mesh)"
            kubectl config use-context $BROWNFIELD_CLUSTER 
            kubectl cluster-info | grep 'control plane' --color=never
        fi

        kubectl config use-context $DEV_CLUSTER 

    }
    
    #create-dev-workloads
    create-dev-workload() {

        kubectl config use-context $DEV_CLUSTER

        scripts/dektecho.sh cmd "tanzu apps workload create $DEV_WORKLOAD -f workload.yaml -n $DEV_NAMESPACE"
        tanzu apps workload create $DEV_WORKLOAD \
            --git-repo https://github.com/dektlong/mood-sensors \
            --git-branch dev \
            --type dekt-backend \
            --label apps.tanzu.vmware.com/has-tests="true" \
            --label app.kubernetes.io/part-of=$DEV_WORKLOAD \
            --yes \
            --namespace $DEV_NAMESPACE
    }

    #create-team-workloads
    create-team-workloads() {

        kubectl config use-context $DEV_CLUSTER
        
        scripts/dektecho.sh cmd "tanzu apps workload create $PORTAL_WORKLOAD -f samples/workloads/mood-portal-dev.yaml -y -n $TEAM_NAMESPACE"
        tanzu apps workload create $PORTAL_WORKLOAD -f samples/workloads/mood-portal-dev.yaml -y -n $TEAM_NAMESPACE

        scripts/dektecho.sh cmd "tanzu apps workload create $SENSORS_WORKLOAD -f samples/workloads/mood-sensors-dev.yaml -y -n $TEAM_NAMESPACE"
        tanzu apps workload create $SENSORS_WORKLOAD -f samples/workloads/mood-sensors-dev.yaml -y -n $TEAM_NAMESPACE

        scripts/dektecho.sh cmd "tanzu apps workload create $LEGACY_WORKLOAD -f samples/workloads/legacy-mood.yaml -y -n $TEAM_NAMESPACE"
        tanzu apps workload create $LEGACY_WORKLOAD -f samples/workloads/legacy-mood.yaml -y -n $TEAM_NAMESPACE
    }

    #create-stage-workloads
    create-stage-workloads() {

        kubectl config use-context $STAGE_CLUSTER
        
        scripts/dektecho.sh cmd "tanzu apps workload create $PORTAL_WORKLOAD -f samples/workloads/mood-portal-stage.yaml -y -n $STAGEPROD_NAMESPACE"
        tanzu apps workload create $PORTAL_WORKLOAD -f samples/workloads/mood-portal-stage.yaml -y -n $STAGEPROD_NAMESPACE

        scripts/dektecho.sh cmd "tanzu apps workload create $SENSORS_WORKLOAD -f samples/workloads/mood-sensors-stage.yaml -y -n $STAGEPROD_NAMESPACE"
        tanzu apps workload create $SENSORS_WORKLOAD -f samples/workloads/mood-sensors-stage.yaml -y -n $STAGEPROD_NAMESPACE

        scripts/dektecho.sh cmd "tanzu apps workload create $LEGACY_WORKLOAD -f samples/workloads/legacy-mood.yaml -y -n $STAGEPROD_NAMESPACE"
        tanzu apps workload create $LEGACY_WORKLOAD -f samples/workloads/legacy-mood.yaml -y -n $STAGEPROD_NAMESPACE
    }

    #prod-roleout
    prod-roleout () {

        mkdir .gitops
        #get Deliverables from stage cluster
        printf "$(date): " > $PROD_AUDIT_FILE 
        kubectl config use-context $STAGE_CLUSTER >> $PROD_AUDIT_FILE
        
        kubectl get deliverable $PORTAL_WORKLOAD -n $STAGEPROD_NAMESPACE -oyaml > $PORTAL_DELIVERABLE
        yq e 'del(.status)' $PORTAL_DELIVERABLE -i 
        yq e 'del(.metadata.ownerReferences)' $PORTAL_DELIVERABLE -i 
        echo "$(date): $PORTAL_DELIVERABLE generated." >> $PROD_AUDIT_FILE 

        kubectl get deliverable $LEGACY_WORKLOAD -n $STAGEPROD_NAMESPACE -oyaml > $LEGACY_DELIVERABLE
        yq e 'del(.status)' $LEGACY_DELIVERABLE -i 
        yq e 'del(.metadata.ownerReferences)' $LEGACY_DELIVERABLE -i 
        echo "$(date): $LEGACY_DELIVERABLE generated." >> $PROD_AUDIT_FILE 

        kubectl get deliverable $SENSORS_WORKLOAD -n $STAGEPROD_NAMESPACE -oyaml > $SENSORS_DELIVERABLE
        yq e 'del(.status)' $SENSORS_DELIVERABLE -i 
        yq e 'del(.metadata.ownerReferences)' $SENSORS_DELIVERABLE -i 
        echo "$(date): $SENSORS_DELIVERABLE generated." >> $PROD_AUDIT_FILE 
        
        scripts/dektecho.sh status "Review Deliverables in gitops repo"

        scripts/dektecho.sh prompt  "Are you sure you want deploy to production?" && [ $? -eq 0 ] || exit

        printf "$(date): " >> $PROD_AUDIT_FILE 
        kubectl config use-context $PROD_CLUSTER >> $PROD_AUDIT_FILE

        scripts/dektecho.sh cmd "Applying production Deliverables to $PROD_CLUSTER cluster..."

        echo "$(date): kubectl apply -f $PORTAL_DELIVERABLE -n $STAGEPROD_NAMESPACE" >> $PROD_AUDIT_FILE
        kubectl apply -f $PORTAL_DELIVERABLE -n $STAGEPROD_NAMESPACE >> $PROD_AUDIT_FILE

        echo "$(date): kubectl apply -f $LEGACY_DELIVERABLE -n $STAGEPROD_NAMESPACE" >> $PROD_AUDIT_FILE
        kubectl apply -f $LEGACY_DELIVERABLE -n $STAGEPROD_NAMESPACE >> $PROD_AUDIT_FILE

        echo "$(date): kubectl apply -f $SENSORS_DELIVERABLE -n $STAGEPROD_NAMESPACE" >> $PROD_AUDIT_FILE
        kubectl apply -f $SENSORS_DELIVERABLE -n $STAGEPROD_NAMESPACE >> $PROD_AUDIT_FILE

        printf "$(date): " >> $PROD_AUDIT_FILE 
        kubectl get deliverables -n $STAGEPROD_NAMESPACE >> $PROD_AUDIT_FILE

        scripts/dektecho.sh status "Congratulations. Your DevX-Mood application is in production"

    }

    #supplychains
    supplychains () {

        scripts/dektecho.sh cmd "tanzu apps cluster-supply-chain list"
        
        tanzu apps cluster-supply-chain list
    }

    #track-workloads
    track-workloads () {

        tapCluster=$1
        appsNamespace=$2
        showLogs=$3
        

        kubectl config use-context $tapCluster

        scripts/dektecho.sh cmd "tanzu apps workload get $PORTAL_WORKLOAD -n $appsNamespace"
        tanzu apps workload get $PORTAL_WORKLOAD -n $appsNamespace

        scripts/dektecho.sh cmd "tanzu apps workload get $LEGACY_WORKLOAD -n $appsNamespace"
        tanzu apps workload get $LEGACY_WORKLOAD -n $appsNamespace

        scripts/dektecho.sh cmd "tanzu apps workload get $SENSORS_WORKLOAD -n $appsNamespace"
        tanzu apps workload get $SENSORS_WORKLOAD -n $appsNamespace
        
        if [ "$showLogs" == "logs" ]; then
            scripts/dektecho.sh cmd "tanzu apps workload tail $SENSORS_WORKLOAD --since 100m --timestamp  -n $appsNamespace"
            
            tanzu apps workload tail $SENSORS_WORKLOAD --since 100m --timestamp  -n $appsNamespace
        fi
    }

    #brownfield
    brownfield () {

        scripts/dektecho.sh info "Brownfield CONSUMER services"

        scripts/dektecho.sh cmd "kubectl get svc -n brownfield-apis"
        kubectl config use-context $DEV_CLUSTER
        kubectl get svc -n brownfield-apis
        kubectl config use-context $STAGE_CLUSTER
        kubectl get svc -n brownfield-apis
        kubectl config use-context $PROD_CLUSTER
        kubectl get svc -n brownfield-apis

        scripts/dektecho.sh info "Brownfield PROVIDER services"

        scripts/dektecho.sh cmd "kubectl get svc -n brownfield-apis"
        kubectl config use-context $BROWNFIELD_CLUSTER 
        kubectl get svc -n brownfield-apis

        
    }

    #soft reset of all clusters configurations
    reset() {

        kubectl config use-context $STAGE_CLUSTER
        tanzu apps workload delete $PORTAL_WORKLOAD -n $STAGEPROD_NAMESPACE -y
        tanzu apps workload delete $LEGACY_WORKLOAD -n $STAGEPROD_NAMESPACE -y
        tanzu apps workload delete $SENSORS_WORKLOAD -n $STAGEPROD_NAMESPACE -y

        kubectl config use-context $PROD_CLUSTER
        kubectl delete deliverable $PORTAL_WORKLOAD -n $STAGEPROD_NAMESPACE
        kubectl delete deliverable $LEGACY_WORKLOAD -n $STAGEPROD_NAMESPACE
        kubectl delete deliverable $SENSORS_WORKLOAD -n $STAGEPROD_NAMESPACE

        kubectl config use-context $DEV_CLUSTER
        tanzu apps workload delete $DEV_WORKLOAD -n $DEV_NAMESPACE -y
        tanzu apps workload delete $PORTAL_WORKLOAD -n $TEAM_NAMESPACE  -y
        tanzu apps workload delete $LEGACY_WORKLOAD -n $TEAM_NAMESPACE  -y
        tanzu apps workload delete $SENSORS_WORKLOAD -n $TEAM_NAMESPACE -y

        toggle-dog sad
        rm -f $PORTAL_DELIVERABLE
        rm -f $LEGACY_DELIVERABLE
        rm -f $SENSORS_DELIVERABLE
        rm -r .gitops

        kubectl config use-context $VIEW_CLUSTER
        kubectl delete pod -l app=backstage -n tap-gui
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
            scripts/dektecho.sh err "!!!incorrect-usage. please specify happy / sad"
            ;;
        esac
        
        git push
        pushd
    }

    #cleanup-helper
    cleanup-helper() {
        toggle-dog sad
        rm -f $PORTAL_DELIVERABLE
        rm -f $LEGACY_DELIVERABLE
        rm -f $SENSORS_DELIVERABLE
    }

    #pre-deploy
    pre-deploy() {
        create-dev-workload
        create-team-workloads
        create-stage-workloads
        scripts/dektecho.sh prompt  "Should we start prod role out?" && [ $? -eq 0 ] || exit
        prod-roleout
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
        echo "  team"
        echo
        echo "  stage"
        echo
        echo "  prod"
        echo
        echo "  supplychains"
        echo
        echo "  track dev/stage [logs]"
        echo
        echo "  brownfield"
        echo
        echo "  behappy / besad"
        echo
        echo "  pre-deploy"
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
    create-dev-workload
    ;;
team)
    create-team-workloads
    ;;
stage)
    create-stage-workloads
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
    case $2 in
    team)
        track-workloads $DEV_CLUSTER $TEAM_NAMESPACE $3
        ;;
    stage)
        track-workloads $STAGE_CLUSTER $STAGEPROD_NAMESPACE $3
        ;;
    *)
        incorrect-usage
        ;;
    esac
    ;;
brownfield)
    brownfield
    ;;
behappy)
    toggle-dog happy
    ;;
besad)
    toggle-dog sad
    ;;
reset)
    reset
    ;;
pre-deploy)
    pre-deploy
    ;;
cleanup-helper)
    cleanup-helper
    ;;
*)
    incorrect-usage
    ;;
esac
