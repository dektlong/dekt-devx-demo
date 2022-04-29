#!/usr/bin/env bash


CLUSTER_NAME=$2
NUMBER_OF_NODES="$3"

#create-tkgm
create-tkgm () {

    if [ -z "$CLUSTER_NAME" ] | [ -z "$NUMBER_OF_NODES" ]; then
        incorrect-usage
    fi

    echo
	echo "Creating TKG-M cluster $CLUSTER_NAME with $NUMBER_OF_NODES nodes ..."
	echo

    #download the TKGM control cluster info from the ubuntu-jumpbox 
    #1. download the private key
    #2. ssh -i ~/Downloads/SC2__haas-414__private_environment.txt ubuntu@10.213.93.4
    #3. exit the ssh
    #4. scp ubuntu@10.213.93.4:/home/ubuntu/cluster-config.yaml .config/tkgm-cluster-config.yaml   
    tanzu cluster create $CLUSTER_NAME --file .config/tkgm-cluster-config.yaml --plan=dev

    tanzu cluster kubeconfig get $CLUSTER_NAME --admin 
    
    kubectl config use-context $CLUSTER_NAME-admin@$CLUSTER_NAME

    kubectl create clusterrolebinding default-tkg-admin-privileged-binding --clusterrole=psp:vmware-system-privileged --group=system:authenticated

#delete-tkgm
delete-tkgm() {

    if [ -z "$CLUSTER_NAME" ] ; then
        incorrect-usage
    fi
       
    echo
	echo "Starting deleting resources of TKG-M cluster $CLUSTER_NAME ..."
	echo

}

# create-pacific
#   $1 cluster name
#   $2 cluster plan
#   $3 number of master nodes
#   $4 number of worker nodes
create-pacific() {

    print-intro "vSpher7,TKG-s (aka embedded k8s in vSphere) " $1 $2 $3 $4 true

    #login to the supervisor cluster
    kubectl vsphere login \
        --insecure-skip-tls-verify \
        --server wcp.haas-$HAAS_SLOT.pez.vmware.com \
        -u administrator@vsphere.local


    #Password: VMware1!

    kubectl config use-context dekt-pacific
    
    kubectl apply -f configs/$1.yml

    echo
	echo "Wait until $3 master nodes and $2 worker nodes are in status 'Ready'"
 	echo
    kubectl get nodes -A -w

    echo
    kubectl get tanzukubernetesclusters -A

     #login to the worker cluster
    kubectl vsphere login --tanzu-kubernetes-cluster-name $1 --server wcp.haas-$HAAS_SLOT.pez.vmware.com --tanzu-kubernetes-cluster-namespace dekt-pacific --insecure-skip-tls-verify -u administrator@vsphere.local

    #Password: VMware1!
     
    kubectl config use-context $1

    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.3.6/components.yaml

    install-lb 
}

#create tkg  
#   $1 cluster name
#   $2 cluster plan
#   $3 number of master nodes
#   $4 number of worker nodes
create-tkg() {

    print-intro "vSpher7,TKG standalone" $1 $2 $3 $4 true

    tkg create cluster $1 --plan=$2 -w $3 -c $4

    tkg get credentials $1

    kubectl config use-context $1-admin@$1

    kubectl apply -f ~/Dropbox/Work/code/k8s-builder/configs/tkgi-vsphere-storageclass.yaml

    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.3.6/components.yaml

    install-lb 
}

#create tkg-i cluster on vSphere7  
#   $1 cluster name
#   $2 cluster plan
#   $3 number of master nodes (for printout only)
#   $4 number of worker nodes (for printout only)
create-pks() {
    
    pushd ../k8s-builder
    
    print-intro "vSphere7, TKG-I" $1 $2 $3 $4 false

    tkgi login -a api.pks.haas-$HAAS_SLOT.pez.vmware.com -u dekt -p appcloud -k
	
    tkgi create-cluster $1 -p $2 --external-hostname $1.pks.haas-$HAAS_SLOT.pez.vmware.com --wait
	
    echo
    echo "====> Create this A record: $1.pks.haas-$HAAS_SLOT.pez.vmware.com --> master node's ip"
    echo       
    echo "Hit any key to continue..."
	echo
	read 
	
    tkgi get-credentials $1

    kubectl apply -f ~/Dropbox/Work/code/k8s-builder/configs/tkgi-vsphere-storageclass.yaml 

    kubectl config set-cluster $1 --insecure-skip-tls-verify=1

    k8s-builders/install-ingress-controller.sh without-lb

}  
  
#print intro
#   $1 infrastructure configuration
#   $2 cluster name
#   $3 cluster plan
#   $4 number of master nodes
#   $5 number of worker nodes
#   $6 loadbalancer true/false
print-intro() {
    echo
    echo "========================================================================================="    
    echo
    echo "Building the following TKG cluster ..."
    echo
    echo "  * infrastructure configuration: $1"
    echo "  * cluster name: $2"
    echo "  * cluster plan: $3"
    echo "  * cluster size: $4 master(s) and $5 worker(s)"
    echo 
    echo "========================================================================================="    
    echo
}

#incorrect-usage
incorrect-usage() {
    echo "Incorrect usage. Please specify:"
    echo "  create [cluster-name number-of-nodes]"
    echo "  delete [cluster-name]"
    exit
}

#################### main #######################

case $1 in

create)
    create-tkgm
    ;;
delete)
    delete-tkgm
    ;;
*)
  	incorrect-usage
  	;;
esac