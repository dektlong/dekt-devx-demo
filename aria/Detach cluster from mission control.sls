META:
  name: TMC - Reference implementation attach AWS EKS cluster to TMC
  provider: TMC
  category: CONFIG
  subcategory: Reference
  template_id: 6b.tmc.1
  version: v2
  description: Dettaches AWS EKS cluster attached to TMC
#Mandatory parameters
{% set group_name = params.get('group_name') %}
{% set cluster_name = params.get('cluster_name') %}
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
  tmc.clusters.absent:
  - cluster_name : {{cluster_name}}
  - group_name: {{group_name}}
  - description: "demo cluster"