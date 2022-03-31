#!/usr/bin/env bash


#create-cluster
create-cluster() {

	minikube start --cpus='8' --memory='10g' --kubernetes-version='1.22.6' --keep-context=true

	minikube tunnel

	kubectl config use-context minikube
}

delete-cluster() {
	
	minikube stop

}
#################### main #######################

case $1 in
create)
  	create-cluster
    ;;
delete)
    delete-cluster
    ;;
*)
	echo "Incorrect usage. Please specific 'create' or 'delete'"
	;;
esac
