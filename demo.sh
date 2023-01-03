#!/usr/bin/env bash

#################### load configs from values yaml  ################

    VIEW_CLUSTER=$(yq .clusters.view.name .config/demo-values.yaml)
    DEV_CLUSTER=$(yq .clusters.dev.name .config/demo-values.yaml)
    STAGE_CLUSTER=$(yq .clusters.stage.name .config/demo-values.yaml)
    PROD_CLUSTER=$(yq .clusters.prod.name .config/demo-values.yaml)
    BROWNFIELD_CLUSTER=$(yq .clusters.brownfield.name .config/demo-values.yaml)
    PRIVATE_CLUSTER=$(yq .brownfield_apis.privateClusterContext .config/demo-values.yaml)
    PORTAL_WORKLOAD="mood-portal"
    SENSORS_WORKLOAD="mood-sensors"
    ANALYZER_WORKLOAD="mood-analyzer"
    DEV_WORKLOAD="mysensors"
    GITOPS_DEV_REPO="gitops-dev"
    GITOPS_STAGE_REPO="gitops-stage"
    DEV_SUB_DOMAIN=$(yq .dns.devSubDomain .config/demo-values.yaml)
    RUN_SUB_DOMAIN=$(yq .dns.prodSubDomain .config/demo-values.yaml)
    DOMAIN=$(yq .dns.domain .config/demo-values.yaml)
    TAP_VERSION=$(yq .tap.tapVersion .config/demo-values.yaml)
    DEV_NAMESPACE=$(yq .apps_namespaces.dev .config/demo-values.yaml)
    TEAM_NAMESPACE=$(yq .apps_namespaces.team .config/demo-values.yaml)
    STAGEPROD_NAMESPACE=$(yq .apps_namespaces.stageProd .config/demo-values.yaml)
    HAPPY_THRESHOLD_MILD=3
    HAPPY_THRESHOLD_AGGRESSIVE=30
   
    

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
            scripts/dektecho.sh info "Social cluster (access via tanzu service mesh)"
            kubectl config use-context $BROWNFIELD_CLUSTER 
            kubectl cluster-info | grep 'control plane' --color=never

            scripts/dektecho.sh info "Private cluster (access via tanzu service mesh)"
            kubectl config use-context $PRIVATE_CLUSTER
            kubectl cluster-info | grep 'control plane' --color=never
        fi

        kubectl config use-context $DEV_CLUSTER 

    }
    
    #create-workloads
    create-workloads() {

        clusterName=$1
        appNamespace=$2
        export happyThreshold=$3
        subDomain=$4
        
        kubectl config use-context $clusterName
        
        yq '.spec.env[0].value = env(happyThreshold)' .config/workloads/mood-portal.yaml -i
        #set subdomain for api calls in mood-portal
        export sensorsActivateAPI="http://mood-sensors.$subDomain.$DOMAIN/activate"
        export sensorsMeasureAPI="http://mood-sensors.$subDomain.$DOMAIN/measure"
        yq '.spec.env[1].value = env(sensorsActivateAPI)' .config/workloads/mood-portal.yaml -i
        yq '.spec.env[2].value = env(sensorsMeasureAPI)' .config/workloads/mood-portal.yaml -i

        scripts/dektecho.sh cmd "tanzu apps workload create $PORTAL_WORKLOAD -f .config/workloads/mood-portal.yaml -y -n $appNamespace"
        tanzu apps workload create -f .config/workloads/mood-portal.yaml -y -n $appNamespace

        scripts/dektecho.sh cmd "tanzu apps workload create $SENSORS_WORKLOAD -f .config/workloads/mood-sensors.yaml -y -n $appNamespace"
        tanzu apps workload create -f .config/workloads/mood-sensors.yaml -y -n $appNamespace

        scripts/dektecho.sh cmd "tanzu apps workload create $ANALYZER_WORKLOAD -f .config/workloads/mood-analyzer.yaml -y -n $appNamespace"
        tanzu apps workload create -f .config/workloads/mood-analyzer.yaml -y -n $appNamespace

    }

    #single-dev-workload
    single-dev-workload() {

        kubectl config use-context $DEV_CLUSTER

        scripts/dektecho.sh cmd "tanzu apps workload create $DEV_WORKLOAD -f workload.yaml -n $DEV_NAMESPACE"
        tanzu apps workload create $DEV_WORKLOAD \
            --git-repo https://github.com/dektlong/mood-sensors \
            --git-branch main \
            --type dekt-api \
            --label apps.tanzu.vmware.com/has-tests="true" \
            --label app.kubernetes.io/part-of=$DEV_WORKLOAD \
            --yes \
            --namespace $DEV_NAMESPACE
    }

    #prod-roleout
    prod-roleout () {

        scripts/dektecho.sh info "Review Deliverables and ServiceBindings in gitops repo"

        scripts/dektecho.sh status "Pulling stage Deliverables and ServiceBindings from $GITOPS_STAGE_REPO repo"

        pushd ../$GITOPS_STAGE_REPO
        git pull 
        pushd

        scripts/dektecho.sh prompt  "Are you sure you want deploy to production?" && [ $? -eq 0 ] || exit
        
        kubectl config use-context $PROD_CLUSTER

        provision-rabbitmq $STAGEPROD_NAMESPACE 2
        provision-rds-postgres $STAGEPROD_NAMESPACE

        scripts/dektecho.sh status "Applying Deliverables and ServiceBindings to $PROD_CLUSTER cluster..."
        
        kubectl apply -f ../$GITOPS_STAGE_REPO/config/$STAGEPROD_NAMESPACE/$ANALYZER_WORKLOAD -n $STAGEPROD_NAMESPACE
        kubectl apply -f ../$GITOPS_STAGE_REPO/config/$STAGEPROD_NAMESPACE/$PORTAL_WORKLOAD -n $STAGEPROD_NAMESPACE
        kubectl apply -f ../$GITOPS_STAGE_REPO/config/$STAGEPROD_NAMESPACE/$SENSORS_WORKLOAD -n $STAGEPROD_NAMESPACE

        scripts/dektecho.sh status "Your DevX-Mood application is being deployed to production"

    }

    #provision-rabbitmq
    provision-rabbitmq() {

        appNamespace=$1
        export numReplicas=$2

        scripts/dektecho.sh status "Provision reading RabbitMQ instance(s) and service claim in $appNamespace namespace"
       
        #provision RabbitMQ 'reading' instance 
        yq '.spec.replicas = env(numReplicas)' .config/data-services/tanzu/reading-instance-tanzu_rabbitmq.yaml -i
        kubectl apply -f .config/data-services/tanzu/reading-instance-tanzu_rabbitmq.yaml -n $appNamespace

        #create a service claim
        tanzu service claim create rabbitmq-claim -n $appNamespace \
            --resource-name reading-queue \
            --resource-kind RabbitmqCluster \
            --resource-api-version rabbitmq.com/v1beta1
    }

    #provision-tanzu-postgres
    provision-tanzu-postgres() {

        appNamespace=$1

        scripts/dektecho.sh status "Provision inventory-db Tanzu Postgres instance and service claim in $appNamespace namespace"
       
        kubectl apply -f .config/data-services/tanzu/inventory-instance-tanzu_postgres.yaml -n $appNamespace

        #create inventory-db resource claim
        tanzu service claim create postgres-claim \
            --resource-name inventory-db \
            --resource-kind Postgres \
            --resource-api-version sql.tanzu.vmware.com/v1 \
            --resource-namespace $appNamespace \
            --namespace $appNamespace
    }

    #provision-rds-postgres
    provision-rds-postgres() {

        appNamespace=$1

        scripts/dektecho.sh status "Provision inventory-db RDS Postgres instance and service claim in $appNamespace namespace"

        kubectl apply -f .config/data-services/rds-postgres/crossplane-aws-provider.yaml

        kubectl apply -f .config/data-services/rds-postgres/crossplane-xrd-composition.yaml

        kubectl apply -f .config/data-services/rds-postgres/instance-class.yaml

        kubectl apply -f .config/data-services/rds-postgres/rds-secret.yaml -n $appNamespace 
        
        kubectl apply -f .config/data-services/rds-postgres/inventory-db-rds-instance.yaml -n $appNamespace

        tanzu service claim create postgres-claim \
            --resource-name inventory-db \
            --resource-kind Secret \
            --resource-api-version v1 \
            --resource-namespace $appNamespace \
            --namespace $appNamespace

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

    #data-services
    data-services() {

        tapCluster=$1
        appsNamespace=$2
        dbType=$3

        kubectl config use-context $tapCluster

        scripts/dektecho.sh cmd "tanzu service claim list -o wide -n $appsNamespace"
        tanzu service claim list -o wide -n $appsNamespace

        scripts/dektecho.sh cmd "kubectl get pods -n $appsNamespace | grep -E '(reading|inventory)'"
        kubectl get pods -n $appsNamespace | grep -E '(reading|inventory)'

        if [ "$dbType" == "rds" ]; then
            scripts/dektecho.sh cmd "kubectl get postgresqlinstance -n $appsNamespace"
            kubectl get postgresqlinstance -n $appsNamespace
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

        scripts/dektecho.sh info "Brownfield PROVIDERS services"
        kubectl config use-context $BROWNFIELD_CLUSTER 
        kubectl get svc -n brownfield-apis
        kubectl config use-context $PRIVATE_CLUSTER
        kubectl get svc -n brownfield-apis

        
    }

    #soft reset of all clusters configurations
    reset() {

        kubectl config use-context $STAGE_CLUSTER
        tanzu apps workload delete $ANALYZER_WORKLOAD -n $STAGEPROD_NAMESPACE -y
        tanzu apps workload delete $PORTAL_WORKLOAD -n $STAGEPROD_NAMESPACE -y
        tanzu apps workload delete $SENSORS_WORKLOAD -n $STAGEPROD_NAMESPACE -y
        tanzu service claims delete postgres-claim -y -n $STAGEPROD_NAMESPACE
        tanzu service claims delete rabbitmq-claim -y -n $STAGEPROD_NAMESPACE
        kubectl delete -f .config/data-services/rds-postgres/inventory-db-rds-instance.yaml -n $STAGEPROD_NAMESPACE
        kubectl delete -f .config/data-services/tanzu/reading-instance-tanzu_rabbitmq.yaml -n $STAGEPROD_NAMESPACE

        kubectl config use-context $PROD_CLUSTER
        kubectl delete -f ../$GITOPS_STAGE_REPO/config/dekt-apps/$ANALYZER_WORKLOAD -n $STAGEPROD_NAMESPACE
        kubectl delete -f ../$GITOPS_STAGE_REPO/config/dekt-apps/$PORTAL_WORKLOAD -n $STAGEPROD_NAMESPACE
        kubectl delete -f ../$GITOPS_STAGE_REPO/config/dekt-apps/$SENSORS_WORKLOAD -n $STAGEPROD_NAMESPACE
        tanzu service claims delete postgres-claim -y -n $STAGEPROD_NAMESPACE
        tanzu service claims delete rabbitmq-claim -y -n $STAGEPROD_NAMESPACE
        kubectl delete -f .config/data-services/rds-postgres/inventory-db-rds-instance.yaml -n $STAGEPROD_NAMESPACE
        kubectl delete -f .config/data-services/tanzu/reading-instance-tanzu_rabbitmq.yaml -n $STAGEPROD_NAMESPACE
       
        
        kubectl config use-context $DEV_CLUSTER
        tanzu apps workload delete $ANALYZER_WORKLOAD -n $TEAM_NAMESPACE -y
        tanzu apps workload delete $PORTAL_WORKLOAD -n $TEAM_NAMESPACE -y
        tanzu apps workload delete $SENSORS_WORKLOAD -n $TEAM_NAMESPACE -y
        tanzu apps workload delete $DEV_WORKLOAD -n $DEV_NAMESPACE -y
        tanzu service claims delete rabbitmq-claim -y -n $DEV_NAMESPACE
        tanzu service claims delete postgres-claim -y -n $TEAM_NAMESPACE
        tanzu service claims delete rabbitmq-claim -y -n $TEAM_NAMESPACE
        kubectl delete -f .config/data-services/tanzu/reading-instance-tanzu_rabbitmq.yaml -n $DEV_NAMESPACE
        kubectl delete -f .config/data-services/tanzu/inventory-instance-tanzu_postgres.yaml -n $TEAM_NAMESPACE
        kubectl delete -f .config/data-services/tanzu/reading-instance-tanzu_rabbitmq.yaml -n $TEAM_NAMESPACE

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

        ./builder.sh runme update-multi-cluster-access
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
        echo "  track team/stage [logs]"
        echo
        echo "  services dev/team/stage"
        echo
        echo "  brownfield"
        echo
        echo "  behappy"
        echo
        echo "  uninstall"
        exit
    }

#################### main ##########################

case $1 in
info)
    info
    ;;
dev)
    single-dev-workload
    provision-rabbitmq $DEV_NAMESPACE 1
    ;;
team)
    create-workloads $DEV_CLUSTER $TEAM_NAMESPACE $HAPPY_THRESHOLD_AGGRESSIVE $DEV_SUB_DOMAIN
    provision-rabbitmq $TEAM_NAMESPACE 1
    provision-tanzu-postgres $TEAM_NAMESPACE
    ;;
stage)
    create-workloads $STAGE_CLUSTER $STAGEPROD_NAMESPACE $HAPPY_THRESHOLD_MILD $RUN_SUB_DOMAIN
    provision-rabbitmq $STAGEPROD_NAMESPACE 2
    provision-rds-postgres $STAGEPROD_NAMESPACE
    ;;
prod)
    prod-roleout
    ;;
behappy)
    kubectl config use-context $DEV_CLUSTER
    tanzu apps workload update $PORTAL_WORKLOAD --env HAPPY_THRESHOLD=$HAPPY_THRESHOLD_MILD -n $TEAM_NAMESPACE 
    ;;   
supplychains)
    supplychains
    ;;
services)
    case $2 in
    dev)
        data-services $DEV_CLUSTER $DEV_NAMESPACE tanzu
        ;;
    team)
        data-services $DEV_CLUSTER $TEAM_NAMESPACE tanzu
        ;;
    stage)
        data-services $STAGE_CLUSTER $STAGEPROD_NAMESPACE rds
        ;;
    prod)
        data-services $PROD_CLUSTER $STAGEPROD_NAMESPACE rds
        ;;
    *)
        incorrect-usage
        ;;
    esac
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
