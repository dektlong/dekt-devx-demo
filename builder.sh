#!/usr/bin/env bash

#################### configs ################
    #clusters
    DEV_CLUSTER_NAME=$(yq .clusters.dev.name .config/demo-values.yaml)
    DEV_CLUSTER_PROVIDER=$(yq .clusters.dev.provider .config/demo-values.yaml)
    DEV_CLUSTER_NODES=$(yq .clusters.dev.nodes .config/demo-values.yaml)
    STAGE_CLUSTER_NAME=$(yq .clusters.stage.name .config/demo-values.yaml)
    STAGE_CLUSTER_PROVIDER=$(yq .clusters.stage.provider .config/demo-values.yaml)
    STAGE_CLUSTER_NODES=$(yq .clusters.stage.nodes .config/demo-values.yaml)
    PROD1_CLUSTER_NAME=$(yq .clusters.prod1.name .config/demo-values.yaml)
    PROD1_CLUSTER_PROVIDER=$(yq .clusters.prod1.provider .config/demo-values.yaml)
    PROD1_CLUSTER_NODES=$(yq .clusters.prod1.nodes .config/demo-values.yaml)
    PROD2_CLUSTER_NAME=$(yq .clusters.prod2.name .config/demo-values.yaml)
    PROD2_CLUSTER_PROVIDER=$(yq .clusters.prod2.provider .config/demo-values.yaml)
    PROD2_CLUSTER_NODES=$(yq .clusters.prod2.nodes .config/demo-values.yaml)
    VIEW_CLUSTER_NAME=$(yq .clusters.view.name .config/demo-values.yaml)
    VIEW_CLUSTER_PROVIDER=$(yq .clusters.view.provider .config/demo-values.yaml)
    VIEW_CLUSTER_NODES=$(yq .clusters.view.nodes .config/demo-values.yaml)
    BROWNFIELD_CLUSTER_NAME=$(yq .clusters.brownfield.name .config/demo-values.yaml)
    BROWNFIELD_CLUSTER_PROVIDER=$(yq .clusters.brownfield.provider .config/demo-values.yaml)
    BROWNFIELD_CLUSTER_NODES=$(yq .clusters.brownfield.nodes .config/demo-values.yaml)
    PRIVATE_CLUSTER_NAME=$(yq .brownfield_apis.privateClusterContext .config/demo-values.yaml)

    #image registry
    PRIVATE_REGISTRY_SERVER=$(yq .private_registry.host .config/demo-values.yaml)
    PRIVATE_RGISTRY_USER=$(yq .private_registry.username .config/demo-values.yaml)
    PRIVATE_RGISTRY_PASSWORD=$(yq .private_registry.password .config/demo-values.yaml)
    PRIVATE_RGISTRY_REPO=$(yq .private_registry.repo .config/demo-values.yaml)
    #tap
    TANZU_NETWORK_USER=$(yq .tanzu_network.username .config/demo-values.yaml)
    TANZU_NETWORK_PASSWORD=$(yq .tanzu_network.password .config/demo-values.yaml)
    TAP_VERSION=$(yq .tap.tapVersion .config/demo-values.yaml)
    CARVEL_BUNDLE=$(yq .tap.carvel_bundle .config/demo-values.yaml)
    SYS_INGRESS_ISSUER=$(yq .tap.sysIngressIssuer .config/demo-values.yaml)
    APPS_INGRESS_ISSUER=$(yq .tap.appsIngressIssuer .config/demo-values.yaml)

    #apps-namespaces
    DEV1_NAMESPACE=$(yq .apps_namespaces.dev1 .config/demo-values.yaml)
    DEV2_NAMESPACE=$(yq .apps_namespaces.dev2 .config/demo-values.yaml)
    TEAM_NAMESPACE=$(yq .apps_namespaces.team .config/demo-values.yaml)
    STAGEPROD_NAMESPACE=$(yq .apps_namespaces.stageProd .config/demo-values.yaml)
    #domains
    SYSTEM_SUB_DOMAIN=$(yq .dns.sysSubDomain .config/demo-values.yaml)
    DEV_SUB_DOMAIN=$(yq .dns.devSubDomain .config/demo-values.yaml)
    PROD1_SUB_DOMAIN=$(yq .dns.prod1SubDomain .config/demo-values.yaml)
    PROD2_SUB_DOMAIN=$(yq .dns.prod2SubDomain .config/demo-values.yaml)
    #data-services
    CLOUD_DB=$(yq .tap.cloudDB .config/demo-values.yaml)
    #apis
    GW_INSTALL_DIR=$(yq .brownfield_apis.scgwInstallDirectory .config/demo-values.yaml)
 
#################### functions ################

    
    #install-view-cluster
    install-view-cluster() {

        scripts/dektecho.sh info "Installing demo components for $VIEW_CLUSTER_NAME cluster"

        kubectl config use-context $VIEW_CLUSTER_NAME

        scripts/tanzu-handler.sh add-carvel-tools
        
        install-tap "tap-view.yaml"

        scripts/dektecho.sh status "Adding custom accelerators"
        kubectl apply -f accelerators -n accelerator-system

        scripts/ingress-handler.sh update-tap-dns $SYSTEM_SUB_DOMAIN $VIEW_CLUSTER_PROVIDER

        process-view-ingress-issuer

    }

    #install-dev-cluster
    install-dev-cluster() {

        scripts/dektecho.sh info "Installing demo components for $DEV_CLUSTER_NAME cluster"

        kubectl config use-context $DEV_CLUSTER_NAME

        scripts/tanzu-handler.sh add-carvel-tools

        setup-app-ns $DEV1_NAMESPACE
        setup-app-ns $DEV2_NAMESPACE
        setup-app-ns $TEAM_NAMESPACE

        install-tap "tap-dev.yaml"

        scripts/ingress-handler.sh update-tap-dns $DEV_SUB_DOMAIN $DEV_CLUSTER_PROVIDER

        if [ "$APPS_INGRESS_ISSUER" != "tap-ingress-selfsigned" ]  
        then
            kubectl apply -f .config/secrets/ingress-issuer-apps.yaml
        fi

    }

    #install-stage-cluster
    install-stage-cluster() {

        scripts/dektecho.sh info "Installing demo components for $STAGE_CLUSTER_NAME cluster"

        kubectl config use-context $STAGE_CLUSTER_NAME

        scripts/tanzu-handler.sh add-carvel-tools

        setup-metadata-store

        setup-app-ns $STAGEPROD_NAMESPACE with-scans

        install-tap "tap-stage.yaml"

        if [ "$APPS_INGRESS_ISSUER" != "tap-ingress-selfsigned" ]  
        then
            kubectl apply -f .config/secrets/ingress-issuer-apps.yaml
        fi

    }
    
    #install-prod-cluster1
    install-prod-cluster1() {

        scripts/dektecho.sh info "Installing demo components for $PROD1_CLUSTER_NAME cluster"

        kubectl config use-context $PROD1_CLUSTER_NAME

        scripts/tanzu-handler.sh add-carvel-tools

        setup-app-ns $STAGEPROD_NAMESPACE

        install-tap "tap-prod1.yaml"

        install-rds-psql

        scripts/ingress-handler.sh update-tap-dns $PROD1_SUB_DOMAIN $PROD1_CLUSTER_PROVIDER

        if [ "$APPS_INGRESS_ISSUER" != "tap-ingress-selfsigned" ]  
        then
            kubectl apply -f .config/secrets/ingress-issuer-apps.yaml
        fi

    }

    #install-prod-cluster2
    install-prod-cluster2() {

        scripts/dektecho.sh info "Installing demo components for $PROD2_CLUSTER_NAME cluster"

        kubectl config use-context $PROD2_CLUSTER_NAME

        scripts/tanzu-handler.sh add-carvel-tools

        setup-app-ns $STAGEPROD_NAMESPACE

        install-tap "tap-prod2.yaml"

        install-rds-psql

        scripts/ingress-handler.sh update-tap-dns $PROD2_SUB_DOMAIN $PROD2_CLUSTER_PROVIDER

         if [ "$APPS_INGRESS_ISSUER" != "tap-ingress-selfsigned" ]  
         then
            kubectl apply -f .config/secrets/ingress-issuer-apps.yaml
         fi

    }

    #install-tap
    install-tap() {

        tap_values_file_name=$1

        scripts/dektecho.sh status "Installing TAP on $(kubectl config current-context) cluster with $tap_values_file_name configs"

        kubectl create ns tap-install

        kubectl apply -f .config/secrets/git-creds-sa-overlay.yaml

        tanzu secret registry add private-repo-creds \
            --server $PRIVATE_REGISTRY_SERVER \
            --username ${PRIVATE_RGISTRY_USER} \
            --password ${PRIVATE_RGISTRY_PASSWORD} \
            --export-to-all-namespaces \
            --yes \
            --namespace tap-install

        tanzu package repository add tanzu-tap-repository \
            --url $PRIVATE_REGISTRY_SERVER/$PRIVATE_RGISTRY_REPO/tap-packages:$TAP_VERSION \
            --namespace tap-install

        tanzu package install tap -p tap.tanzu.vmware.com -v $TAP_VERSION \
            --values-file .config/tap-profiles/$tap_values_file_name \
            --namespace tap-install
        
      }

    #setup-app-ne
    setup-app-ns() {

        appnamespace=$1

        scripts/dektecho.sh status "Setting up $appnamespace as a TAP application namespace"

        kubectl create ns $appnamespace
        kubectl label namespaces $appnamespace apps.tanzu.vmware.com/tap-ns="" 

        kubectl apply -f .config/secrets/git-creds.yaml -n $appnamespace

        if [ "$2" == "with-scans" ]; then
            kubectl apply -f .config/secrets/snyk-creds.yaml -n $appnamespace
            kubectl apply -f .config/secrets/carbonblack-creds.yaml -n $appnamespace
        fi

    }
    #setup-metadata-store
    setup-metadata-store() {

        scripts/dektecho.sh status "Configure metadata-store access between $VIEW_CLUSTER_NAME and $STAGE_CLUSTER_NAME"
        
        kubectl config use-context $VIEW_CLUSTER_NAME
        CA_CERT=$(kubectl get secret -n metadata-store ingress-cert -o json | jq -r ".data.\"ca.crt\"")
cat <<EOF > .config/secrets/store_ca.yaml
---
apiVersion: v1
kind: Secret
type: Opaque
metadata:
  name: store-ca-cert
  namespace: metadata-store-secrets
data:
  ca.crt: $CA_CERT
EOF
        
        AUTH_TOKEN=$(kubectl get secrets metadata-store-read-write-client -n metadata-store -o jsonpath="{.data.token}" | base64 -d)

        kubectl config use-context $STAGE_CLUSTER_NAME
        kubectl create ns metadata-store-secrets
        kubectl apply -f .config/secrets/store_ca.yaml
        kubectl create secret generic store-auth-token \
            --from-literal=auth_token=$AUTH_TOKEN -n metadata-store-secrets
cat <<EOF | kubectl apply -f -
---
apiVersion: secretgen.carvel.dev/v1alpha1
kind: SecretExport
metadata:
  name: store-ca-cert
  namespace: metadata-store-secrets
spec:
  toNamespace: $STAGEPROD_NAMESPACE
---
apiVersion: secretgen.carvel.dev/v1alpha1
kind: SecretExport
metadata:
  name: store-auth-token
  namespace: metadata-store-secrets
spec:
  toNamespace: $STAGEPROD_NAMESPACE
EOF

   rm .config/secrets/store_ca.yaml

    }

    #setup-access-to-view-cluster
    setup-access-to-view-cluster() {

        export clusterName=$1
        export clusterIndex=$2
        
        scripts/dektecho.sh status "Setup access between $clusterName and $VIEW_CLUSTER_NAME ..."

        kubectl config use-context $clusterName
        kubectl apply -f .config/secrets/viewer-rbac.yaml
        export clusterUrl=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: tap-gui-viewer
  namespace: tap-gui
  annotations:
    kubernetes.io/service-account.name: tap-gui-viewer
type: kubernetes.io/service-account-token
EOF
        export clusterToken=$(kubectl -n tap-gui get secret tap-gui-viewer -o=json \
            | jq -r '.data["token"]' \
            | base64 --decode)

        yq '.tap_gui.app_config.kubernetes.clusterLocatorMethods.[0].clusters.[env(clusterIndex)].url = env(clusterUrl)' .config/tap-profiles/tap-view.yaml -i
        yq '.tap_gui.app_config.kubernetes.clusterLocatorMethods.[0].clusters.[env(clusterIndex)].name = env(clusterName)' .config/tap-profiles/tap-view.yaml -i
        yq '.tap_gui.app_config.kubernetes.clusterLocatorMethods.[0].clusters.[env(clusterIndex)].serviceAccountToken = env(clusterToken)' .config/tap-profiles/tap-view.yaml -i

        kubectl apply -f .config/secrets/viewer-rbac.yaml
    } 

    #install-rds-psql
    install-rds-psql () {

        scripts/dektecho.sh status "Installing rds-postgres DB connector via crossplane"
        
        kubectl apply -f .config/crossplane/aws/provider.yaml
        
        kubectl wait "providers.pkg.crossplane.io/provider-aws" --for=condition=Installed --timeout=180s
        kubectl wait "providers.pkg.crossplane.io/provider-aws" --for=condition=Healthy --timeout=180s

        AWS_PROFILE=default && echo -e "[default]\naws_access_key_id = $(aws configure get aws_access_key_id --profile $AWS_PROFILE)\naws_secret_access_key = $(aws configure get aws_secret_access_key --profile $AWS_PROFILE)\naws_session_token = $(aws configure get aws_session_token --profile $AWS_PROFILE)" > creds.conf

        kubectl create secret generic aws-provider-creds -n crossplane-system --from-file=creds=./creds.conf

        rm -f creds.conf

kubectl apply -f -<<EOF
---
apiVersion: aws.crossplane.io/v1beta1
kind: ProviderConfig
metadata:
  name: default
spec:
  credentials:
    source: Secret
    secretRef:
      namespace: crossplane-system
      name: aws-provider-creds
      key: creds
EOF

 
        
       kubectl apply -f .config/crossplane/aws/rds-psql-xrd.yaml

       kubectl apply -f .config/crossplane/aws/rds-psql-composition.yaml

       kubectl apply -f .config/crossplane/aws/rds-psql-class.yaml

       kubectl apply -f .config/crossplane/aws/rds-psql-rbac.yaml
        

    }


    #process-view-ingress-issuer
    process-view-ingress-issuer() {

        

        if [ "$SYS_INGRESS_ISSUER" == "tap-ingress-selfsigned" ]   #if using self-signed CA , it needs to be trusted explicitly by ALV
        then
            
            kubectl get secret appliveview-cert -n app-live-view -o yaml | yq '.data."ca.crt"' | base64 -d > .config/secrets/alv-cert.pem
            yq '.appliveview_connector.backend.caCertData = load_str(".config/secrets/alv-cert.pem")' .config/tap-profiles/tap-dev.yaml -i
            rm .config/secrets/alv-cert.pem
        else #workaround for the acme-solver image pull issue
            yq '.appliveview_connector.backend.caCertData = ""' .config/tap-profiles/tap-dev.yaml -i
            tanzu secret registry add acme-pull \
            --server $PRIVATE_REGISTRY_SERVER \
            --username ${PRIVATE_RGISTRY_USER} \
            --password ${PRIVATE_RGISTRY_PASSWORD} \
            --yes \
            --namespace metadata-store
            tanzu secret registry add acme-pull \
            --server $PRIVATE_REGISTRY_SERVER \
            --username ${PRIVATE_RGISTRY_USER} \
            --password ${PRIVATE_RGISTRY_PASSWORD} \
            --yes \
            --namespace app-live-view
            kubectl apply -f .config/secrets/ingress-issuer-sys.yaml
        fi

    }

    #add-brownfield-apis
    add-brownfield-apis () {
        
        brownfield_apis_ns="brownfield"

        scripts/dektecho.sh info "Installing brownfield APIs components"

        scripts/dektecho.sh status "adding 'provider' components on $BROWNFIELD_CLUSTER_NAME cluster"
        kubectl config use-context $BROWNFIELD_CLUSTER_NAME
        kubectl create ns scgw-system
        kubectl create secret docker-registry spring-cloud-gateway-image-pull-secret --docker-server=$PRIVATE_REGISTRY_SERVER --docker-username=$PRIVATE_RGISTRY_USER --docker-password=$PRIVATE_RGISTRY_PASSWORD --namespace scgw-system
        $GW_INSTALL_DIR/scripts/install-spring-cloud-gateway.sh --namespace scgw-system
        kubectl create ns $brownfield_apis_ns
        kubectl apply -f brownfield-apis/sentiment.yaml -n $brownfield_apis_ns
    
        scripts/dektecho.sh status "adding'consumer' components on $DEV_CLUSTER_NAME cluster"
        kubectl config use-context $DEV_CLUSTER_NAME
        kubectl create ns $brownfield_apis_ns
        kubectl create service clusterip sentiment-api --tcp=80:80 -n $brownfield_apis_ns
        kubectl create service clusterip datacheck-api --tcp=80:80 -n $brownfield_apis_ns

        scripts/dektecho.sh status "adding 'consumer' components on $STAGE_CLUSTER_NAME cluster"
        kubectl config use-context $STAGE_CLUSTER_NAME
        kubectl create ns $brownfield_apis_ns
        kubectl create service clusterip sentiment-api --tcp=80:80 -n $brownfield_apis_ns
        kubectl create service clusterip datacheck-api --tcp=80:80 -n $brownfield_apis_ns

        scripts/dektecho.sh status "adding 'consumer' components on $PROD1_CLUSTER_NAME cluster"
        kubectl config use-context $PROD1_CLUSTER_NAME
        kubectl create ns $brownfield_apis_ns
        kubectl create service clusterip sentiment-api --tcp=80:80 -n $brownfield_apis_ns
        kubectl create service clusterip datacheck-api --tcp=80:80 -n $brownfield_apis_ns

        scripts/dektecho.sh status "adding 'consumer' components on $PROD2_CLUSTER_NAME cluster"
        kubectl config use-context $PROD2_CLUSTER_NAME
        kubectl create ns $brownfield_apis_ns
        kubectl create service clusterip sentiment-api --tcp=80:80 -n $brownfield_apis_ns
        kubectl create service clusterip datacheck-api --tcp=80:80 -n $brownfield_apis_ns

    }

  
    #delete-tmc-cluster
    delete-tmc-clusters() {

        scripts/tanzu-handler.sh tmc-cluster remove $VIEW_CLUSTER_NAME
        scripts/tanzu-handler.sh tmc-cluster remove $DEV_CLUSTER_NAME
        scripts/tanzu-handler.sh tmc-cluster remove $STAGE_CLUSTER_NAME
        scripts/tanzu-handler.sh tmc-cluster remove $PROD1_CLUSTER_NAME
        scripts/tanzu-handler.sh tmc-cluster remove $PROD2_CLUSTER_NAME
        scripts/tanzu-handler.sh tmc-cluster remove $BROWNFIELD_CLUSTER_NAME
    }

    #update-tap
    update-tap ()
    {
        case $1 in
        view) 
            kubectl config use-context $VIEW_CLUSTER_NAME
            tanzu package installed update tap --values-file .config/tap-profiles/tap-view.yaml -n tap-install
            ;;
        dev) 
            kubectl config use-context $DEV_CLUSTER_NAME
            tanzu package installed update tap --values-file .config/tap-profiles/tap-dev.yaml -n tap-install
            ;;
        stage) 
            kubectl config use-context $STAGE_CLUSTER_NAME
            tanzu package installed update tap --values-file .config/tap-profiles/tap-stage.yaml -n tap-install
            ;;
        prod) 
            kubectl config use-context $PROD1_CLUSTER_NAME
            tanzu package installed update tap --values-file .config/tap-profiles/tap-prod1.yaml -n tap-install
            kubectl config use-context $PROD2_CLUSTER_NAME
            tanzu package installed update tap --values-file .config/tap-profiles/tap-prod2.yaml -n tap-install
            ;;
        multicluster)
            setup-access-to-view-cluster $DEV_CLUSTER_NAME 0
            setup-access-to-view-cluster $STAGE_CLUSTER_NAME 1
            update-tap view
            ;;
        *)
            incorrect-usage
            ;;
        esac
    }

    #install-devstage
    install-devstage () {
        
        install-view-cluster
        install-dev-cluster
        install-stage-cluster
        update-tap multicluster

        scripts/tanzu-handler.sh tmc-cluster attach $VIEW_CLUSTER_NAME
        scripts/tanzu-handler.sh tmc-cluster attach $DEV_CLUSTER_NAME
        scripts/tanzu-handler.sh tmc-cluster attach $STAGE_CLUSTER_NAME
    }

    #install-prod()
    install-prod() {

        install-prod-cluster1 
        install-prod-cluster2
        add-brownfield-apis
        
        scripts/tanzu-handler.sh tmc-cluster attach $PROD1_CLUSTER_NAME
        scripts/tanzu-handler.sh tmc-cluster attach $PROD2_CLUSTER_NAME
        scripts/tanzu-handler.sh tmc-cluster attach $BROWNFIELD_CLUSTER_NAME

    }

    
    #incorrect usage
    incorrect-usage() {
        
        scripts/dektecho.sh err "Incorrect usage. Please specify one of the following: "
        
        echo "  create-clusters [ all | devstage ]"
        echo
        echo "  install  [ all | devstage | prod ]"
        echo 
        echo "  delete-all"
        echo
        echo "  generate-configs"
        echo
        echo "  update-tap view [ dev | stage | prod | multicluster ]"
        echo
        echo "  export-packages [ tap | tbs | tds | scgw ]"
        echo
        echo "  runme [ function-name ]"
        echo
        exit
    }


#################### main ##########################


case $1 in
create-clusters)
    case $2 in
    all)
        scripts/k8s-handler.sh create $VIEW_CLUSTER_PROVIDER $VIEW_CLUSTER_NAME $VIEW_CLUSTER_NODES \
        & scripts/k8s-handler.sh create $DEV_CLUSTER_PROVIDER $DEV_CLUSTER_NAME $DEV_CLUSTER_NODES \
        & scripts/k8s-handler.sh create $STAGE_CLUSTER_PROVIDER $STAGE_CLUSTER_NAME $STAGE_CLUSTER_NODES \
        & scripts/k8s-handler.sh create $PROD1_CLUSTER_PROVIDER $PROD1_CLUSTER_NAME $PROD1_CLUSTER_NODES \
        & scripts/k8s-handler.sh create $PROD2_CLUSTER_PROVIDER $PROD2_CLUSTER_NAME $PROD2_CLUSTER_NODES \
        & scripts/k8s-handler.sh create $BROWNFIELD_CLUSTER_PROVIDER $BROWNFIELD_CLUSTER_NAME $BROWNFIELD_CLUSTER_NODES  
        ;;
    devstage)
        scripts/k8s-handler.sh create $VIEW_CLUSTER_PROVIDER $VIEW_CLUSTER_NAME $VIEW_CLUSTER_NODES \
        & scripts/k8s-handler.sh create $DEV_CLUSTER_PROVIDER $DEV_CLUSTER_NAME $DEV_CLUSTER_NODES \
        & scripts/k8s-handler.sh create $STAGE_CLUSTER_PROVIDER $STAGE_CLUSTER_NAME $STAGE_CLUSTER_NODES \
        ;;
    *)
        incorrect-usage
        ;;
    esac
    ;;
install)
    case $2 in
    all)
        install-devstage
        install-prod
        ;;
    devstage) 
        install-devstage
        ;;
    prod)
        install-prod
        ;; 
    *)
        incorrect-usage
        ;;
    esac
    ;;
delete-all)
    scripts/dektecho.sh prompt  "Are you sure you want to delete all clusters?" && [ $? -eq 0 ] || exit
    ./demo.sh reset
    delete-tmc-clusters
    scripts/k8s-handler.sh delete $VIEW_CLUSTER_PROVIDER $VIEW_CLUSTER_NAME \
    & scripts/k8s-handler.sh delete $DEV_CLUSTER_PROVIDER $DEV_CLUSTER_NAME \
    & scripts/k8s-handler.sh delete $STAGE_CLUSTER_PROVIDER $STAGE_CLUSTER_NAME \
    & scripts/k8s-handler.sh delete $PROD1_CLUSTER_PROVIDER $PROD1_CLUSTER_NAME \
    & scripts/k8s-handler.sh delete $PROD2_CLUSTER_PROVIDER $PROD2_CLUSTER_NAME \
    & scripts/k8s-handler.sh delete $BROWNFIELD_CLUSTER_PROVIDER $BROWNFIELD_CLUSTER_NAME
    ;;
generate-configs)
    scripts/tanzu-handler.sh generate-configs
    ;;
update-tap)
    update-tap $2
    ;;
export-packages)
    scripts/tanzu-handler.sh relocate-tanzu-images $2
    ;;
runme)
    $2 $3 $4
    ;;
*)
    incorrect-usage
    ;;
esac