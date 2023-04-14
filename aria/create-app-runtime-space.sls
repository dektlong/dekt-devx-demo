META:
  name: Create App runtimes_components space 
  provider: SaltStack
  category: SECURITY
  subcategory: Reference
  template_id: 3b.ssc.11
  version: v1
  description: Create App runtimes_components space

{% set space_name = params.get('space_name') %}
{% set data_svc_provisioning = params.get('data_svc_provisioning') %}
{% set data_complainces = params.get('data_complainces') %}
{% set space_domain = params.get('space_domain') %}
{% set k8s_ns = params.get('k8s_ns') %}
{% set runtimes_components = params.get('runtimes_components') %}
{% set workloads = params.get('workloads') %}
{% set ha_levels = params.get('ha_levels') %}
{% set space_config_values = params.get('space_config_values') %}


Create Target {{ space_name }}:
  META:
    name: Create space
    parameters:
      space_name:
        description: Space name
        name: Space name
        uiElement: text
      space_domain:
        description: Space domain
        name: Space domain
        uiElement: text
      runtimes_components:
        description: Runtime Components
        name: Runtime Components
        uiElement: multiselect
        options:
        - name: On-cluster services
          value: dev-services
        - name: AWS services
          value: aws
        - name: Azure services
          value: azure
        - name: Google services
          value: google
        - name: Private services 
          value: private
        - name: External APIs
          value: externalapis
        - name: Scanners policies
          value: scanners
        - name: Image build strategies
          value: builds
        - name: Sensitive cluster operations
          value: sensitive
      workloads:
        description: Workloads placement
        name: Workloads placement
        uiElement: select
        options:
        - name: Best effort
          value: besteffort
        - name: SLA driven
          value: sla
        - name: Strict
          value: strict

  saltstack.target.present:
  - name: {{ workloads }}
  - desc: {{ space_domain }}
  - runtimes_components: {{ runtimes_components }}
  - tgt: {{space_name}}

Create Policy on target {{ ha_levels }}:
  META:
   name: Configure space
   parameters:
     ha_levels:
       description: High-Availability levels
       name: High-Availability levels
       uiElement: multiselect
       options:
       - name: Clouds
         value: clouds
       - name: Avalability zones
         value: datacenter
       - name: Clusters
         value: cluster
       - name: API Gateway routes
         value: gw
       - name: App instances
         value: app
     data_complainces:
       description: Data Compliances
       name: Data Compliances
       uiElement: multiselect
       options:
       - name: Baseline
         value: baseline
       - name: GDPR
         value: GDPR
       - name: HIPAA
         value: HIPAA
       - name: PCI DSS
         value: pci
       - name: CCPA
         value: CCPA
     data_svc_provisioning:
       description: Service binding 
       name: Service binding 
       uiElement: select
       options:
       - name: Provision and bind
         value: provision_bind
       - name: Bind only
         value: bind
     k8s_ns:
       description: Mapped k8s namespaces
       name: Mapped k8s namespaces
       uiElement: array
     space_config_values:
       description: Space config values
       name: Space config key-values
       uiElement: array
  saltstack.policy.present:
  - require:
    - saltstack.target: Create Target {{ data_svc_provisioning }}
  - name: {{ ha_levels }}
  - data_svc_provisioning: {{ data_svc_provisioning }}
  - data_complainces: {{ data_complainces }}
  - k8s_ns: {{ k8s_ns }}
  - space_config_values: {{ space_config_values }}
