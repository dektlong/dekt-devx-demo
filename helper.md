# Helper commands for running the TAP supply chain demo (in logical order)

# Devs
tanzu apps workload apply devx-mood \
  -f workloads//devx-mood-workload.yaml \
  --namespace dekt-apps

# AppOps
tanzu package repository add tanzu-tap-repository \
  --url registry.tanzu.vmware.com/tanzu-application-platform/tap-packages:0.3.0 \
  --namespace tap-install

kubectl get pkgi -n tap-install

tanzu apps cluster-supply-chain list

# Devs
tanzu apps workload tail devx-mood --since 10m --timestamp  -n dekt-apps

tanzu apps workload get devx-mood -n dekt-apps

# AppOps
kp images list -n dekt-apps





# Troubleshooting

on EKS, if cloudformation stack fails to delete do the following:
  * Search "Elastic IP Address", delete all ips
  * Search "Elastic Load Balancing", delete all instances
  * Search "network interfaces", delete all instances
  * ignore the errors!, click refresh to make sure they are both delete
  * Search "cloud formation",  delete the faild stack, do not check any resources to retain
