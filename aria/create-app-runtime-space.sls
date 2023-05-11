META:
  name: Create App Runtime Space
  category: SECURITY
  subcategory: Reference
  template_id: 3b.ssc.11
  version: v1

{% set param1= params.get('param1') %}
{% set param2= params.get('param2') %}
{% set param3= params.get('param3') %}
{% set param4= params.get('param4') %}
{% set param5= params.get('param5') %}
{% set param6= params.get('param6') %}
{% set param7= params.get('param7') %}
{% set param8= params.get('param8') %}
{% set param9= params.get('param9') %}
{% set param10= params.get('param10') %}
{% set param11= params.get('param11') %}
{% set param12= params.get('param12') %}

Delivery {{ param1 }}:
  META:
    name: Delivery Definitions
    parameters:
      param1:
        name: Runtime Environment Name
        uiElement: text
      param2:
        name: Pipeline Requirements
        uiElement: multiselect
        options:
        - name: Functional Testing 
          value: testing
        - name: Source Scanning 
          value: src_scan
        - name: Image Scanning 
          value: img_scan
        - name: Open API Validation 
          value: api_validation
        - name:  Enforce Pod Convensions  
          value: conv
        - name:  Manual deployment approval
          value: manual_deployment
      param3:
        name: Target Runtime
        uiElement: select
        options:
        - name: Tanzu Cloud Native Runtime (kNative)
          value: knative
        - name: Vanilla k8s provider
          value: k8s
        - name: BYO middleware (base image)
          value: byo
          
  saltstack.target.present:
  - param1: {{ param1 }}
  - param2: {{ param2 }}
  - param3: {{ param3 }}

Policies  {{ param4 }}:
  META:
    name: Operational Policies
    parameters:
      param4:
        name: Workloads Placement
        uiElement: select
        options:
        - name: Best effort
          value: besteffort
        - name: Performance driven
          value: sla
        - name: Cost driven
          value: cost
        - name: Strict
          value: strict
      param5:
        name: Load Management
        uiElement: multiselect
        options:
        - name: Auto Scaling
          value: auto_scale
        - name: Scale to Zero
          value: scale_zero
        - name: Fixed instances
          value: fixed
      param6:
        name: High Availability
        uiElement: multiselect
        options:
        - name: Cloud Regions
          value: clouds
        - name: Avalability zones
          value: datacenter
        - name: Clusters
          value: cluster
        - name: App instances
          value: app
      param7:
        name: Deployment Strategy
        uiElement: select
        options:
        - name: Rolling 
          value: rolling
        - name: Blue-Green
          value: blue_green
        - name: Canary
          value: canary
      param8:
        name: Data Compliance
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
  saltstack.policy.present:
  - param4: {{ param4 }}
  - param5: {{ param5 }}
  - param6: {{ param6 }}
  - param7: {{ param7 }}
  - param8: {{ param7 }}
  
App Services {{ param9 }}:
  META:
    name: App Services
    parameters:
      param9:
        name: Available Catalogs
        uiElement: multiselect
        options:
        - name: AWS curate marketplace
          value: aws
        - name: Azure curate marketplace
          value: azure
        - name: GCP curate marketplace
          value: gcp
        - name: Tanzu App Catalog (bitnami)
          value: bitnami
        - name: Helm charts
          value: helm
      param10:
       name: Service binding 
       uiElement: select
       options:
       - name: Provision and bind
         value: provision_bind
       - name: Bind only
         value: bind
  saltstack.policy.present:
  - param9: {{ param9 }}
  - param10: {{ param10 }}

Advanced Configurations {{ param11 }}:
  META:
    name: Advanced Configurations
    parameters:
      param11:
        name: Mapped k8s namespaces
        uiElement: array
      param12:
        name: Space config key-values
        uiElement: array
  saltstack.policy.present:
  - param11: {{ param11 }}
  - param12: {{ param12 }}