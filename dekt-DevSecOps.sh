#!/usr/bin/env bash

#################### load configs from values yaml  ################

    #clusters
    VIEW_CLUSTER=$(yq .view-cluster.name .config/demo-values.yaml)
    DEV_CLUSTER=$(yq .dev-cluster.name .config/demo-values.yaml)
    STAGE_CLUSTER=$(yq .stage-cluster.name .config/demo-values.yaml)
    PROD_CLUSTER=$(yq .prod-cluster.name .config/demo-values.yaml)
    BROWNFIELD_CLUSTER=$(yq .brownfield-cluster.name .config/demo-values.yaml)
    #workloads (must match the info in .config/workloads)
    PORTAL_WORKLOAD="mood-portal"
    SENSORS_WORKLOAD="mood-sensors"
    ANALYZER_WORKLOAD="mood-analyzer"
    DEV_WORKLOAD="mysensors"
    DEV_BRANCH="dev"
    STAGE_BRANCH="release-v1.0"
    GITOPS_DEV_REPO="gitops-dev"
    GITOPS_STAGE_REPO="gitops-stage"
    #tap
    TAP_VERSION=$(yq .tap.version .config/demo-values.yaml)
    SYSTEM_REPO=$(yq .tap.systemRepo .config/demo-values.yaml)
    #apps-namespaces
    DEV_NAMESPACE=$(yq .apps-namespaces.dev .config/demo-values.yaml)
    TEAM_NAMESPACE=$(yq .apps-namespaces.team .config/demo-values.yaml)
    STAGEPROD_NAMESPACE=$(yq .apps-namespaces.stageProd .config/demo-values.yaml)
   
    

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

        clusterName=$1
        appNamespace=$2
        export branch=$3
        
        kubectl config use-context $clusterName
        
        #set branch in workloads
        yq '.spec.source.git.ref.branch = env(branch)' .config/workloads/mood-portal.yaml -i
        yq '.spec.source.git.ref.branch = env(branch)' .config/workloads/mood-sensors.yaml -i
        
        scripts/dektecho.sh cmd "tanzu apps workload create $PORTAL_WORKLOAD -f .config/workloads/mood-portal.yaml -y -n $appNamespace"
        tanzu apps workload create $PORTAL_WORKLOAD -f .config/workloads/mood-portal.yaml -y -n $appNamespace

        scripts/dektecho.sh cmd "tanzu apps workload create $SENSORS_WORKLOAD -f .config/workloads/mood-sensors.yaml -y -n $appNamespace"
        tanzu apps workload create $SENSORS_WORKLOAD -f .config/workloads/mood-sensors.yaml -y -n $appNamespace

        scripts/dektecho.sh cmd "tanzu apps workload create $ANALYZER_WORKLOAD -f .config/workloads/mood-analyzer.yaml -y -n $appNamespace"
        tanzu apps workload create $ANALYZER_WORKLOAD -f .config/workloads/mood-analyzer.yaml -y -n $appNamespace
    }

    #single-dev-workload
    single-dev-workload() {

        kubectl config use-context $DEV_CLUSTER

        scripts/dektecho.sh cmd "tanzu apps workload create $DEV_WORKLOAD -f workload.yaml -n $DEV_NAMESPACE"
        tanzu apps workload create $DEV_WORKLOAD \
            --git-repo https://github.com/dektlong/mood-sensors \
            --git-branch dev \
            --type dekt-api \
            --label apps.tanzu.vmware.com/has-tests="true" \
            --label app.kubernetes.io/part-of=$DEV_WORKLOAD \
            --yes \
            --namespace $DEV_NAMESPACE

        #default sample app
        tanzu apps workload create tanzu-java-web-app \
            --git-repo https://github.com/sample-accelerators/tanzu-java-web-app \
            --git-branch main \
            --type web \
            --label app.kubernetes.io/part-of=tanzu-java-web-app \
            --yes \
            --namespace $DEV_NAMESPACE
    }
    
    #prod-roleout
    prod-roleout () {

        scripts/dektecho.sh info "Review Deliverables and ServiceBindings in gitops repo"

        scripts/dektecho.sh prompt  "Are you sure you want deploy to production?" && [ $? -eq 0 ] || exit
        
        scripts/dektecho.sh status "Pulling stage Deliverables and ServiceBindings from $GITOPS_STAGE_REPO repo"

        pushd ../$GITOPS_STAGE_REPO
        git pull 
        pushd

        scripts/dektecho.sh status "Applying Deliverables and ServiceBindings to $PROD_CLUSTER cluster..."

        kubectl config use-context $PROD_CLUSTER
        kubectl apply -f ../$GITOPS_STAGE_REPO/config/dekt-apps/$ANALYZER_WORKLOAD -n $STAGEPROD_NAMESPACE
        kubectl apply -f ../$GITOPS_STAGE_REPO/config/dekt-apps/$PORTAL_WORKLOAD -n $STAGEPROD_NAMESPACE
        kubectl apply -f ../$GITOPS_STAGE_REPO/config/dekt-apps/$SENSORS_WORKLOAD -n $STAGEPROD_NAMESPACE

        scripts/dektecho.sh status "Your DevX-Mood application is being deployed to production"

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

        scripts/dektecho.sh cmd "tanzu apps workload get $ANALYZER_WORKLOAD -n $appsNamespace"
        tanzu apps workload get $ANALYZER_WORKLOAD -n $appsNamespace

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
        tanzu apps workload delete $ANALYZER_WORKLOAD -n $STAGEPROD_NAMESPACE -y
        tanzu apps workload delete $PORTAL_WORKLOAD -n $STAGEPROD_NAMESPACE -y
        tanzu apps workload delete $SENSORS_WORKLOAD -n $STAGEPROD_NAMESPACE -y

        kubectl config use-context $PROD_CLUSTER
        kubectl delete -f ../$GITOPS_STAGE_REPO/config/dekt-apps/$ANALYZER_WORKLOAD -n $STAGEPROD_NAMESPACE
        kubectl delete -f ../$GITOPS_STAGE_REPO/config/dekt-apps/$PORTAL_WORKLOAD -n $STAGEPROD_NAMESPACE
        kubectl delete -f ../$GITOPS_STAGE_REPO/config/dekt-apps/$SENSORS_WORKLOAD -n $STAGEPROD_NAMESPACE
       
        
        kubectl config use-context $DEV_CLUSTER
        tanzu apps workload delete $ANALYZER_WORKLOAD -n $TEAM_NAMESPACE -y
        tanzu apps workload delete $PORTAL_WORKLOAD -n $TEAM_NAMESPACE -y
        tanzu apps workload delete $SENSORS_WORKLOAD -n $TEAM_NAMESPACE -y
        tanzu apps workload delete $DEV_WORKLOAD -n $DEV_NAMESPACE -y
        

        toggle-dog sad

        pushd ../$GITOPS_DEV_REPO
        git pull 
        git rm -rf config 
        git commit -m "reset" 
        git push 
        pushd
        
        pushd ../$GITOPS_STAGE_REPO
        git pull 
        git rm -rf config 
        git commit -m "reset" 
        git push 
        pushd

        #kubectl config use-context $VIEW_CLUSTER
        #kubectl delete pod -l app=backstage -n tap-gui
        ./builder.sh runme update-multi-cluster-access
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
        echo "  reset"
        exit
    }

#################### main ##########################

case $1 in
info)
    info
    ;;
dev)
    single-dev-workload
    ;;
team)
    create-workloads $DEV_CLUSTER $TEAM_NAMESPACE $DEV_BRANCH
    ;;
stage)
    create-workloads $STAGE_CLUSTER $STAGEPROD_NAMESPACE $STAGE_BRANCH
    ;;
prod)
    prod-roleout
    ;;
behappy)
    toggle-dog happy
    ;;   
besad)
    toggle-dog sad
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
cleanup-helper)
    cleanup-helper
    ;;
*)
    incorrect-usage
    ;;
esac
