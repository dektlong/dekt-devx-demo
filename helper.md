
# AppOps: tap install on any k8s

tanzu package install tap -p tap.tanzu.vmware.com -v 1.0.1  --values-file tap-values.yaml -n tap-install

tanzu package installed list -A


# Devs: devx-mood workload
tanzu apps workload apply devx-mood -f workloads/devx-mood/devx-mood.yaml -n dekt-apps

tanzu apps workload list -n dekt-apps

# Devs: devx-mood-backend api

tanzu apps workload apply devx-mood-sensors --type web --git-repo https://github.com/dektlong/devx-mood-sensors --git-branch main --label autoscaling.knative.dev/minScale=2 -n dekt-apps -y

curl http://devx-mood-backend.dekt-apps.cnr.dekt.io/write 
curl http://devx-mood-backend.dekt-apps.cnr.dekt.io/sensors-data

# AppOps: supply chains

tanzu apps cluster-supply-chain list

(let's see how each supply chain was created)

# Devs: devx-mood function
tanzu apps workload tail devx-mood --since 10m --timestamp  -n dekt-apps

tanzu apps workload get devx-mood -n dekt-apps

# AppOps
kp images list -n dekt-apps
