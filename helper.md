#tanzu package install tap -p tap.tanzu.vmware.com -v 1.0.1  --values-file tap-values.yaml -n tap-install

tanzu package installed list -n tap-install

tanzu apps workload apply -f ~/Downloads/workload.yaml -n dekt-apps

tanzu apps workload list -n dekt-apps

tanzu apps cluster-supply-chain list

tanzu apps workload get mood-portal -n dekt-apps

tanzu apps workload tail mood-portal --since 10m --timestamp  -n dekt-apps

tanzu apps workload get mood-sensors -n dekt-apps

https://github.com/dektlong/_DevXDemo/blob/main/workloads/devx-mood/backstage/catalog-info.yaml
