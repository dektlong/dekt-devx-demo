# Demo helper commands

## TAP install
tanzu package install tap -p tap.tanzu.vmware.com -v 1.0.1  --values-file tap-values-full.yaml -n tap-install

tanzu package installed list -n tap-install

## workloads
tanzu apps workload create -f ../mood-portal/workload.yaml -y -n dekt-apps

tanzu apps workload create -f ../mood-sensors/workload.yaml -y -n dekt-apps

tanzu apps workload list -n dekt-apps

## supply chains
tanzu apps cluster-supply-chain list

### track workload progress
tanzu apps workload get mood-sensors -n dekt-apps

kubectl describe imagescan.scanning.apps.tanzu.vmware.com/mood-sensors -n dekt-apps

tanzu apps workload tail mood-sensors --since 100m --timestamp  -n dekt-apps

kubeclt get ServiceBinding -n dekt-apps

## mood-portal code change 
(can skip if no time and show the intergrate branch already has the change)

./builder.sh be-happy
tanzu apps workload get mood-portal -n dekt-apps
kubectl get pods -n dekt-apps

## Promote to production

### 'promote' to Build cluster (source code)

kubectl config use-context dekt-integrate
tanzu package installed list -n tap-install

tanzu apps workload create mood-portal \
--git-repo https://github.com/dektlong/mood-portal \
--git-branch integrate \
--type web \
--label app.kubernetes.io/part-of=devx-mood \
--yes \
--namespace dekt-apps

    show supply chain progress on multi-cluster Backstage

tanzu apps workload get mood-portal -n dekt-apps

kubectl get deliverable mood-portal -n dekt-apps -oyaml > mood-portal-deliverable.yaml

    Delete the ownerReferences and status sections from the deliverable.yaml

### 'promote' to Run cluster (Deliverable) 

kubectl config use-context dekt-prod  

tanzu package installed list -n tap-install 

kubectl apply -f mood-portal-deliverable.yaml -n dekt-apps
kubectl get deliverables -n dekt-apps
kubectl get httpproxy -n dekt-apps
    show that the new Deliverable is deployed on the production domain - run.dekt.io


## multi k8s
kubectl config get-contexts
kubectl config use-context dekel@dekt-eks.us-west-1.eksctl.io
kubectl config use-context dekt-aks

create workloads 