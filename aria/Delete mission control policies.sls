META:
  name: TMC - Image registry policy
  provider: TMC
  category: CONFIG
  subcategory: Foundation
  template_id: 6a.tmc.1
  version: v1
  description: enables image registry policy on a cluster namespace

## Required Parameters
{% set cluster_name = params.get('cluster_name') %}
{% set workspace_name = params.get('workspace_name') %}
{% set namespace_name = params.get('namespace_name') %}
{% set policy_name = params.get('policy_name') %}
{% set label_env_name = params.get('label_env_name') %}
{% set source_registry = params.get('source_registry') %}

## Optional Parameters
{% set policy_type = 'image-policy' %}
{% set policy_recipe = 'custom' %}

# create policy on workspace

{{workspace_name}}.{{policy_name}}:
  META:
    name: Create workspace policy in TMC.
    parameters:
      policy_name:
        name: policy name
        description: name of the image registry policy
        uiElement: text
      source_registry:
        name: source registry name
        description: source registry from which an image can be pulled
        uiElement: text
  tmc.workspace_policies.absent:
  - workspace_name: {{workspace_name}}
  - policy_recipe: {{policy_recipe}}
  - policy_name: {{policy_name}}
  - policy_type: {{policy_type}}
  - policy_input:
      rules:
        - hostname: {{source_registry}}

# create/attach namespace to a workspace

{{cluster_name}}.{{namespace_name}}:
  META:
    name: Create custer namespace
    parameters:
      cluster_name:
        name: cluster name
        description: name of the cluster
        uiElement: text
      namespace_name:
        name: namespace name
        description: name of the namespace to be created on cluster
        uiElement: text
      label_env_name:
        name: value for label env
        description: value for label env
        uiElement: text
  tmc.cluster_namespaces.absent:
  - cluster_name: {{cluster_name}}
  - namespace_name: {{namespace_name}}
  - workspace_name: {{workspace_name}}
  - description: demo namespace
  - labels:
      env: {{label_env_name}}
  - require:
      - tmc.workspace_policies: {{workspace_name}}.{{policy_name}}


# create workspace

{{workspace_name}}:
  META:
    name: Create workspace in TMC
    parameters:
      workspace_name:
        name: tmc workspace name
        description: name of the workspace to be created in tmc
        uiElement: text
      label_env_name:
        name: value for label env
        description: value for label env
        uiElement: text
  tmc.workspaces.absent:
  - name: {{workspace_name}}
  - description: demo workspace
  - labels:
      env: {{label_env_name}}
  - require:
      - tmc.cluster_namespaces: {{cluster_name}}.{{namespace_name}}