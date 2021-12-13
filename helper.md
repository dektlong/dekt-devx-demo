kubectl get pkgi -n tap-install

# Helper commands for running the TAP supply chain demo (in logical order)

# Devs
tanzu apps workload apply devx-mood -f workloads/devx-mood/devx-mood.yaml -n dekt-apps

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

  * Delete LB 
    https://us-west-1.console.aws.amazon.com/ec2/v2/home?region=us-west-1#LoadBalancers:sort=loadBalancerName

  * Delete all network interfaces, if still exists
    https://us-west-1.console.aws.amazon.com/ec2/v2/home?region=us-west-1#NIC:

  * delete the vpc with your cluster name in it
    https://us-west-1.console.aws.amazon.com/vpc/home?region=us-west-1#vpcs:

  * delete the faild stack, do not check any resources to retain
    https://us-west-1.console.aws.amazon.com/cloudformation/home?region=us-west-1#/stacks?filteringStatus=active&filteringText=&viewNested=true&hideStacks=false
