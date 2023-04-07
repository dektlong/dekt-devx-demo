META:
  name: Automation for Secure Clouds - CIS AWS foundation Benchmark 1.5.0
  provider: SecureState
  category: SECURITY
  subcategory: Reference
  template_id: 3b.ss_cis_aws.33
  version: v1
  description: Center for Internet Security AWS Foundations Security Benchmark 1.5.0 is a compliance standard for securing Amazon Web Services resources. This template will enable framework and all rules for CIS AWS foundation Benchmark 1.5.0

{% set severity = 'All' %}

enable_cis_aws_framework_benchmark:
  META:
    name: Enable CIS AWS foundation Benchmark 1.5.0
  securestate.framework.present:
  - name: CIS AWS foundation Benchmark 1.5.0
  - id: '91987e9a-86e8-4071-a748-595f1e313237'
  - status: Enabled

enable_all_state_rule:
  META:
    name: Enable all rules for CIS AWS foundation Benchmark 1.5.0
  exec.run:
    - require:
        - securestate.framework: enable_cis_aws_framework_benchmark
    - path: securestate.framework.get_rule_by_frameworkId
    - kwargs:
        id: '91987e9a-86e8-4071-a748-595f1e313237'
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
