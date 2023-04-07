META:
  name: Install TAP on AKS
  provider: SaltStack
  category: SECURITY
  subcategory: Reference
  template_id: 3b.ssc.11
  version: v1
  description: Install TAP on AKS

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
    name: Install TAP
    parameters:
      tgt_name:
        description: Name of TAP cluster
        name: Cluster name
        uiElement: text
      tgt_desc:
        description: AKS nodes
        name: AKS nodes
        uiElement: text
      tgt_type:
        description: AKS region
        name: AKS region
        uiElement: select
        options:
        - name: US West
          value: westus
        - name: UK
          value: ukwest
        - name: Europe
          value: eu-central-1
        - name: South east asia
          value: ap-southeast1 
      tgt_value:
        description: TAP profile
        name: TAP profile
        uiElement: select
        options:
        - name: iterate
          value: iterate
        - name: build
          value: build
        - name: run
          value: run
        - name: full
          value: full
        - name: view
          value: view
  saltstack.target.present:
  - name: {{ tgt_name }}
  - desc: {{ tgt_desc }}
  - tgt_type: {{ tgt_type }}
  - tgt: {{tgt_value}}

Create Policy on target {{ policy_name }}:
  META:
   name: Configure TAP
   parameters:
     policy_name:
       description: Deployment domain
       name: Deployment domain
       uiElement: text
     tgt_name1:
       description: Installed scanners
       name: Installed scanners
       uiElement: multiselect
       options:
         - name: Aqua
           value: Aqua
         - name: Carbon black
           value: carbonblack
         - name: Grype
           value: grype
         - name: Snyk
           value: snyk
     remediate:
       description: Data-services connector
       name: Data-services connector
       uiElement: multiselect
       options:
         - name: Crossplane
           value: crossplane
         - name: Services Toolkit
           value: svc-toolkit
         - name: K8s secrets
           value: k8s-secret
     benchmark_names:
       description: TAP install values
       name: TAP install values
       uiElement: array
  saltstack.policy.present:
  - require:
    - saltstack.target: Create Target {{ tgt_name1 }}
  - name: {{ policy_name }}
  - tgt_name1: {{ tgt_name1 }}
  - remediate: {{ remediate }}
  - benchmark_names: {{ benchmark_names }}