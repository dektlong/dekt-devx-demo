# Demo helper commands

## TAP install
tanzu package install tap -p tap.tanzu.vmware.com -v 1.0.1  --values-file tap-values.yaml -n tap-install

tanzu package installed list -n tap-install

## workloads
tanzu apps workload create -f ../mood-portal/workload.yaml -y -n dekt-apps

tanzu apps workload create -f ../mood-sensors/workload.yaml -y -n dekt-apps

tanzu apps workload list -n dekt-apps

## supply chains
tanzu apps cluster-supply-chain list

## track workload progress
tanzu apps workload get mood-sensors -n dekt-apps

kubectl describe imagescan.scanning.apps.tanzu.vmware.com/mood-sensors -n dekt-apps

tanzu apps workload tail mood-sensors --since 100m --timestamp  -n dekt-apps

kc get ServiceBinding -n dekt-apps

## mood-portal code change
./builder.sh be-happy

tanzu apps workload get mood-portal -n dekt-apps

kubectl get pods -n dekt-apps

## multi k8s
kubectl config get-contexts
kubectl config use-context dekel@dekt-eks.us-west-1.eksctl.io
kubectl config use-context dekt-aks

create workloads 