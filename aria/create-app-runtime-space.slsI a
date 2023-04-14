META:
  name: Create App runtime space 
  provider: SaltStack
  category: SECURITY
  subcategory: Reference
  template_id: 3b.ssc.11
  version: v1
  description: Create App runtime space

{% set tgt_name = params.get('tgt_name') %}
{% set tgt_name1 = params.get('tgt_name1') %}
{% set tgt_desc = params.get('tgt_desc') %}
{% set policy_name = params.get('policy_name') %}
{% set tgt_type = params.get('tgt_type') %}
{% set tgt_value = params.get('tgt_value') %}
{% set remediate = params.get('remediate') %}
{% set benchmark_names = params.get('benchmark_names') %}


Create Target {{ tgt_name }}:
  META:
    name: Create space
    parameters:
      tgt_name:
        description: Space name
        name: Space name
        uiElement: text
      tgt_desc:
        description: Space domain
        name: Space domain
        uiElement: text
      tgt_type:
        description: Runtime resources
        name: Runtime resources
        uiElement: multiselect
        options:
        - name: Auto provisioned data services
          value: dev-services
        - name: Pre-provisioned data services (Crossplane)
          value: crossplane
        - name: Pre-provisioned data services (Services toolkit)
          value: svc-toolkit
        - name: Deployments
          value: deployments
        - name: Api descriptors
          value: apidescriptors
      tgt_value:
        description: Traffic policy
        name: Network policy
        uiElement: select
        options:
        - name: Strict
          value: strict
        - name: Dynamic
          value: dynamic
        - name: Baseline
          value: baseline
  saltstack.target.present:
  - name: {{ tgt_name }}
  - desc: {{ tgt_desc }}
  - tgt_type: {{ tgt_type }}
  - tgt: {{tgt_value}}

Create Policy on target {{ policy_name }}:
  META:
   name: Configure space
   parameters:
     policy_name:
       description: Mapped k8s namespaces
       name: Mapped k8s namespaces
       uiElement: array
     tgt_name1:
       description: Placement strategy
       name: Placement strategy
       uiElement: select
       options:
       - name: Active-active
         value: active-active
       - name: Active-passive
         value: active-passive
     remediate:
       description: HA levels
       name: slas
       uiElement: multiselect
       options:
         - name: Cloud (Cloud providers failover)
           value: clouds
         - name: Datacenter (Avalability zones failover)
           value: datacenter
         - name: Cluster (cluster failover)
           value: cluster
         - name: Gateway (API gateways routes failover)
           value: gw
         - name: App (app instance failover)
     benchmark_names:
       description: Space config values
       name: Space config key-values
       uiElement: array
  saltstack.policy.present:
  - require:
    - saltstack.target: Create Target {{ tgt_name1 }}
  - name: {{ policy_name }}
  - tgt_name1: {{ tgt_name1 }}
  - remediate: {{ remediate }}
  - benchmark_names: {{ benchmark_names }}
