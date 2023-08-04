META:
  name: App Runtime Profile (Space)
  provider: TMC
  category: CONFIG
  subcategory: Reference
  template_id: 6b.tmc.1
  version: v2
  description: App Runtime Profile (Space)

{% set app_runtime = params.get('app_runtime') %}
{% set languages = params.get('languages') %}
{% set service_catalog = params.get('service_catalog') %}
{% set pipeline = params.get('pipeline') %}
{% set deployment = params.get('deployment') %}

{% set workload_placement = params.get('workload_placement') %}
{% set resource_allocation = params.get('resource_allocation') %}
{% set ha_policy = params.get('ha_policy') %}
{% set data_compliance = params.get('data_compliance') %}
{% set service_binding = params.get('service_binding') %}

{% set k8_namespace = params.get('k8_namespace') %}
{% set advanced_key_value = params.get('advanced_key_value') %}


#space Capabilities
Profile Capabilities :
  META:
    name: Profile Capabilities 
    parameters:
      app_runtime:
        name: Runtime
        uiElement: select
        options:
        - name: Tanzu Cloud Native Runtime (kNative)
          value: knative
        - name: Tanzu App Service Runtime (Cloud Foundry)
          value: cf
        - name: Vanilla k8s provider
          value: k8s
        - name: BYO middleware (base image)
          value: byo
      languages:
        name: Builders
        uiElement: multiselect
        options:
        - name: Spring/Java
          value: spring
        - name: .NET Core
          value: dotnet
        - name: Node.JS
          value: node
        - name: GoLang
          value: go
        - name: Phyton
          value: phyton
        - name: BYO (docker file)
          value: docker
      pipeline:
        name: Pipelines
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
      service_catalog:
        name: Services
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
      deployment:
        name: Deployments
        uiElement: multiselect
        options:
        - name: Progressive delivery (blue/green)
          value: bluegreen
        - name: Autoscaling
          value: autoscaling
        - name: Brownfield APIs
          value: api
        - name: SLO metrics
          value: slo
        - name: Log aggregation and exfiltration
          value: logs
  tmc.cluster_groups.present:
    - app_runtime: {{app_runtime}}
    - languages: {{languages}}
    - service_catalog: {{service_catalog}}
    - pipeline: {{pipeline}}
    - deployment: {{deployment}}

#policies
Profile Policies:
  META:
    name: Profile Policies
    parameters:
      workload_placement:
        name: Workloads Placement and distribution
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
      resource_allocation:
          name: CPU and memory resource allocation
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
      ha_policy:
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
      data_compliance:
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
      service_binding:
        name: Service binding 
        uiElement: select
        options:
        - name: Provision and bind
          value: provision_bind
        - name: Bind only
          value: bind
  tmc.cluster_groups.present:
    - workload_placement: {{workload_placement}}
    - resource_allocation: {{resource_allocation}}
    - ha_policy: {{ha_policy}}
    - data_compliance: {{data_compliance}}
    - service_binding: {{service_binding}}
    
#advanced
Advanced Configurations {{advanced_key_value}}:
  META:
    name: Advanced Configurations
    parameters:
      k8_namespace:
        name: Mapped k8s namespaces
        uiElement: array
      advanced_key_value:
        name: Space config key-values
        uiElement: array
  tmc.cluster_groups.present:
    - k8_namespace: {{k8_namespace}}
    - advanced_key_value: {{advanced_key_value}}