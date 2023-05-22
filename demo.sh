#!/usr/bin/env bash

#################### load configs from values yaml  ################

    VIEW_CLUSTER=$(yq .clusters.view.name .config/demo-values.yaml)
    DEV_CLUSTER=$(yq .clusters.dev.name .config/demo-values.yaml)
    STAGE_CLUSTER=$(yq .clusters.stage.name .config/demo-values.yaml)
    PROD1_CLUSTER=$(yq .clusters.prod1.name .config/demo-values.yaml)
    PROD2_CLUSTER=$(yq .clusters.prod2.name .config/demo-values.yaml)
    BROWNFIELD_CLUSTER=$(yq .clusters.brownfield.name .config/demo-values.yaml)
    PRIVATE_CLUSTER=$(yq .brownfield_apis.privateClusterContext .config/demo-values.yaml)
    PORTAL_WORKLOAD="mood-portal"
    SENSORS_WORKLOAD="mood-sensors"
    MEDICAL_WORKLOAD="mood-doctor"
    PREDICTOR_WORKLOAD="mood-predictor"
    DEV1_WORKLOAD="myportal"
    DEV2_WORKLOAD="mysensors"
    DEV_SUB_DOMAIN=$(yq .dns.devSubDomain .config/demo-values.yaml)
    PROD1_SUB_DOMAIN=$(yq .dns.prod1SubDomain .config/demo-values.yaml)
    PROD2_SUB_DOMAIN=$(yq .dns.prod2SubDomain .config/demo-values.yaml)
    DOMAIN=$(yq .dns.domain .config/demo-values.yaml)
    TAP_VERSION=$(yq .tap.tapVersion .config/demo-values.yaml)
    DEV1_NAMESPACE=$(yq .apps_namespaces.dev1 .config/demo-values.yaml)
    DEV2_NAMESPACE=$(yq .apps_namespaces.dev2 .config/demo-values.yaml)
    TEAM_NAMESPACE=$(yq .apps_namespaces.team .config/demo-values.yaml)
    STAGEPROD_NAMESPACE=$(yq .apps_namespaces.stageProd .config/demo-values.yaml)
    SNIFF_THRESHOLD_MILD=15
    SNIFF_THRESHOLD_AGGRESSIVE=50
    PREDICTOR_IMAGE=$(yq .private_registry.host .config/demo-values.yaml)/isvs/$(yq .tap.isvImg .config/demo-values.yaml)
    IMAGE_SCAN_TEMPLATE_PORTAL=$(yq .tap.imageScanPortal .config/demo-values.yaml)
    IMAGE_SCAN_TEMPLATE_SENSORS=$(yq .tap.imageScanSensors .config/demo-values.yaml)
    IMAGE_SCAN_TEMPLATE_DOCTOR=$(yq .tap.imageScanDoctor .config/demo-values.yaml)
    IMAGE_SCAN_TEMPLATE_PREDICTOR=$(yq .tap.imageScanPredictor .config/demo-values.yaml)
    DEV_GITOPS_REPO=$(yq .gitops.deliverables.devRepo .config/demo-values.yaml)
    STAGE_GITOPS_REPO=$(yq .gitops.deliverables.stageRepo .config/demo-values.yaml)
    

    

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

        scripts/dektecho.sh info "Production cluster $PROD1_CLUSTER (TAP 'run' profile)"
        kubectl config use-context $PROD1_CLUSTER 
        kubectl cluster-info | grep 'control plane' --color=never
        tanzu package installed list -n tap-install

        scripts/dektecho.sh info "Production cluster $PROD2_CLUSTER (TAP 'run' profile)"
        kubectl config use-context $PROD2_CLUSTER 
        kubectl cluster-info | grep 'control plane' --color=never
        tanzu package installed list -n tap-install

        scripts/dektecho.sh info "Social cluster (access via tanzu service mesh)"
        kubectl config use-context $BROWNFIELD_CLUSTER 
        kubectl cluster-info | grep 'control plane' --color=never

        kubectl config use-context $DEV_CLUSTER 

    }
        
    #create-mydev
    create-mydev() {

        #dev1 workload
        scripts/dektecho.sh cmd "tanzu apps workload create $DEV1_WORKLOAD -f .config/workloads/mood-portal.yaml -y -n $DEV1_NAMESPACE"
        tanzu apps workload create $DEV1_WORKLOAD -f .config/workloads/mood-portal.yaml \
            --env SNIFF_THRESHOLD=$SNIFF_THRESHOLD_AGGRESSIVE \
            -y -n $DEV1_NAMESPACE

        #dev2 workload (updated via VS Code)
        #tanzu apps workload create $DEV2_WORKLOAD -f .config/workloads/mood-sensors.yaml -y -n $DEV2_NAMESPACE
    }

    #create-workloads
    create-workloads() {

        appNamespace=$1
        sniffThershold=$2
        sqlClass=$3
        
        #postgreSQL inventory db
        scripts/dektecho.sh cmd "tanzu service class-claim create inventory --class $sqlClass --parameter storageGB=2 -n $appNamespace"
        tanzu service class-claim create inventory --class $sqlClass --parameter storageGB=2  -n $appNamespace

        #rabbitmq reading queue
        scripts/dektecho.sh cmd "tanzu service class-claim create reading --class rabbitmq-unmanaged --parameter replicas=2 --parameter storageGB=1 -n $appNamespace"
        tanzu service class-claim create reading --class rabbitmq-unmanaged --parameter replicas=2 --parameter storageGB=1 -n $appNamespace
    

        #portal workload
        scripts/dektecho.sh cmd "tanzu apps workload create $PORTAL_WORKLOAD -f .config/workloads/mood-portal.yaml -y -n $appNamespace" 
        tanzu apps workload create $PORTAL_WORKLOAD -f .config/workloads/mood-portal.yaml \
            --param scanning_image_template=$IMAGE_SCAN_TEMPLATE_PORTAL \
            --env SNIFF_THRESHOLD=$sniffThershold \
            -y -n $appNamespace

        #sensors workload
        scripts/dektecho.sh cmd "tanzu apps workload create $SENSORS_WORKLOAD -f .config/workloads/mood-sensors.yaml -y -n $appNamespace"
         tanzu apps workload create $SENSORS_WORKLOAD -f .config/workloads/mood-sensors.yaml \
            --param scanning_image_template=$IMAGE_SCAN_TEMPLATE_SENSORS \
            --service-ref inventory-claim=services.apps.tanzu.vmware.com/v1alpha1:ClassClaim:inventory \
            --service-ref reading-claim=services.apps.tanzu.vmware.com/v1alpha1:ClassClaim:reading \
            -y -n $appNamespace

        #doctor workload
        scripts/dektecho.sh cmd "tanzu apps workload create $MEDICAL_WORKLOAD -f .config/workloads/mood-doctor.yaml -y -n $appNamespace"
        tanzu apps workload create $MEDICAL_WORKLOAD -f .config/workloads/mood-doctor.yaml \
            --param scanning_image_template=$IMAGE_SCAN_TEMPLATE_DOCTOR \
            --service-ref reading-claim=services.apps.tanzu.vmware.com/v1alpha1:ClassClaim:reading \
            -y -n $appNamespace

        #predictor workload 
        scripts/dektecho.sh cmd "tanzu apps workload create $PREDICTOR_WORKLOAD -f .config/workloads/mood-predictor.yaml -y -n $appNamespace"
        tanzu apps workload create $PREDICTOR_WORKLOAD -f .config/workloads/mood-predictor.yaml \
            --image $PREDICTOR_IMAGE \
            --param scanning_image_template=$IMAGE_SCAN_TEMPLATE_PREDICTOR \
            -y -n $appNamespace

    }

    #prod-roleout
    prod-roleout () {

        scripts/dektecho.sh status "Pulling staging deliverables from $STAGE_GITOPS_REPO repo"
        
        pushd ../$STAGE_GITOPS_REPO
        git pull 
        pushd

        scripts/dektecho.sh prompt  "Deliverables pulled to  ../$STAGE_GITOPS_REPO/config/$STAGEPROD_NAMESPACE. Press 'y' to continue deploying to production clusters" && [ $? -eq 0 ] || exit
        
        prod-deploy $PROD1_CLUSTER
        prod-deploy $PROD2_CLUSTER

    }

    #prod-deploy
    prod-deploy() {

        clusterName=$1

        kubectl config use-context $clusterName
        scripts/dektecho.sh status "Creating data services in $clusterName production cluster..."
        tanzu service class-claim create inventory --class aws-rds-psql -p storageGB=30 -n $STAGEPROD_NAMESPACE
        tanzu service class-claim create reading --class rabbitmq-unmanaged --parameter replicas=2 --parameter storageGB=1 -n $STAGEPROD_NAMESPACE
        
        scripts/dektecho.sh status "Applying staging deliverables to $clusterName production cluster..."
        kubectl apply -f ../$STAGE_GITOPS_REPO/config/$STAGEPROD_NAMESPACE/$MEDICAL_WORKLOAD -n $STAGEPROD_NAMESPACE
        kubectl apply -f ../$STAGE_GITOPS_REPO/config/$STAGEPROD_NAMESPACE/$PORTAL_WORKLOAD -n $STAGEPROD_NAMESPACE
        kubectl apply -f ../$STAGE_GITOPS_REPO/config/$STAGEPROD_NAMESPACE/$SENSORS_WORKLOAD -n $STAGEPROD_NAMESPACE

    }

    #supplychains
    supplychains () {

        scripts/dektecho.sh cmd "tanzu apps cluster-supply-chain list"
        
        tanzu apps cluster-supply-chain list
    }

    #track-workloads
    track-workloads () {

        appNamespace=$1
        showLogs=$2

        scripts/dektecho.sh cmd "tanzu apps workload get $PORTAL_WORKLOAD -n $appNamespace"
        tanzu apps workload get $PORTAL_WORKLOAD -n $appNamespace

        scripts/dektecho.sh cmd "tanzu apps workload get $MEDICAL_WORKLOAD -n $appNamespace"
        tanzu apps workload get $MEDICAL_WORKLOAD -n $appNamespace

        scripts/dektecho.sh cmd "tanzu apps workload get $SENSORS_WORKLOAD -n $appNamespace"
        tanzu apps workload get $SENSORS_WORKLOAD -n $appNamespace
        
        if [ "$showLogs" == "logs" ]; then
            scripts/dektecho.sh cmd "tanzu apps workload tail $SENSORS_WORKLOAD --since 100m --timestamp  -n $appNamespace"
            
            tanzu apps workload tail $SENSORS_WORKLOAD --since 100m --timestamp  -n $appNamespace
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
        kubectl config use-context $PROD1_CLUSTER
        kubectl get svc -n brownfield-apis
        kubectl config use-context $PROD2_CLUSTER
        kubectl get svc -n brownfield-apis

        scripts/dektecho.sh info "Brownfield PROVIDERS services"
        kubectl config use-context $BROWNFIELD_CLUSTER 
        kubectl get svc -n brownfield-apis
        
    }

    #soft reset of all clusters configurations
    reset() {

        reset-dev
        reset-team-stage $DEV_CLUSTER $TEAM_NAMESPACE
        reset-team-stage $STAGE_CLUSTER $STAGEPROD_NAMESPACE
        reset-prod $PROD1_CLUSTER 
        reset-prod $PROD2_CLUSTER 
        reset-deliverable-gitops
        #./builder.sh update-tap multicluster

    }

    #reset-dev
    reset-dev () {

        kubectl config use-context $DEV_CLUSTER
        tanzu apps workload delete $DEV1_WORKLOAD -n $DEV1_NAMESPACE -y
        tanzu apps workload delete $DEV2_WORKLOAD -n $DEV2_NAMESPACE -y
    }
    
    #reset-team-stage
    reset-team-stage() {

        clusterName=$1
        appNamespace=$2
        
        kubectl config use-context $clusterName

        tanzu apps workload delete $MEDICAL_WORKLOAD -n $appNamespace -y
        tanzu apps workload delete $PREDICTOR_WORKLOAD -n $appNamespace -y
        tanzu apps workload delete $PORTAL_WORKLOAD -n $appNamespace -y
        tanzu apps workload delete $SENSORS_WORKLOAD -n $appNamespace -y
        tanzu service class-claim delete reading -y -n $appNamespace
        tanzu service class-claim delete inventory -y -n $appNamespace
    }

    #reset-prod
    reset-prod () {

        clusterName=$1

        kubectl config use-context $clusterName
        kubectl delete -f ../$STAGE_GITOPS_REPO/config/$STAGEPROD_NAMESPACE/$MEDICAL_WORKLOAD -n $STAGEPROD_NAMESPACE
        kubectl delete -f ../$STAGE_GITOPS_REPO/config/$STAGEPROD_NAMESPACE/$PORTAL_WORKLOAD -n $STAGEPROD_NAMESPACE
        kubectl delete -f ../$STAGE_GITOPS_REPO/config/$STAGEPROD_NAMESPACE/$SENSORS_WORKLOAD -n $STAGEPROD_NAMESPACE
        tanzu service class-claim delete reading -y -n $STAGEPROD_NAMESPACE
        tanzu service class-claim delete inventory -y -n $STAGEPROD_NAMESPACE
      
      
    }

    #reset-deliverable-gitops
    reset-deliverable-gitops () {

        pushd ../$DEV_GITOPS_REPO
        git pull 
        git rm -rf config 
        git commit -m "reset" 
        git push 
        pushd

        pushd ../$STAGE_GITOPS_REPO
        git pull 
        git rm -rf config 
        git commit -m "reset" 
        git push 
        pushd
    }

    #incorrect usage
    incorrect-usage() {
        
        echo
        scripts/dektecho.sh err "Incorrect usage. Please specify one of the following: "
        echo
        echo "  info (display packages on all clusters)"
        echo
        echo "  dev"
        echo
        echo "  stage"
        echo
        echo "  prod (role out to 2 prod clusters)"
        echo
        echo "  track dev/stage [logs]"
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
dev)
    kubectl config use-context $DEV_CLUSTER
    create-mydev
    create-workloads $TEAM_NAMESPACE $SNIFF_THRESHOLD_AGGRESSIVE "postgresql-unmanaged"
    ;;
stage)
    kubectl config use-context $STAGE_CLUSTER
    create-workloads $STAGEPROD_NAMESPACE $SNIFF_THRESHOLD_MILD "aws-rds-psql"
    ;;
prod)
    prod-roleout
    ;;
behappy)
    kubectl config use-context $DEV_CLUSTER
    tanzu apps workload apply $PORTAL_WORKLOAD --env SNIFF_THRESHOLD=$SNIFF_THRESHOLD_MILD -n $TEAM_NAMESPACE -y
    ;;   
besad)
    kubectl config use-context $DEV_CLUSTER
    tanzu apps workload apply $PORTAL_WORKLOAD --env SNIFF_THRESHOLD=$SNIFF_THRESHOLD_AGGRESSIVE -n $TEAM_NAMESPACE -y
    ;;
track)
    case $2 in
    dev)
        kubectl config use-context $DEV_CLUSTER
        track-workloads $TEAM_NAMESPACE $3
        ;;
    stage)
        kubectl config use-context $STAGE_CLUSTER
        track-workloads $STAGEPROD_NAMESPACE $3
        ;;
    *)
        incorrect-usage
        ;;
    esac
    ;;
brownfield)
    brownfield
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
