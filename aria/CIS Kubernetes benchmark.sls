META:
  name: Automation for Secure Clouds - CIS Kubernetes V1.23 Benchmark
  provider: SecureState
  category: SECURITY
  subcategory: Reference
  template_id: 3b.ss_cis_kubernetes.11
  version: v1
  description: Enables framework CIS Kubernetes V1.23 Benchmark and all of its rules. This framework is a compliance standard for securing Kubernetes resources. This template works with Secure State Paid version only.

{% set severity = 'All' %}

enable_cis_kubernetes_benchmark:
  META:
    name: Enable CIS Kubernetes V1.23 Benchmark
  securestate.framework.present:
  - name: CIS Kubernetes V1.23 Benchmark
  - id: '4e905288-8690-4319-ab08-a555e03d300a'
  - status: Enabled

enable_all_state_rule:
  META:
    name: Enable all rules for CIS Kubernetes V1.23 Benchmark
  exec.run:
    - require:
        - securestate.framework: enable_cis_kubernetes_benchmark
    - path: securestate.framework.get_rule_by_frameworkId
    - kwargs:
        id: '4e905288-8690-4319-ab08-a555e03d300a'
        status: Enabled
        filter:
            severity: {{ severity }}

#!require:enable_all_state_rule

{% for rule_id in hub.idem.arg_bind.resolve('${exec.run:enable_all_state_rule}')['results'] %}
{{rule_id}}:
  securestate.rule.present:
  - id: {{rule_id}}
  - status: Enabled
{% endfor %}
