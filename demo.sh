#!/usr/bin/env bash

#################### load configs from values yaml  ################

    VIEW_CLUSTER=$(yq .clusters.view.name .config/demo-values.yaml)
    DEV_CLUSTER=$(yq .clusters.dev.name .config/demo-values.yaml)
    STAGE_CLUSTER=$(yq .clusters.stage.name .config/demo-values.yaml)
    STAGE_CLUSTER_PROVIDER=$(yq .clusters.stage.provider .config/demo-values.yaml)
    PROD1_CLUSTER=$(yq .clusters.prod1.name .config/demo-values.yaml)
    PROD1_CLUSTER_PROVIDER=$(yq .clusters.prod1.provider .config/demo-values.yaml)
    PROD2_CLUSTER=$(yq .clusters.prod2.name .config/demo-values.yaml)
    PROD2_CLUSTER_PROVIDER=$(yq .clusters.prod2.provider .config/demo-values.yaml)
    BROWNFIELD_CLUSTER=$(yq .clusters.brownfield.name .config/demo-values.yaml)
    PRIVATE_CLUSTER=$(yq .brownfield_apis.privateClusterContext .config/demo-values.yaml)
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
    IMAGE_SCAN_TEMPLATE_PORTAL=$(yq .tap.scanTemplates.portal .config/demo-values.yaml)
    IMAGE_SCAN_TEMPLATE_SENSORS=$(yq .tap.scanTemplates.sensors .config/demo-values.yaml)
    IMAGE_SCAN_TEMPLATE_DOCTOR=$(yq .tap.scanTemplates.doctor .config/demo-values.yaml)
    IMAGE_SCAN_TEMPLATE_PREDICTOR=$(yq .tap.scanTemplates.predictor .config/demo-values.yaml)
    IMAGE_SCAN_TEMPLATE_PAINTER=$(yq .tap.scanTemplates.painter .config/demo-values.yaml)
    ISV_IMAGE=$(yq .private_registry.host .config/demo-values.yaml)/isvs/$(yq .tap.isvImg .config/demo-values.yaml)
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
        scripts/dektecho.sh cmd "tanzu apps workload create myportal -f .config/workloads/mood-portal.yaml -y -n $DEV1_NAMESPACE"
        tanzu apps workload create myportal -f .config/workloads/mood-portal.yaml \
            --env SNIFF_THRESHOLD=$SNIFF_THRESHOLD_AGGRESSIVE \
            -y -n $DEV1_NAMESPACE

        #dev2 workload (updated via VS Code)
        #tanzu apps workload create mysensor -f .config/workloads/mood-sensors.yaml -y -n $DEV2_NAMESPACE
    }

    #create-workloads
    create-workloads() {

        appNamespace=$1
        sniffThershold=$2

        #portal workload
        scripts/dektecho.sh cmd "tanzu apps workload create -f .config/workloads/mood-portal.yaml -y -n $appNamespace" 
        tanzu apps workload create -f .config/workloads/mood-portal.yaml \
            --param scanning_image_template=$IMAGE_SCAN_TEMPLATE_PORTAL \
            --env SNIFF_THRESHOLD=$sniffThershold \
            -y -n $appNamespace

        #sensors workload
        scripts/dektecho.sh cmd "tanzu apps workload create -f .config/workloads/mood-sensors.yaml -y -n $appNamespace"
         tanzu apps workload create -f .config/workloads/mood-sensors.yaml \
            --param scanning_image_template=$IMAGE_SCAN_TEMPLATE_SENSORS \
             -y -n $appNamespace

        #doctor workload
        scripts/dektecho.sh cmd "tanzu apps workload create -f .config/workloads/mood-doctor.yaml -y -n $appNamespace"
        tanzu apps workload create -f .config/workloads/mood-doctor.yaml \
            --param scanning_image_template=$IMAGE_SCAN_TEMPLATE_DOCTOR \
            -y -n $appNamespace

        #predictor workload 
        kubectl apply -f .config/secrets/openai-creds.yaml -n $appNamespace
        scripts/dektecho.sh cmd "tanzu apps workload create -f .config/workloads/mood-predictor.yaml -y -n $appNamespace"
        tanzu apps workload create -f .config/workloads/mood-predictor.yaml \
            --param scanning_image_template=$IMAGE_SCAN_TEMPLATE_PREDICTOR \
            -y -n $appNamespace

        #painter workload 
        scripts/dektecho.sh cmd "tanzu apps workload create -f .config/workloads/mood-painter.yaml -y -n $appNamespace"
        tanzu apps workload create -f .config/workloads/mood-painter.yaml \
            --image $ISV_IMAGE \
            --param scanning_image_template=$IMAGE_SCAN_TEMPLATE_PAINTER \
            -y -n $appNamespace

    }

    #prod-roleout
    prod-roleout () {

        scripts/dektecho.sh info "Pulling staging deliverables from $STAGE_GITOPS_REPO repo"
        
        pushd ../$STAGE_GITOPS_REPO
        git pull 
        pushd

        scripts/dektecho.sh prompt  "Deliverables pulled to  ../$STAGE_GITOPS_REPO/config/$STAGEPROD_NAMESPACE. Press 'y' to continue deploying to production clusters" && [ $? -eq 0 ] || exit
        
        scripts/dektecho.sh info "Deploying services and workloads to $PROD1_CLUSTER production cluster..."
        kubectl config use-context $PROD1_CLUSTER
        create-stageprod-claims $PROD1_CLUSTER_PROVIDER
        apply-prod-deliverables

        scripts/dektecho.sh info "Deploying services and workloads to $PROD2_CLUSTER production cluster..."
        kubectl config use-context $PROD2_CLUSTER
        create-stageprod-claims $PROD2_CLUSTER_PROVIDER
        apply-prod-deliverables

    }

    #create-team-claims
    create-team-claims () {

        scripts/dektecho.sh status "Creating data services via class-claim dynamic provisioning"

        tanzu service class-claim create rabbitmq-claim \
            --class rabbitmq-unmanaged \
            --parameter replicas=1 \
            --parameter storageGB=1 \
            --namespace $TEAM_NAMESPACE 

        tanzu service class-claim create postgres-claim \
            --class postgresql-unmanaged \
            --parameter storageGB=2 \
            --namespace $TEAM_NAMESPACE 

    }

    #create-stageprod-claims
    create-stageprod-claims () {

        provider=$1

        scripts/dektecho.sh status "Creating RabbitMQ class-claim"

        tanzu service class-claim create rabbitmq-claim \
            --class rabbitmq-operator-corp \
            --parameter replicas=3 \
            --parameter storageGB=2 \
            --namespace $STAGEPROD_NAMESPACE
        
        case $provider in
            eks) 
                scripts/dektecho.sh status "Create Amazon RDS postgres class claim"
                tanzu service class-claim create postgres-claim \
                    --class postgres-rds-corp \
                    --namespace $STAGEPROD_NAMESPACE
                ;;
            gke) 
                scripts/dektecho.sh status "Create Google CloudSQL postgres class claim"
                tanzu service class-claim create postgres-claim \
                    --class postgres-cloudsql-corp \
                    --namespace $STAGEPROD_NAMESPACE
                ;;
            aks) 
                scripts/dektecho.sh status "Create Azure SQL postgres resource claim"
                #kubectl apply -f .config/dataservices/azure/azuresql-postgres-instance.yaml -n $STAGEPROD_NAMESPACE
                #tanzu service class-claim create postgres-claim \
                #    --class postgres-azuresql-corp \
                #    --namespace $STAGEPROD_NAMESPACE
                tanzu service resource-claim create postgres-claim \
                    --resource-name external-azure-db-binding-compatible \
                    --resource-kind Secret \
                    --resource-api-version v1 \
                    --namespace $STAGEPROD_NAMESPACE
                ;;
            *)
                scripts/dektecho.sh err "k8s provider $provider is not supported for creating cloud databases"
                ;;
            esac
    }


    #apply-prod-deliverable
    apply-prod-deliverables() {

        kubectl apply -f ../$STAGE_GITOPS_REPO/config/$STAGEPROD_NAMESPACE/mood-portal -n $STAGEPROD_NAMESPACE
        kubectl apply -f ../$STAGE_GITOPS_REPO/config/$STAGEPROD_NAMESPACE/mood-sensors -n $STAGEPROD_NAMESPACE
        kubectl apply -f ../$STAGE_GITOPS_REPO/config/$STAGEPROD_NAMESPACE/mood-predictor -n $STAGEPROD_NAMESPACE
        kubectl apply -f ../$STAGE_GITOPS_REPO/config/$STAGEPROD_NAMESPACE/mood-painter -n $STAGEPROD_NAMESPACE

    }

    #track-sensors
    track-sensors () {

        appNamespace=$1
        showLogs=$2

        if [ "$showLogs" == "logs" ]
        then
            scripts/dektecho.sh cmd "tanzu apps workload tail mood-sensors --since 100m --timestamp  -n $appNamespace"
            tanzu apps workload tail mood-sensors --since 100m --timestamp  -n $appNamespace
        else
            scripts/dektecho.sh cmd "tanzu apps workload get mood-sensors -n $appNamespace"
            tanzu apps workload get mood-sensors -n $appNamespace
        fi
    }
    #services
    services () {

        case $1 in
        dev)
            kubectl config use-context $DEV_CLUSTER
            scripts/dektecho.sh cmd "tanzu services class-claim list -n $TEAM_NAMESPACE"
            tanzu services class-claim list -n $TEAM_NAMESPACE
            ;;
        stage)
            kubectl config use-context $STAGE_CLUSTER
            scripts/dektecho.sh cmd "tanzu services class-claim list -n $STAGEPROD_NAMESPACE"
            tanzu services class-claim list -n $STAGEPROD_NAMESPACE
            tanzu services resource-claims get postgres-claim -n devxmood
            ;;
        prod)
            kubectl config use-context $PROD1_CLUSTER
            scripts/dektecho.sh cmd "tanzu services class-claim list -n $STAGEPROD_NAMESPACE"
            tanzu services class-claim list -n $STAGEPROD_NAMESPACE
            echo
            kubectl config use-context $PROD2_CLUSTER
            scripts/dektecho.sh cmd "tanzu services class-claim list -n $STAGEPROD_NAMESPACE"
            tanzu services class-claim list -n $STAGEPROD_NAMESPACE
            ;;
        *)
        incorrect-usage
        ;;
    esac
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
        tanzu apps workload delete myportal -n $DEV1_NAMESPACE -y
        tanzu apps workload delete mysensors -n $DEV2_NAMESPACE -y
    }
    
    #reset-team-stage
    reset-team-stage() {

        clusterName=$1
        appNamespace=$2
        
        kubectl config use-context $clusterName

        kubectl delete -f .config/workloads -n $appNamespace
        tanzu service class-claim delete postgres-claim -y -n $appNamespace
        tanzu service class-claim delete rabbitmq-claim -y -n $appNamespace
    }

    #reset-prod
    reset-prod () {

        clusterName=$1

        kubectl config use-context $clusterName
        kubectl delete -f ../$STAGE_GITOPS_REPO/config/$STAGEPROD_NAMESPACE/mood-portal -n $STAGEPROD_NAMESPACE
        kubectl delete -f ../$STAGE_GITOPS_REPO/config/$STAGEPROD_NAMESPACE/mood-sensors -n $STAGEPROD_NAMESPACE
        kubectl delete -f ../$STAGE_GITOPS_REPO/config/$STAGEPROD_NAMESPACE/mood-predictor -n $STAGEPROD_NAMESPACE
        kubectl delete -f ../$STAGE_GITOPS_REPO/config/$STAGEPROD_NAMESPACE/mood-painter -n $STAGEPROD_NAMESPACE
        tanzu service class-claim delete postgres-claim -y -n $STAGEPROD_NAMESPACE
        tanzu service class-claim delete rabbitmq-claim -y -n $STAGEPROD_NAMESPACE
      
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
        echo "  services dev/stage/prod"
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
    create-team-claims
    create-workloads $TEAM_NAMESPACE $SNIFF_THRESHOLD_AGGRESSIVE
    ;;
stage)
    kubectl config use-context $STAGE_CLUSTER
    create-stageprod-claims $STAGE_CLUSTER_PROVIDER
    create-workloads $STAGEPROD_NAMESPACE $SNIFF_THRESHOLD_MILD
    ;;
prod)
    prod-roleout
    ;;
behappy)
    kubectl config use-context $DEV_CLUSTER
    tanzu apps workload apply mood-portal --env SNIFF_THRESHOLD=$SNIFF_THRESHOLD_MILD -n $TEAM_NAMESPACE -y
    ;;   
besad)
    kubectl config use-context $DEV_CLUSTER
    tanzu apps workload apply  mood-portal --env SNIFF_THRESHOLD=$SNIFF_THRESHOLD_AGGRESSIVE -n $TEAM_NAMESPACE -y
    ;;
track)
    case $2 in
    dev)
        kubectl config use-context $DEV_CLUSTER
        track-sensors $TEAM_NAMESPACE $3
        ;;
    stage)
        kubectl config use-context $STAGE_CLUSTER
        track-sensors $STAGEPROD_NAMESPACE $3
        ;;
    *)
        incorrect-usage
        ;;
    esac
    ;;
services)
    services $2
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
