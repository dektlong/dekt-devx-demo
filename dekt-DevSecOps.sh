#!/usr/bin/env bash

#################### load configs from values yaml  ################

    #clusters
    VIEW_CLUSTER=$(yq .view-cluster.name .config/demo-values.yaml)
    DEV_CLUSTER=$(yq .dev-cluster.name .config/demo-values.yaml)
    STAGE_CLUSTER=$(yq .stage-cluster.name .config/demo-values.yaml)
    PROD_CLUSTER=$(yq .prod-cluster.name .config/demo-values.yaml)
    BROWNFIELD_CLUSTER=$(yq .brownfield-cluster.name .config/demo-values.yaml)
    #workloads
    PORTAL_WORKLOAD="mood-portal"
    SENSORS_WORKLOAD="mood-sensors"
    PORTAL_DELIVERABLE=".gitops/portal_deliverable.yaml"
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
    
    #create-workloads
    create-workloads() {

        case $1 in
        team)
            gitBranch="dev"
            tapCluster=$DEV_CLUSTER
            appsNamespace=$TEAM_NAMESPACE
            ;;
        stage)
            gitBranch="integrate"
            tapCluster=$STAGE_CLUSTER
            appsNamespace=$STAGEPROD_NAMESPACE
            ;;
        esac

        kubectl config use-context $tapCluster

        scripts/dektecho.sh cmd "tanzu apps workload create $PORTAL_WORKLOAD --git-repo https://github.com/dektlong/mood-portal --git-branch $gitBranch -y -n $appsNamespace"
        
        tanzu apps workload create $PORTAL_WORKLOAD \
            --git-repo https://github.com/dektlong/mood-portal \
            --git-branch $gitBranch \
            --type web \
            --label app.kubernetes.io/part-of=$PORTAL_WORKLOAD \
            --yes \
            --namespace $appsNamespace

        scripts/dektecho.sh cmd "tanzu apps workload create $SENSORS_WORKLOAD --git-repo https://github.com/dektlong/mood-sensors --git-branch $gitBranch -y -n $appsNamespace"

        tanzu apps workload create $SENSORS_WORKLOAD \
            --git-repo https://github.com/dektlong/mood-sensors \
            --git-branch $gitBranch \
            --type web-backend \
            --label app.kubernetes.io/part-of=$SENSORS_WORKLOAD \
            --label apps.tanzu.vmware.com/has-tests=true \
            --service-ref rabbitmq-claim=rabbitmq.com/v1beta1:RabbitmqCluster:reading \
            --yes \
            --namespace $appsNamespace
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

        kubectl get deliverable $SENSORS_WORKLOAD -n $STAGEPROD_NAMESPACE -oyaml > $SENSORS_DELIVERABLE
        yq e 'del(.status)' $SENSORS_DELIVERABLE -i 
        yq e 'del(.metadata.ownerReferences)' $SENSORS_DELIVERABLE -i 
              
        echo "$(date): $SENSORS_DELIVERABLE generated." >> $PROD_AUDIT_FILE 
        
        scripts/dektecho.sh info "Review Deliverables in gitops repo"
        scripts/dektecho.sh err "Hit any key to go production!" && read

        printf "$(date): " >> $PROD_AUDIT_FILE 
        kubectl config use-context $PROD_CLUSTER >> $PROD_AUDIT_FILE

        scripts/dektecho.sh cmd "Applying production Deliverables to $PROD_CLUSTER cluster..."

        echo "$(date): kubectl apply -f $PORTAL_DELIVERABLE -n $STAGEPROD_NAMESPACE" >> $PROD_AUDIT_FILE
        kubectl apply -f $PORTAL_DELIVERABLE -n $STAGEPROD_NAMESPACE >> $PROD_AUDIT_FILE

        echo "$(date): kubectl apply -f $SENSORS_DELIVERABLE -n $STAGEPROD_NAMESPACE" >> $PROD_AUDIT_FILE
        kubectl apply -f $SENSORS_DELIVERABLE -n $STAGEPROD_NAMESPACE >> $PROD_AUDIT_FILE

        printf "$(date): " >> $PROD_AUDIT_FILE 
        kubectl get deliverables -n $STAGEPROD_NAMESPACE >> $PROD_AUDIT_FILE

        scripts/dektecho.sh info "Congratulations. Your DevX-Mood application is in production"

    }

    
    #supplychains
    supplychains () {

        scripts/dektecho.sh cmd "tanzu apps cluster-supply-chain list"
        
        tanzu apps cluster-supply-chain list
    }

    #track-workload
    track-workload () {

        case $1 in
        team)
            tapCluster=$DEV_CLUSTER
            appsNamespace=$TEAM_NAMESPACE
            ;;
        stage)
            tapCluster=$STAGE_CLUSTER
            appsNamespace=$STAGEPROD_NAMESPACE
            ;;
        esac

        kubectl config use-context $tapCluster

        scripts/dektecho.sh cmd "tanzu apps workload get $PORTAL_WORKLOAD -n $appsNamespace"
        tanzu apps workload get $PORTAL_WORKLOAD -n $appsNamespace

        scripts/dektecho.sh cmd "tanzu apps workload get $SENSORS_WORKLOAD -n $appsNamespace"
        tanzu apps workload get $SENSORS_WORKLOAD -n $appsNamespace

        
        if [ "$2" == "logs" ]; then
            scripts/dektecho.sh cmd "tanzu apps workload tail $SENSORS_WORKLOAD --since 100m --timestamp  -n $appsNamespace"
            
            tanzu apps workload tail $SENSORS_WORKLOAD --since 100m --timestamp  -n $appsNamespace
        fi
    }

    #brownfield
    brownfield () {

        scripts/dektecho.sh info "Brownfield consumer services on $STAGE_CLUSTER cluster"

        kubectl config use-context $STAGE_CLUSTER
        kubectl get svc -n brownfield-apis

        scripts/dektecho.sh info "Brownfield provider service on $BROWNFIELD_CLUSTER cluster"
        kubectl config use-context $BROWNFIELD_CLUSTER 
        kubectl get svc -n brownfield-apis

        
    }

    
    #scanning-results
    scan-results () {

        scripts/dektecho.sh info "Scanning results"

        kubectl describe imagescan.scanning.apps.tanzu.vmware.com/$SENSORS_WORKLOAD -n $STAGEPROD_NAMESPACE

    }
        

    #soft reset of all clusters configurations
    reset() {

        kubectl config use-context $STAGE_CLUSTER
        tanzu apps workload delete $PORTAL_WORKLOAD -n $STAGEPROD_NAMESPACE -y
        tanzu apps workload delete $SENSORS_WORKLOAD -n $STAGEPROD_NAMESPACE -y
        tanzu package installed update tap --package-name tap.tanzu.vmware.com --version $TAP_VERSION -n tap-install -f .config/tap-build.yaml

        kubectl config use-context $PROD_CLUSTER
        kubectl delete deliverable $PORTAL_WORKLOAD -n $STAGEPROD_NAMESPACE
        kubectl delete deliverable $SENSORS_WORKLOAD -n $STAGEPROD_NAMESPACE
        tanzu package installed update tap --package-name tap.tanzu.vmware.com --version $TAP_VERSION -n tap-install -f .config/tap-run.yaml

        kubectl config use-context $DEV_CLUSTER
        tanzu apps workload delete mysensors -n $DEV_NAMESPACE -y
        tanzu apps workload delete $PORTAL_WORKLOAD -n $TEAM_NAMESPACE  -y
        tanzu apps workload delete $SENSORS_WORKLOAD -n $TEAM_NAMESPACE -y
        tanzu package installed update tap --package-name tap.tanzu.vmware.com --version $TAP_VERSION -n tap-install -f .config/tap-iterate.yaml
        
        kubectl config use-context $VIEW_CLUSTER
        kubectl delete pod -l app=backstage -n tap-gui
        kubectl -n app-live-view delete pods -l=name=application-live-view-connector
        tanzu package installed update tap --package-name tap.tanzu.vmware.com --version $TAP_VERSION -n tap-install -f .config/tap-view.yaml

        toggle-dog sad
        rm -f $PORTAL_DELIVERABLE
        rm -f $SENSORS_DELIVERABLE
        rm -r .gitops

        kubectl config use-context $DEV_CLUSTER
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
        rm -f $SENSORS_DELIVERABLE
    }

    #incorrect usage
    incorrect-usage() {
        
        echo
        scripts/dektecho.sh err "Incorrect usage. Please specify one of the following: "
        echo
        echo "  info"
        echo
        echo "  team"
        echo
        echo "  stage"
        echo
        echo "  prod"
        echo
        echo "  supplychains"
        echo "  track team/stage [ logs ]"
        echo "  scan-results"
        echo 
        echo "  brownfield"
        echo
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
team)
    create-workloads "team"
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
brownfield)
    brownfield
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
