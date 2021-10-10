#!/usr/bin/env bash


#################### functions #######################

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

#incorrect usage
incorrect-usage() {
	echo
    echo "Incorrect usage. Required: TKG-version [tkg-m/tkg-s/tkg-i], cluster-name, cluster-plan, num-master-nodes, num-workers-nodes"
    echo "  e.g. build-tkg-cluster.sh tkg-i mycluster small 1 3"
    echo
  	exit   
}

#################### main #######################

source secrets/config-values.env

case $1 in
tkg-m)
    create-tkg $2 $3 $4 $5
	;;
tkg-s)
    create-pacific $2 $3 $4 $5
	;;
tkg-i)
    create-pks $2 $3 $4 $5
	;;
*)
  	incorrect-usage
  	;;
esac