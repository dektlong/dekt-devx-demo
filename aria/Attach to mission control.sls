META:
  name: TMC - Reference implementation attach AWS EKS cluster to TMC
  provider: TMC
  category: CONFIG
  subcategory: Reference
  template_id: 6b.tmc.1
  version: v2
  description: Attaches AWS EKS cluster to TMC and enables data protection on a cluster

#Mandatory parameters
{% set group_name = params.get('group_name') %}
{% set cluster_name = params.get('cluster_name') %}
{% set backup_location = params.get('backup_location') %}
{% set region = params.get('region') %}
{% set credential = params.get('credential') %}
{% set target_provider = params.get('target_provider') %}
{% set label_env_name = params.get('label_env_name') %}

#Optional parameters
{% set provider_name = 'tmc' %}
{% set total_timeout_seconds = 240 %}
{% set delay_interval_seconds = 30 %}
{% set cluster_status = 'READY' %}
{% set cluster_health = 'HEALTHY' %}


#searches aws eks cluster
Search AWS EKS cluster {{cluster_name}}:
  META:
    name: Search AWS EKS cluster
    parameters:
      cluster_name:
        name: cluster name
        description: name of the aws eks cluster
        uiElement: text
  exec.run:
    - path: aws.eks.cluster.get
    - kwargs:
        name: Search AWS EKS cluster {{cluster_name}}
        resource_id: {{cluster_name}}

#create cluster group
Create cluster group in TMC {{group_name}}:
  META:
    name: Create cluster group in TMC
    parameters:
      group_name:
        name: cluster group name
        description: name of the tmc cluster group
        uiElement: text
      label_env_name:
        name: value for label env
        description: value for label env
        uiElement: text
  tmc.cluster_groups.present:
  - name: {{group_name}}
  - description: "demo cluster group"
  - labels:
       env: {{label_env_name}}
  - require:
      - exec: Search AWS EKS cluster {{cluster_name}}

#attaches cluster on tmc
"Attach TMC cluster":
  META:
    name: Attaches EKS cluster in TMC
    parameters:
      cluster_name:
        name: cluster name
        description: name of the cluster to the attached in tmc
        uiElement: text
      group_name:
        name: cluster group name
        description: name of the tmc cluster group
        uiElement: text
      label_env_name:
        name: value for label env
        description: value for label env
        uiElement: text
  tmc.clusters.present:
  - cluster_name : {{cluster_name}}
  - group_name: {{group_name}}
  - description: "demo cluster"
  - labels:
       env: {{label_env_name}}
  - require:
      - tmc.cluster_groups: Create cluster group in TMC {{group_name}}

#generate eks token
"Generate EKS token":
  META:
    name: Generates EKS token
    parameters:
      cluster_name:
        name: cluster name
        description: name of the cluster to the attached in tmc
        uiElement: text
      region:
        name: aws region name
        description: name of the aws region in which the aws EKS cluster is created
        uiElement: text
  ekstoken.token.present:
  - cluster_name: {{cluster_name}}
  - region: {{region}}
  - require:
      - tmc.clusters: "Attach TMC cluster"

#apply TMC manifest uri on eks_cluster
"Apply TMC installer on EKS cluster":
  META:
    name: Apply TMC manifest on EKS cluster
    parameters:
      cluster_name:
        name: cluster name
        description: name of the cluster to the attached in tmc
        uiElement: text
  kubernetes.manifest.present:
  - manifest_uri: ${tmc.clusters:Attach TMC cluster:status:installerLink}
  - cluster_name: {{cluster_name}}
  - cluster_config:
      provider: "aws"
      cluster_endpoint: ${exec:Search AWS EKS cluster {{cluster_name}}:endpoint}
      cluster_cert: ${exec:Search AWS EKS cluster {{cluster_name}}:certificate_authority:data}
      eks_cluster_token:  ${ekstoken.token:generate eks_token:token}
  - require:
      - ekstoken.token: "Generate EKS token"

#checks status of tmc cluster attachment
"Check cluster status":
  META:
    name: Check status of EKS cluster attachment in TMC
    type: tmc_attach_cluster
    parameters:
      cluster_name:
        name: cluster name
        description: name of the cluster to the attached in tmc
        uiElement: text
      group_name:
        name: cluster group name
        description: name of the tmc cluster group
        uiElement: text
  tmc.clusters.present:
    - cluster_name: {{cluster_name}}
    - group_name: {{group_name}}
    - check_status:
        total_timeout_seconds: {{total_timeout_seconds}}
    - require:
        - kubernetes.manifest: "Apply TMC installer on EKS cluster"

#create backup location
Create backup location in TMC {{backup_location}}:
  META:
    name: Create backup location in TMC
    parameters:
      backup_location:
        name: backup_location name
        description: name of the backup location that you can use for storage of backups
        uiElement: text
      credential:
        name: credential name
        description: name of the credential used to connect to the target backup location
      target_provider:
        name: target provider name
        description: name of the target provider
        uiElement: text
  tmc.backup_locations.present:
  - name: {{backup_location}}
  - provider_name: {{provider_name}}
  - credential:
      name: {{credential}}
  - target_provider: {{target_provider}}
  - assigned_groups:
    - clustergroup:
        name: "${tmc.cluster_groups:Create cluster group in TMC {{group_name}}:name}"
  - require:
      - tmc.clusters: "Check cluster status"

# Setup/ Enable data protection on cluster as present in TMC_Cluster_1
Enable data protection in TMC {{cluster_name}}.{{backup_location}}:
  META:
    name: Enable data protection in TMC
  tmc.data_protections.present:
  - name: {{cluster_name}}.{{backup_location}}
  - cluster_name: "${tmc.clusters:Check cluster status:name}"
  - backup_location_names:
    - "${tmc.backup_locations:Create backup location in TMC {{backup_location}}:name}"
  - require:
      - tmc.backup_locations: Create backup location in TMC {{backup_location}}