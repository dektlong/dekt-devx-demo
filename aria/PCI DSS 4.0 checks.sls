META:
  name: Automation for Secure Clouds - PCI DSS 4.0
  provider: SecureState
  category: SECURITY
  subcategory: Reference
  template_id: 3b.ss_pci_dss.11
  version: v1
  description: This template will enable PCI DSS 4.0 framework and all of its rules. This template works with Secure State Paid version only.

{% set severity = 'All' %}

enable_cis_pci_dss:
  META:
    name: Enable PCI DSS 4.0
  securestate.framework.present:
  - name: PCI DSS 4.0
  - id: 'a68daabd-4c88-4da8-a726-f55de82f681b'
  - status: Enabled

enable_all_state_rule:
  META:
    name: Enable all rules for PCI DSS 4.0
  exec.run:
    - require:
        - securestate.framework: enable_cis_pci_dss
    - path: securestate.framework.get_rule_by_frameworkId
    - kwargs:
        id: 'a68daabd-4c88-4da8-a726-f55de82f681b'
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
