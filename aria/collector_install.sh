#!/bin/bash

# BSD 2-Clause License
# 
# Copyright (c) 2009-present, Homebrew contributors
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
# * Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
# 
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# Usage
#
# export VMW_CLUSTER_NAME=my-cluster
# export VMW_CLUSTER_CLOUD_ACCOUNT_ID=1234
# export VMW_CLUSTER_REGION=us-west-2
# export VMW_ACCESS_KEY=abcd
# export VMW_COLLECTOR_ID=5678
# export VMW_COLLECTOR_CLIENT_SECRET=efgh
# export VMW_ORG_ID=9012
# export VMW_CLIENT_ID=3456
# export VMW_ENVIRONMENT=prod
# export VMW_CLUSTER_CLOUD_PROVIDER=AWS
# /bin/bash -c "$(curl -fsSL https://mgmt.vmware.com/aria/k8s-collector/install.sh)"

set -u

abort() {
  printf "%s\n" "$@" >&2
  exit 1
}

# string formatters
if [[ -t 1 ]]
then
  tty_escape() { printf "\033[%sm" "$1"; }
else
  tty_escape() { :; }
fi
tty_mkbold() { tty_escape "1;$1"; }
tty_underline="$(tty_escape "4;39")"
tty_blue="$(tty_mkbold 34)"
tty_red="$(tty_mkbold 31)"
tty_bold="$(tty_mkbold 39)"
tty_reset="$(tty_escape 0)"

shell_join() {
  local arg
  printf "%s" "$1"
  shift
  for arg in "$@"
  do
    printf " "
    printf "%s" "${arg// /\ }"
  done
}

chomp() {
  printf "%s" "${1/"$'\n'"/}"
}

ohai() {
  printf "${tty_blue}==>${tty_bold} %s${tty_reset}\n" "$(shell_join "$@")"
}

warn() {
  printf "${tty_red}Warning${tty_reset}: %s\n" "$(chomp "$1")"
}

# Values you should not change.
#
# These are being written as configurable in case we *are* able to modify them in the futuer
## Need to know this value to send otel metrics correctly
ARIA_DEFAULT_NAMESPACE="aria-k8s"

## Pixie expects this to be its namespace
PIXIE_DEFAULT_NAMESPACE="pl"

## Label of pre-Helm Aria K8s Collector. Used for removing pre-helm resources during an upgrade.
OLD_ARIA_K8S_LABEL="aria-k8s"

## Switch which indicates whether we are upgrading from a non-helm install
LEGACY_YAML_DEPLOY=0

## Switch which indicates whether a legacy secret was found that should be reused
LEGACY_YAML_SECRET=0

## Switch indicating whether chart upgrades should happen
VMW_UPGRADE=0

## Switch indicating whether chart installs should happen
VMW_INSTALL=0

# Are we running on linux?
RUNNING_ON_LINUX=0

# Are we running on MacOS?
RUNNING_ON_MACOS=0

# Whether we should attempt to download 'yq' if it doesn't exist on the system
SHOULD_DOWNLOAD_YQ=1

# For storing values.yaml files we create for helm.
VALUES_TMP_DIR="$(mktemp -d)"
export TMPDIR="${VALUES_TMP_DIR}"

# For being able to "detect" yq if its downloaded
export PATH="${PATH}:${TMPDIR}"

# Optional values
K8S_COLLECTOR_DEFAULT_HELM_REPO="oci://projects.registry.vmware.com/adie/helm-charts/k8s-collector"
PIXIE_DEFAULT_HELM_REPO="https://pixie-operator-charts.storage.googleapis.com"
TELEGRAF_DEFAULT_HELM_REPO="oci://projects.registry.vmware.com/adie/helm-charts/telegraf-collector"
VMW_DEFAULT_CLOUD_ADDR="pixie.adie.securestate.vmware.com:443"
VMW_DEFAULT_CLUSTER_CLOUD_PROVIDER="AWS"
VMW_DEFAULT_DEPLOY_KEY="px-dep-85158508-c7f1-4f7e-b8ee-3eda111e554d"
VMW_DEFAULT_ENVIRONMENT="prod"
VMW_DEFAULT_NETWORK_MAP_METRICS_COLLECT_INTERVAL_SECONDS="30s"
VMW_DEFAULT_NETWORK_MAP_METRICS_ENDPOINT="http://aria-telegraf-collector.aria-k8s:9273/metrics"
VMW_DEFAULT_DEBUG=0
VMW_DEFAULT_HELM_WAIT=1
VMW_DEFAULT_CSP_HOST="https://console.cloud.vmware.com"
VMW_DEFAULT_METRICS_DOMAIN="aria-k8s-prod-us-2"
VMW_DEFAULT_HTTP_INGESTION_URL="https://data.mgmt.cloud.vmware.com/le-mans/v1/streams/tss-proto"
VMW_DEFAULT_USE_ETCD_OPERATOR="false"
VMW_DEFAULT_METRICS_STORAGE_POLICY="aria-k8s"
VMW_DEFAULT_NODE_LIMIT=0
VMW_DEFAULT_DEPLOY_OLM="true"
VMW_DEFAULT_CLEANUP_OLD_RESOURCES=1
VMW_DEFAULT_CLIENT_ID=""
VMW_DEFAULT_COLLECTOR_CLIENT_SECRET=""
VMW_DEFAULT_CLUSTER_MANAGED="false"
VMW_DEFAULT_PEM_MEMORY_LIMIT="2Gi"
VMW_DEFAULT_DRY_RUN=0
VMW_DEFAULT_TRACE_ENTITY_ID=0
VMW_DEFAULT_TRACE_METRIC=0
VMW_DEFAULT_ACCESS_KEY=""
VMW_DEFAULT_CLUSTER_CLOUD_ACCOUNT_ID=""
VMW_DEFAULT_CLUSTER_REGION=""
VMW_DEFAULT_CLUSTER_NAME=""
VMW_DEFAULT_COLLECTOR_ID=""
VMW_DEFAULT_ORG_ID=""

# Version
#
# This is the version that the collector reports back to Aria.
#
# When the collector gained additional add-on functionality, it was no longer reasonable to consider the k8s-collector
# container image itself to be the version-source-of-truth due to the extra moving pieces. This variable was added to
# allow the version reported by the k8s-collector heartbeat back to Aria to be overridden to support the (now) higher
# level version.
#
# You can think of this version as the version of the product if it were represented as an Umbrella Chart in Helm.
#
# If you are updating any of the moving parts of this product, this version here should *always* be semantically updated
# to indicate new-ness or "latest" to the customer.
VMW_COLLECTOR_VERSION_OVERRIDE="2.4.6"

# Chart versions
TELEGRAF_CHART_DEFAULT_VERSION="${VMW_COLLECTOR_VERSION_OVERRIDE}"
K8S_COLLECTOR_CHART_DEFAULT_VERSION="${VMW_COLLECTOR_VERSION_OVERRIDE}"
PIXIE_CHART_DEFAULT_VERSION="0.0.38"

# Override used values with defaults if necessary
ARIA_NAMESPACE="${ARIA_NAMESPACE:-"${ARIA_DEFAULT_NAMESPACE}"}"
K8S_COLLECTOR_HELM_REPO="${K8S_COLLECTOR_HELM_REPO:-"${K8S_COLLECTOR_DEFAULT_HELM_REPO}"}"
PIXIE_HELM_REPO="${PIXIE_HELM_REPO:-"${PIXIE_DEFAULT_HELM_REPO}"}"
PIXIE_NAMESPACE="${PIXIE_NAMESPACE:-"${PIXIE_DEFAULT_NAMESPACE}"}"
TELEGRAF_HELM_REPO="${TELEGRAF_HELM_REPO:-"${TELEGRAF_DEFAULT_HELM_REPO}"}"
VMW_CLOUD_ADDR="${VMW_CLOUD_ADDR:-"${VMW_DEFAULT_CLOUD_ADDR}"}"
VMW_CLUSTER_CLOUD_PROVIDER="${VMW_CLUSTER_CLOUD_PROVIDER:-"${VMW_DEFAULT_CLUSTER_CLOUD_PROVIDER}"}"
VMW_DEPLOY_KEY="${VMW_DEPLOY_KEY:-"${VMW_DEFAULT_DEPLOY_KEY}"}"
VMW_ENVIRONMENT="${VMW_ENVIRONMENT:-"${VMW_DEFAULT_ENVIRONMENT}"}"
VMW_NETWORK_MAP_METRICS_COLLECT_INTERVAL_SECONDS="${VMW_NETWORK_MAP_METRICS_COLLECT_INTERVAL_SECONDS:-"${VMW_DEFAULT_NETWORK_MAP_METRICS_COLLECT_INTERVAL_SECONDS}"}"
VMW_NETWORK_MAP_METRICS_ENDPOINT="${VMW_NETWORK_MAP_METRICS_ENDPOINT:-"${VMW_DEFAULT_NETWORK_MAP_METRICS_ENDPOINT}"}"
TELEGRAF_CHART_VERSION="${TELEGRAF_CHART_VERSION:-"${TELEGRAF_CHART_DEFAULT_VERSION}"}"
K8S_COLLECTOR_CHART_VERSION="${K8S_COLLECTOR_CHART_VERSION:-"${K8S_COLLECTOR_CHART_DEFAULT_VERSION}"}"
PIXIE_CHART_VERSION="${PIXIE_CHART_VERSION:-"${PIXIE_CHART_DEFAULT_VERSION}"}"
VMW_DEBUG="${VMW_DEBUG:-"${VMW_DEFAULT_DEBUG}"}"
VMW_HELM_WAIT="${VMW_HELM_WAIT:-"${VMW_DEFAULT_HELM_WAIT}"}"
VMW_CSP_HOST="${VMW_CSP_HOST:-"${VMW_DEFAULT_CSP_HOST}"}"
VMW_METRICS_DOMAIN="${VMW_METRICS_DOMAIN:-"${VMW_DEFAULT_METRICS_DOMAIN}"}"
VMW_HTTP_INGESTION_URL="${VMW_HTTP_INGESTION_URL:-"${VMW_DEFAULT_HTTP_INGESTION_URL}"}"
VMW_USE_ETCD_OPERATOR="${VMW_USE_ETCD_OPERATOR:-"${VMW_DEFAULT_USE_ETCD_OPERATOR}"}"
VMW_METRICS_STORAGE_POLICY="${VMW_METRICS_STORAGE_POLICY:-"${VMW_DEFAULT_METRICS_STORAGE_POLICY}"}"
VMW_NODE_LIMIT="${VMW_NODE_LIMIT:-"${VMW_DEFAULT_NODE_LIMIT}"}"
VMW_DEPLOY_OLM="${VMW_DEPLOY_OLM:-"${VMW_DEFAULT_DEPLOY_OLM}"}"
VMW_CLEANUP_OLD_RESOURCES="${VMW_CLEANUP_OLD_RESOURCES:-"${VMW_DEFAULT_CLEANUP_OLD_RESOURCES}"}"
VMW_CLIENT_ID="${VMW_CLIENT_ID:-"${VMW_DEFAULT_CLIENT_ID}"}"
VMW_COLLECTOR_CLIENT_SECRET="${VMW_COLLECTOR_CLIENT_SECRET:-"${VMW_DEFAULT_COLLECTOR_CLIENT_SECRET}"}"
VMW_CLUSTER_MANAGED="${VMW_CLUSTER_MANAGED:-"${VMW_DEFAULT_CLUSTER_MANAGED}"}"
VMW_PEM_MEMORY_LIMIT="${VMW_PEM_MEMORY_LIMIT:-"${VMW_DEFAULT_PEM_MEMORY_LIMIT}"}"
VMW_DRY_RUN="${VMW_DRY_RUN:-"${VMW_DEFAULT_DRY_RUN}"}"
VMW_TRACE_ENTITY_ID="${VMW_TRACE_ENTITY_ID:-"${VMW_DEFAULT_TRACE_ENTITY_ID}"}"
VMW_TRACE_METRIC="${VMW_TRACE_METRIC:-"${VMW_DEFAULT_TRACE_METRIC}"}"
VMW_ACCESS_KEY="${VMW_ACCESS_KEY:-"${VMW_DEFAULT_ACCESS_KEY}"}"
VMW_CLUSTER_CLOUD_ACCOUNT_ID="${CLUSTER_CLOUD_ACCOUNT_ID:-"${VMW_DEFAULT_CLUSTER_CLOUD_ACCOUNT_ID}"}"
VMW_CLUSTER_NAME="${VMW_CLUSTER_NAME:-"${VMW_DEFAULT_CLUSTER_NAME}"}"
VMW_CLUSTER_REGION="${VMW_CLUSTER_REGION:-"${VMW_DEFAULT_CLUSTER_REGION}"}"
VMW_COLLECTOR_ID="${VMW_COLLECTOR_ID:-"${VMW_DEFAULT_COLLECTOR_ID}"}"
VMW_ORG_ID="${VMW_ORG_ID:-"${VMW_DEFAULT_ORG_ID}"}"

# Prefer later Helm version (with oci:// support)
REQUIRED_HELM_VERSION=3.9.0
REQUIRED_KUBECTL_VERSION=1.20.0
REQUIRED_YQ_VERSION=4.33.3

parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --collector-id)
        VMW_COLLECTOR_ID="$2"
        shift # past argument
        shift # past value
        ;;
      --cluster-name)
        VMW_CLUSTER_NAME="$2"
        shift # past argument
        shift # past value
        ;;
      --cluster-cloud-account-id)
        VMW_CLUSTER_CLOUD_ACCOUNT_ID="$2"
        shift # past argument
        shift # past value
        ;;
      --cluster-cloud-provider)
        VMW_CLUSTER_CLOUD_PROVIDER="$2"
        shift # past argument
        shift # past value
        ;;
      --cluster-region)
        VMW_CLUSTER_REGION="$2"
        shift # past argument
        shift # past value
        ;;
      --cluster-managed)
        VMW_CLUSTER_MANAGED="true"
        shift # past argument
        ;;
      --environment)
        VMW_ENVIRONMENT="$2"
        shift # past argument
        shift # past value
        ;;
      --collector-client-secret)
        VMW_COLLECTOR_CLIENT_SECRET="$2"
        shift # past argument
        shift # past value
        ;;
      --org-id)
        VMW_ORG_ID="$2"
        shift # past argument
        shift # past value
        ;;
      --client-id)
        VMW_CLIENT_ID="$2"
        shift # past argument
        shift # past value
        ;;
      --access-key)
        VMW_ACCESS_KEY="$2"
        shift # past argument
        shift # past value
        ;;
      --telegraf-chart-version)
        TELEGRAF_CHART_VERSION="$2"
        shift # past argument
        shift # past value
        ;;
      --k8s-collector-chart-version)
        K8S_COLLECTOR_CHART_VERSION="$2"
        shift # past argument
        shift # past value
        ;;
      --pixie-chart-version)
        PIXIE_CHART_VERSION="$2"
        shift # past argument
        shift # past value
        ;;
      --cloud-addr)
        VMW_CLOUD_ADDR="$2"
        shift # past argument
        shift # past value
        ;;
      --pem-memory-limit)
        VMW_PEM_MEMORY_LIMIT="$2"
        shift # past argument
        shift # past value
        ;;
      --csp-host)
        VMW_CSP_HOST="$2"
        shift # past argument
        shift # past value
        ;;
      --metrics-domain)
        VMW_METRICS_DOMAIN="$2"
        shift # past argument
        shift # past value
        ;;
      --metrics-storage-policy)
        VMW_METRICS_STORAGE_POLICY="$2"
        shift # past argument
        shift # past value
        ;;
      --namespace)
        ARIA_NAMESPACE="$2"
        shift # past argument
        shift # past value
        ;;
      --http-ingestion-url)
        VMW_HTTP_INGESTION_URL="$2"
        shift # past argument
        shift # past value
        ;;
      --node-limit)
        VMW_NODE_LIMIT="$2"
        shift # past argument
        shift # past value
        ;;
      --debug)
        VMW_DEBUG=1
        shift # past argument
        ;;
      --no-cleanup-old-resources)
        VMW_CLEANUP_OLD_RESOURCES=0
        shift # past argument
        ;;
      --no-deploy-olm)
        VMW_DEPLOY_OLM="false"
        shift # past argument
        ;;
      --dry-run)
        VMW_DRY_RUN=1
        shift # past argument
        ;;
      --trace-entity-id)
        VMW_TRACE_ENTITY_ID=1
        shift # past argument
        ;;
      --trace-metric)
        VMW_TRACE_METRIC=1
        shift # past argument
        ;;
      --no-wait)
        VMW_HELM_WAIT=0
        shift # past argument
        ;;
      --use-etcd-operator)
        VMW_USE_ETCD_OPERATOR="true"
        shift # past argument
        ;;
      *)
        shift # past argument
        ;;
    esac
  done
}

check_global_required_args() {
  # Single brackets are needed here for POSIX compatibility
  # shellcheck disable=SC2292
  if [ -z "${VMW_CLUSTER_NAME:-}" ]; then
    abort "Cluster Name is required to interpret this script."
  fi

  if [ -z "${VMW_CLUSTER_CLOUD_ACCOUNT_ID:-}" ]; then
    abort "Cluster Cloud Account ID is required to interpret this script."
  fi

  if [ -z "${VMW_CLUSTER_REGION:-}" ]; then
    abort "Cluster Region is required to interpret this script."
  fi

  if [ -z "${VMW_COLLECTOR_ID:-}" ]; then
    abort "Collector ID is required to interpret this script."
  fi

  if [ -z "${VMW_ORG_ID:-}" ]; then
    abort "CSP Org ID is required to interpret this script."
  fi
}

getc() {
  local save_state
  save_state="$(/bin/stty -g)"
  /bin/stty raw -echo
  IFS='' read -r -n 1 -d '' "$@"
  /bin/stty "${save_state}"
}

ring_bell() {
  # Use the shell's audible bell.
  if [[ -t 1 ]]
  then
    printf "\a"
  fi
}

wait_for_user() {
  local c
  echo
  echo "Press ${tty_bold}RETURN${tty_reset}/${tty_bold}ENTER${tty_reset} to continue or any other key to abort:"
  getc c
  # we test for \r and \n because some stuff does \r instead
  if ! [[ "${c}" == $'\r' || "${c}" == $'\n' ]]
  then
    exit 1
  fi
}

set_detected_os() {
  # First check OS.
  OS="$(uname)"
  if [[ "${OS}" == "Linux" ]]
  then
    RUNNING_ON_LINUX=1
  elif [[ "${OS}" == "Darwin" ]]
  then
    # shellcheck disable=SC2034
    RUNNING_ON_MACOS=1
  else
    abort "Script is only supported on macOS and Linux."
  fi
}
check_legacy_yaml_deploy() {
  local kubectl_get_output
  kubectl_get_output="$("$USABLE_KUBECTL" get po --namespace "${ARIA_NAMESPACE}" -l app=aria-k8s 2> /dev/null | grep -cv NAME 2> /dev/null || true)"
  if [ "${kubectl_get_output}" = "1" ]; then
    LEGACY_YAML_DEPLOY=1
  fi
}

check_legacy_secret() {
  local kubectl_get_output
  kubectl_get_output="$("$USABLE_KUBECTL" get secret collector-client-secret --namespace "${ARIA_NAMESPACE}" 2> /dev/null | grep -cv NAME 2> /dev/null || true)"
  if [ "${kubectl_get_output}" = "1" ]; then
    LEGACY_YAML_SECRET=1
  fi
}

read_client_secret() {
  if [ "$VMW_COLLECTOR_CLIENT_SECRET" ]; then
    # The user provided the client secret to us.
    # This overrides re-using the one in legacy YAML
    return 1
  fi

  local kubectl_get_output
  kubectl_get_output="$("$USABLE_KUBECTL" get secret --namespace "${ARIA_NAMESPACE}" collector-client-secret -o=jsonpath='{.data.COLLECTOR_CLIENT_SECRET}' 2> /dev/null)"
  if [[ -z "${kubectl_get_output}" ]]; then
    return 1
  fi
  ohai "Re-using Collector Client Secret from legacy YAML deployment"
  VMW_COLLECTOR_CLIENT_SECRET="$(echo "${kubectl_get_output}" | base64 -d)"
}

read_client_id() {
  if [ "$VMW_CLIENT_ID" ]; then
    # The user provided the client secret to us.
    # This overrides re-using the one in legacy YAML
    return 1
  fi

  local kubectl_get_output
  kubectl_get_output="$("$USABLE_KUBECTL" get deploy --namespace "${ARIA_NAMESPACE}" aria-k8s -o=jsonpath='{.spec.template.spec.containers[*].env[?(@.name == "CLIENT_ID")].value}' 2> /dev/null || true)"
  if [[ -z "${kubectl_get_output}" ]]; then
    return 1
  fi
  ohai "Re-using Collector Client ID from legacy YAML deployment"
  VMW_CLIENT_ID="${kubectl_get_output}"
}

major_minor() {
  echo "${1%%.*}.$(
    x="${1#*.}"
    echo "${x%%.*}"
  )"
}

version_ge() {
  [[ "$1" == "$(echo -e "$1\n$2" | sort -V | tail -n1)" ]]
}

version_lt() {
  [[ "$1" != "$(echo -e "$1\n$2" | sort -V | tail -n1)" ]]
}

charts_need_upgrade() {
  if chart_needs_upgrade "aria-k8s-collector" "${ARIA_NAMESPACE}" "${K8S_COLLECTOR_CHART_VERSION}" -eq 0; then
    VMW_UPGRADE=1
  fi
  if chart_needs_upgrade "aria-telegraf-collector" "${ARIA_NAMESPACE}" "${TELEGRAF_CHART_VERSION}" -eq 0; then
    VMW_UPGRADE=1
  fi
  if chart_needs_upgrade "pixie" "pl" "${PIXIE_CHART_DEFAULT_VERSION}" -eq 0; then
    VMW_UPGRADE=1
  fi
}

charts_need_install() {
  chart_needs_install "aria-k8s-collector" "${ARIA_NAMESPACE}"
  chart_needs_install "aria-telegraf-collector" "${ARIA_NAMESPACE}"
  chart_needs_install "pixie" "pl"
}

chart_needs_upgrade() {
  # Check if a given chart, in a given namespace is running a version less than a given version
  #
  # Returns: 1 if params are not provided or if upgrade is needed. 0 otherwise.

  # The chart name
  if [[ -z "$1" ]]; then
    return 1
  fi

  # The chart namespace
  if [[ -z "$2" ]]; then
    return 1
  fi

  # The version to check for
  if [[ -z "$3" ]]; then
    return 1
  fi

  local app_version_output

  # Look for the App version because we keep these unified across the charts that we distribute with this script.
  # The app version serves as an umbrella chart version.
  app_version_output="$("$USABLE_HELM" list --namespace "${2}" --no-headers --filter ^"${1}"$ 2> /dev/null | awk '{print $10}')"

  # example format
  # aria-k8s-collector	aria-k8s	4	2023-02-27 11:06:43.966945 -0800 PST	deployed	k8s-collector-1.12.0	1.0.0
  version_lt "$(major_minor "${app_version_output}")" "$(major_minor "${3}")"
}

chart_needs_install() {
  # Check if a given chart, in a given namespace exists
  #
  # Returns: 1 if params are not provided or if install is needed. 0 otherwise.

  # The chart name
  if [[ -z "$1" ]]; then
    return 1
  fi

  # The chart namespace
  if [[ -z "$2" ]]; then
    return 1
  fi

  # Look for the App version because we keep these unified across the charts that we distribute with this script.
  # The app version serves as an umbrella chart version.
  (${USABLE_HELM} status --namespace "${2}" "$1") > /dev/null 2>&1
  if [ $? -eq 1 ]; then
    VMW_INSTALL=1
  fi
}

test_helm() {
  if [[ ! -x "$1" ]]; then
    return 1
  fi

  local helm_version_output helm_name_and_version
  helm_version_output="$("$1" version 2>/dev/null)"

  # example format
  # version.BuildInfo{Version:"v3.11.1", GitCommit:"293b50c65d4d56187cd4e2f390f0ada46b4c4737", GitTreeState:"clean"...}
  helm_name_and_version=${helm_version_output%\", GitCommit:*}  # retain the part before the version end-quote
  helm_name_and_version=${helm_name_and_version##*Version:\"v}  # retain the part after the "v"
  # ex. compare 3.11.1 to 3.9.0
  version_ge "$(major_minor "${helm_name_and_version##* }")" "$(major_minor "${REQUIRED_HELM_VERSION}")"
}

test_kubectl() {
  if [[ ! -x "$1" ]]; then
    return 1
  fi

  local kubectl_version_output kubectl_name_and_version
  kubectl_version_output="$("$1" version --client 2>/dev/null)"

  # example format
  # version.BuildInfo{Version:"v1.25.9", GitCommit:"a1a87a0a2bcd605820920c6b0e618a8ab7d117d4", GitTreeState:"clean"...}
  kubectl_name_and_version=${kubectl_version_output%\", GitCommit:*}  # retain the part before the version end-quote
  kubectl_name_and_version=${kubectl_name_and_version##*Version:\"v}  # retain the part after the "v"
  # ex. compare 1.25.9 to 1.20.0
  version_ge "$(major_minor "${kubectl_name_and_version##* }")" "$(major_minor "${REQUIRED_KUBECTL_VERSION}")"
}

test_yq() {
  if [[ ! -x "$1" ]]; then
    return 1
  fi

  local yq_version_output yq_name_and_version
  yq_version_output="$("$1" --version 2>/dev/null)"

  # example format
  # yq (https://github.com/mikefarah/yq/) version v4.34.1
  yq_name_and_version=${yq_version_output##*version v}  # retain the part after the "v"
  # ex. compare 4.34.1 to 4.33.1
  version_ge "$(major_minor "${yq_name_and_version##* }")" "$(major_minor "${REQUIRED_YQ_VERSION}")"
}

has_k8s_resource() {
  if [[ -z "$1" ]]; then
    return 1
  fi

  local kubectl_get_output
  kubectl_get_output="$("$USABLE_KUBECTL" get "$1" --namespace "${ARIA_NAMESPACE}" -l app=aria-k8s 2> /dev/null | wc -l)"

  if [[ -z "${kubectl_get_output}" ]]; then
    return 1
  fi
  [[ $((kubectl_get_output)) -gt 0 ]]
}

has_specific_k8s_resource() {
  if [[ -z "$1" ]]; then
    return 1
  fi

  if [[ -z "$2" ]]; then
    return 1
  fi

  local kubectl_get_output
  kubectl_get_output="$("$USABLE_KUBECTL" get "$1" "$2" --namespace "${ARIA_NAMESPACE}" 2> /dev/null | wc -l)"

  if [[ -z "${kubectl_get_output}" ]]; then
    return 1
  fi
  [[ $((kubectl_get_output)) -gt 0 ]]
}

remove_old_k8s_resources() {
  if "has_k8s_resource" "clusterrole"; then
    run_command "${USABLE_KUBECTL}" delete clusterrole -l app=aria-k8s
  fi
  if "has_k8s_resource" "clusterrolebinding"; then
    run_command "${USABLE_KUBECTL}" delete clusterrolebinding -l app=aria-k8s
  fi
  if "has_k8s_resource" "deployment"; then
    run_command "${USABLE_KUBECTL}" delete deployment -n "${ARIA_NAMESPACE}" -l "app=${OLD_ARIA_K8S_LABEL}"
  fi
  if "has_k8s_resource" "serviceaccount"; then
    run_command "${USABLE_KUBECTL}" delete serviceaccount -n "${ARIA_NAMESPACE}" -l "app=${OLD_ARIA_K8S_LABEL}"
  fi
  if "has_k8s_resource" "secret"; then
    run_command "${USABLE_KUBECTL}" delete secret -n "${ARIA_NAMESPACE}" collector-client-secret
  fi
  if "has_specific_k8s_resource" "secret" "collector-client-secret"; then
    run_command "${USABLE_KUBECTL}" delete secret -n "${ARIA_NAMESPACE}" collector-client-secret
  fi
}

has_old_resources() {
  # Look for resources that would indicate a cleanup needs to happen due to replacement of the YAML bundle with a Helm
  # chart
  if "has_k8s_resource" "clusterrole"; then echo "clusterrole"; fi
  if "has_k8s_resource" "clusterrolebinding"; then echo "clusterrolebinding"; fi
  if "has_k8s_resource" "deployment"; then echo "deployment"; fi
  if "has_k8s_resource" "serviceaccount"; then echo "serviceaccount"; fi
  if "has_k8s_resource" "secret"; then echo "secret"; fi
  if "has_specific_k8s_resource" "secret" "collector-client-secret"; then echo "secret"; fi
}

# Search for the given executable in PATH (avoids a dependency on the `which` command)
which() {
  # Alias to Bash built-in command `type -P`
  type -P "$@"
}

# Search PATH for the specified program that satisfies requirements. function which is set above
# shellcheck disable=SC2230
find_tool() {
  if [[ $# -ne 1 ]]; then
    return 1
  fi

  local executable
  while read -r executable
  do
    if "test_$1" "${executable}"; then
      echo "${executable}"
      break
    fi
  done < <(which -a "$1")
}

no_usable_helm() {
  [[ -z "$(find_tool helm)" ]]
}

should_helm_install() {
  # chart name
  if [[ -z "$1" ]]; then
    return 1
  fi

  # namespace
  if [[ -z "$2" ]]; then
    return 1
  fi

  local helm_list_output
  helm_list_output="$("$USABLE_HELM" list --namespace "${2}" --short --filter ^"$1"$ 2> /dev/null)"
  [[ -z "${helm_list_output}" ]]
}

should_install_addons() {
  if [[ -z "$1" ]]; then
    return 1
  fi

  local kubectl_nodes_output
  kubectl_nodes_output="$("$USABLE_KUBECTL" get node | grep -cv NAME 2> /dev/null)"
  if [[ -z "${kubectl_nodes_output}" ]]; then
    return 1
  fi
  [[ $((kubectl_nodes_output)) -le $1 || 0 -eq $1 ]]
}

download_yq() {
  # Get the operating system and architecture
  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  arch=$(uname -m)

  if [ "$os" == "linux" ]; then
    if [ "$arch" == "x86_64" ]; then
      asset_name="yq_linux_amd64"
    elif [ "$arch" == "aarch64" ]; then
      asset_name="yq_linux_arm64"
    else
      echo "Unsupported architecture: $arch"
      return 1
    fi
  elif [ "$os" == "darwin" ]; then
    if [ "$arch" == "x86_64" ]; then
      asset_name="yq_darwin_amd64"
    elif [ "$arch" == "arm64" ]; then
      asset_name="yq_darwin_arm64"
    else
      echo "Unsupported architecture: $arch"
      return 1
    fi
  else
    echo "Unsupported operating system: $os"
    return 1
  fi

  # Download the appropriate asset
  download_url="https://github.com/mikefarah/yq/releases/download/v${REQUIRED_YQ_VERSION}/${asset_name}"
  curl -sL "$download_url" -o "${TMPDIR}/yq"

  # Make the binary executable
  chmod +x "${TMPDIR}/yq"
}

check_required_args() {
  if [[ -z "${VMW_ACCESS_KEY:-}" ]] ; then
    abort "Access Key is required to interpret this script."
  fi

  if [[ -z "${VMW_COLLECTOR_CLIENT_SECRET:-}" ]] ; then
    abort "Collector Client Secret is required to interpret this script."
  fi

  if [ -z "${VMW_CLIENT_ID:-}" ]; then
    abort "CSP Client ID is required to interpret this script."
  fi
}

print_work_to_do_wrapper() {
  if [[ $VMW_INSTALL -eq 1 ]]; then
    ohai "This script will install: VMware Aria Kubernetes Collector"
    ohai "This script will install: InfluxDB Telegraf Collector"
    ohai "This script will install: New Relic Pixie Collector"
  elif [[ $VMW_UPGRADE -eq 1 ]]; then
    ohai "This script will upgrade: VMware Aria Kubernetes Collector"
    ohai "This script will upgrade: InfluxDB Telegraf Collector"
    ohai "This script will upgrade: New Relic Pixie Collector"
  fi
}

# shellcheck disable=SC2120
k8s_collector_values_file() {
  local temp_file

  # temp file to write generated YAML To
  if [ $# -ne 1 ] || [ -z "$1" ]; then
    temp_file=$(mktemp)
  else
    temp_file=$1
  fi

  cat << EOF > "${temp_file}"
---
config:
  clusterCloudAccountId: "${VMW_CLUSTER_CLOUD_ACCOUNT_ID}"
  clusterCloudProvider: "${VMW_CLUSTER_CLOUD_PROVIDER}"
  clusterManaged: "${VMW_CLUSTER_MANAGED}"
  clusterName: "${VMW_CLUSTER_NAME}"
  clusterRegion: "${VMW_CLUSTER_REGION}"
  collectorId: "${VMW_COLLECTOR_ID}"
  environment: "${VMW_ENVIRONMENT}"
csp:
  clientId: "${VMW_CLIENT_ID}"
  clientSecret: "${VMW_COLLECTOR_CLIENT_SECRET}"
  host: "${VMW_CSP_HOST}"
  orgId: "${VMW_ORG_ID}"
collector:
  extraEnvironmentVars:
    NETWORK_MAP_METRICS_COLLECT_INTERVAL_SECONDS: "${VMW_NETWORK_MAP_METRICS_COLLECT_INTERVAL_SECONDS}"
    NETWORK_MAP_METRICS_ENDPOINT: "${VMW_NETWORK_MAP_METRICS_ENDPOINT}"
    COLLECTOR_VERSION_OVERRIDE: "${VMW_COLLECTOR_VERSION_OVERRIDE}"
  volumeMounts:
    - name: "aria-k8s-collector"
      mountPath: "/etc/aria-k8s-csp-secret"
      readOnly: true
  volumes:
    - name: "aria-k8s-collector"
      secret:
        secretName: "aria-k8s-collector"
EOF
  echo "${temp_file}"
}

# shellcheck disable=SC2120
telegraf_values_file() {
  local temp_file

  # temp file to write generated YAML To
  if [ $# -ne 1 ] || [ -z "$1" ]; then
    temp_file=$(mktemp)
  else
    temp_file=$1
  fi

  cat << EOF > "${temp_file}"
---
telegraf:
  enabled: true
  extraEnvironmentVars:
    ACCESS_KEY: "${VMW_ACCESS_KEY}"
    CLUSTER_CLOUD_ACCOUNT_ID: "${VMW_CLUSTER_CLOUD_ACCOUNT_ID}"
    CLUSTER_CLOUD_PROVIDER: "${VMW_CLUSTER_CLOUD_PROVIDER}"
    CLUSTER_NAME: "${VMW_CLUSTER_NAME}"
    CLUSTER_REGION: "${VMW_CLUSTER_REGION}"
    HTTP_INGESTION_URL: "${VMW_HTTP_INGESTION_URL}"
    METRICS_DOMAIN: "${VMW_METRICS_DOMAIN}"
    METRICS_STORAGE_POLICY: "${VMW_METRICS_STORAGE_POLICY}"
    ORG_ID: "${VMW_ORG_ID}"
    TRACE_ENTITY_ID: "${VMW_TRACE_ENTITY_ID}"
    TRACE_METRIC: "${VMW_TRACE_METRIC}"
EOF
  echo "${temp_file}"
}

# shellcheck disable=SC2120
pixie_values_file() {
  local temp_file

  # temp file to write generated YAML To
  if [ $# -ne 1 ] || [ -z "$1" ]; then
    temp_file=$(mktemp)
  else
    temp_file=$1
  fi

  cat << EOF > "${temp_file}"
---
deployOLM: "${VMW_DEPLOY_OLM}"
olmNamespace: "olm"
olmOperatorNamespace: "px-operator"
olmBundleChannel: "stable"
name: "pixie"
clusterName: "${VMW_CLUSTER_NAME}"
version: ""
deployKey: "${VMW_DEPLOY_KEY}"
customDeployKeySecret: ""
disableAutoUpdate: false
useEtcdOperator: ${VMW_USE_ETCD_OPERATOR}
cloudAddr: "${VMW_CLOUD_ADDR}"
devCloudNamespace: ""
pemMemoryLimit: "${VMW_PEM_MEMORY_LIMIT}"
pemMemoryRequest: ""
dataAccess: "Full"
pod:
  annotations: {}
  labels: {}
  resources: {}
  nodeSelector: {}
EOF
  echo "${temp_file}"
}

existing_telegraf_values_file() {
  local temp_file
  temp_file=$(mktemp)
  ${USABLE_HELM} get values -o yaml aria-telegraf-collector -n "${ARIA_NAMESPACE}" > "${temp_file}"
  echo "${temp_file}"
}

existing_collector_values_file() {
  local temp_file
  temp_file=$(mktemp)
  ${USABLE_HELM} get values -o yaml aria-k8s-collector -n "${ARIA_NAMESPACE}" > "${temp_file}"
  echo "${temp_file}"
}

existing_pixie_values_file() {
  local temp_file
  temp_file=$(mktemp)
  ${USABLE_HELM} get values -o yaml pixie -n pl > "${temp_file}"
  echo "${temp_file}"
}

run_command() {
  if [ "$VMW_DRY_RUN" -eq 1 ]; then
    echo "DRYRUN: Not executing $*"
    return 0
  fi
  # shellcheck disable=SC2294
  if ! eval "$@"
  then
    abort "$(printf "Failed during: %s" "$(shell_join "$@")")"
  fi
}

set_usable_helm() {
  USABLE_HELM="$(find_tool helm)"
  if [[ -z "${USABLE_HELM}" ]]; then
    abort "$(
      cat <<EOABORT
The version of Helm that was found does not satisfy script requirements.
Please install Helm ${REQUIRED_HELM_VERSION} or newer and add it to your PATH.
EOABORT
    )"
  fi
}

set_usable_yq() {
  if [ "${SHOULD_DOWNLOAD_YQ}" -eq 1 ]; then
    USABLE_YQ="$(find_tool yq)"
    if [[ -z "${USABLE_YQ}" ]]; then
      ohai "Ensuring yq exists"
      ohai "Downloading yq to ${TMPDIR}"
      download_yq
    fi
  fi

  # Re-check yq after attempting to download it if its not installed.
  USABLE_YQ="$(find_tool yq)"
  if [[ -z "${USABLE_YQ}" ]]; then
    abort "$(
      cat <<EOABORT
The version of yq that was found does not satisfy script requirements.
Please install yq ${REQUIRED_YQ_VERSION} or newer and add it to your PATH.
EOABORT
    )"
  fi
}

check_bash() {
  # Fail fast with a concise message when not using bash
  # Single brackets are needed here for POSIX compatibility
  # shellcheck disable=SC2292
  if [ -z "${BASH_VERSION:-}" ]; then
    abort "Bash is required to interpret this script."
  fi
}

check_force_interactive() {
  # Check if script is run with force-interactive mode in CI
  if [[ -n "${CI-}" && -n "${INTERACTIVE-}" ]]; then
    abort "Cannot run force-interactive mode in CI."
  fi
}

set_usable_kubectl() {
  USABLE_KUBECTL="$(find_tool kubectl)"
  if [[ -z "${USABLE_KUBECTL}" ]]; then
    abort "$(
      cat <<EOABORT
The version of kubectl that was found does not satisfy script requirements.
Please install kubectl ${REQUIRED_KUBECTL_VERSION} or newer and add it to your PATH.
EOABORT
    )"
  fi
}

print_legacy_yaml_mesg() {
  if [[ $LEGACY_YAML_DEPLOY -eq 1 ]]; then
    ohai "An existing legacy YAML deployment was found and will be removed."
  fi

  if [[ $LEGACY_YAML_SECRET -eq 1 ]]; then
    ohai "An existing legacy collector secret was found and will be removed."
  fi
}

set_helm_opts() {
  if [[ $VMW_DEBUG -ne 0 ]]; then
    HELM_DEBUG_OPT="--debug "
  else
    HELM_DEBUG_OPT=""
  fi

  if [[ $VMW_HELM_WAIT -ne 0 ]]; then
    HELM_WAIT_OPT="--wait "
  else
    HELM_WAIT_OPT=""
  fi
}

print_resources_to_cleanup() {
  if "has_k8s_resource" "clusterrole"; then
    ohai "ClusterRole with label: ${OLD_ARIA_K8S_LABEL}"
  fi
  if "has_k8s_resource" "clusterrolebinding"; then
    ohai "ClusterRoleBinding with label: ${OLD_ARIA_K8S_LABEL}"
  fi
  if "has_k8s_resource" "deployment"; then
    ohai "Deployment with label: ${OLD_ARIA_K8S_LABEL}"
  fi
  if "has_k8s_resource" "serviceaccount"; then
    ohai "ServiceAccount with label: ${OLD_ARIA_K8S_LABEL}"
  fi
  if "has_k8s_resource" "secret"; then
    ohai "Secret with label: ${OLD_ARIA_K8S_LABEL}"
  fi
  if "has_specific_k8s_resource" "secret" "collector-client-secret"; then
    ohai "Secret: collector-client-secret"
  fi
}

main() {
  trap 'rm -rf -- "$VALUES_TMP_DIR"' EXIT

  # Things can fail later if `pwd` doesn't exist.
  # Also sudo prints a warning message for no good reason
  cd "/usr" || exit 1

  check_bash
  check_force_interactive

  # Check if both `INTERACTIVE` and `NONINTERACTIVE` are set
  # Always use single-quoted strings with `exp` expressions
  # shellcheck disable=SC2016
  if [[ -n "${INTERACTIVE-}" && -n "${NONINTERACTIVE-}" ]]
  then
    abort 'Both `$INTERACTIVE` and `$NONINTERACTIVE` are set. Please unset at least one variable and try again.'
  fi

  # Check if script is run in POSIX mode
  if [[ -n "${POSIXLY_CORRECT+1}" ]]
  then
    abort 'Bash must not run in POSIX mode. Please unset POSIXLY_CORRECT and try again.'
  fi

  # Check if script is run non-interactively (e.g. CI)
  # If it is run non-interactively we should not prompt for passwords.
  # Always use single-quoted strings with `exp` expressions
  # shellcheck disable=SC2016
  if [[ -z "${NONINTERACTIVE-}" ]]
  then
    if [[ -n "${CI-}" ]]
    then
      warn 'Running in non-interactive mode because `$CI` is set.'
      NONINTERACTIVE=1
    elif [[ ! -t 0 ]]
    then
      if [[ -z "${INTERACTIVE-}" ]]
      then
        warn 'Running in non-interactive mode because `stdin` is not a TTY.'
        NONINTERACTIVE=1
      else
        warn 'Running in interactive mode despite `stdin` not being a TTY because `$INTERACTIVE` is set.'
      fi
    fi
  else
    ohai 'Running in non-interactive mode because `$NONINTERACTIVE` is set.'
  fi

  set_detected_os

  # Helm will re-use values except in times of upgrade where we might want to set new values.
  if [[ $VMW_INSTALL -eq 1 ]]; then
    check_global_required_args
  fi

  set_usable_helm
  set_usable_kubectl
  set_usable_yq

  check_legacy_yaml_deploy
  check_legacy_secret
  charts_need_upgrade
  charts_need_install

  if [[ $LEGACY_YAML_DEPLOY -eq 1 && $VMW_INSTALL -eq 1 ]]; then
    # fresh helm install; legacy yaml deployed

    # Attempt to read generated data from the existing installation because these will not presently be known by Helm.
    # Reading existing content will be skipped if the user provided arguments for that content
    if [ "${VMW_DEFAULT_COLLECTOR_CLIENT_SECRET}" = "${VMW_COLLECTOR_CLIENT_SECRET}" ]; then
      read_client_secret
    else
      ohai "Skipping lookup of existing client secret because it was provided on the command line"
    fi
    if [ "${VMW_DEFAULT_CLIENT_ID}" = "${VMW_CLIENT_ID}" ]; then
      read_client_id
    else
      ohai "Skipping lookup of existing client ID because it was provided on the command line"
    fi

    check_required_args
  elif [[ $LEGACY_YAML_SECRET -eq 1 ]]; then
    # edge-case where helm charts were deployed, but old secret env params still used.
    if [ "${VMW_DEFAULT_COLLECTOR_CLIENT_SECRET}" = "${VMW_COLLECTOR_CLIENT_SECRET}" ]; then
      read_client_secret
    else
      ohai "Skipping lookup of existing client secret because it was provided on the command line"
    fi
  elif [[ $LEGACY_YAML_DEPLOY -eq 1 && $VMW_UPGRADE -eq 1 ]]; then
    # fresh helm install; legacy yaml deployed; failed prior helm install
    :
  elif [[ $LEGACY_YAML_DEPLOY -eq 0 && $VMW_INSTALL -eq 1 ]]; then
    # fresh helm install
    check_required_args
  elif [[ $LEGACY_YAML_DEPLOY -eq 0 && $VMW_UPGRADE -eq 1 ]]; then
    # existing helm install, upgrade chart
    :
  fi

  print_work_to_do_wrapper
  print_legacy_yaml_mesg

  if [[ -z "${NONINTERACTIVE-}" ]]; then
    ring_bell
    wait_for_user
  fi

if "should_install_addons" "${VMW_NODE_LIMIT}"; then
  ohai "Deploying Aria Kubernetes Collector and add-ons..."
else
  ohai "Deploying Aria Kubernetes Collector"
fi

(
  # pixie is not yet distributed via oci images
  run_command "${USABLE_HELM}" repo add pixie-operator "${PIXIE_HELM_REPO}"
  run_command "${USABLE_HELM}" repo update

  set_helm_opts

  if "should_install_addons" "${VMW_NODE_LIMIT}"
  then
    if [[ $VMW_INSTALL -eq 1 ]]; then
      if "should_helm_install" "aria-telegraf-collector" "${ARIA_NAMESPACE}"
      then
        # install vmw version of telegraf collector helm. includes consistent variable naming across vmw charts
        # shellcheck disable=SC2086
        run_command ${USABLE_HELM} install aria-telegraf-collector "${TELEGRAF_HELM_REPO}" \
          --create-namespace \
          ${HELM_DEBUG_OPT} \
          --namespace "${ARIA_NAMESPACE}" \
          --values "$(telegraf_values_file)" \
          --version "${TELEGRAF_CHART_VERSION}" \
          ${HELM_WAIT_OPT}
      fi
    else
      # Save existing helm values
      have="$(existing_telegraf_values_file)"
      want="$(telegraf_values_file)"

      # Manipulate the "want" values to remove empty strings
      #
      # Empty values can exist if you run the install.sh as an upgrade. In this case, fields like csp.clientSecret
      # and `telegraf.extraEnvironmentVars.ACCESS_KEY` can potentially be unset because they are not stored and are
      # irretrievable after they are provided during install.
      yq -i 'del(.. | select(length == 0))' "${want}"

      # Upgrade the chart
      # shellcheck disable=SC2086
      run_command ${USABLE_HELM} upgrade \
        aria-telegraf-collector \
        "${TELEGRAF_HELM_REPO}" \
        ${HELM_DEBUG_OPT} \
        --namespace "${ARIA_NAMESPACE}" \
        --version "${TELEGRAF_CHART_VERSION}" \
        --reset-values \
        --values "${have}" \
        --values "${want}" \
        ${HELM_WAIT_OPT}
    fi

    if [[ $VMW_INSTALL -eq 1 ]]; then
      if "should_helm_install" "pixie" "pl"
      then
        # shellcheck disable=SC2086
        run_command ${USABLE_HELM} install \
          pixie \
          pixie-operator/pixie-operator-chart \
          --create-namespace \
          ${HELM_DEBUG_OPT} \
          --namespace "${PIXIE_NAMESPACE}" \
          --values "$(pixie_values_file)" \
          --version "${PIXIE_CHART_VERSION}" \
          ${HELM_WAIT_OPT}
      fi
    else
      # Save existing helm values
      have="$(existing_pixie_values_file)"
      want="$(pixie_values_file)"

      # Manipulate the "want" values to remove empty strings
      #
      # Empty values can exist if you run the install.sh as an upgrade. In this case, fields like csp.clientSecret
      # and `telegraf.extraEnvironmentVars.ACCESS_KEY` can potentially be unset because they are not stored and are
      # irretrievable after they are provided during install.
      yq -i 'del(.. | select(length == 0))' "${want}"

      # shellcheck disable=SC2086
      run_command ${USABLE_HELM} upgrade \
        pixie \
        pixie-operator/pixie-operator-chart \
        ${HELM_DEBUG_OPT} \
        --namespace "${PIXIE_NAMESPACE}" \
        --version "${PIXIE_CHART_VERSION}" \
        --reset-values \
        --values "${have}" \
        --values "${want}" \
        ${HELM_WAIT_OPT}
    fi
  fi

  if [[ $VMW_INSTALL -eq 1 ]]; then
    if "should_helm_install" "aria-k8s-collector" "${ARIA_NAMESPACE}"
    then
      # the aria-k8s-collector is installed via OCI images; requires Helm >= 3.8
      # shellcheck disable=SC2086
      run_command ${USABLE_HELM} install \
        aria-k8s-collector \
        "${K8S_COLLECTOR_HELM_REPO}" \
        --create-namespace \
        ${HELM_DEBUG_OPT} \
        --namespace "${ARIA_NAMESPACE}" \
        --values "$(k8s_collector_values_file)" \
        --version "${K8S_COLLECTOR_CHART_VERSION}" \
        ${HELM_WAIT_OPT}
    fi
  else
    # save existing helm values
    have="$(existing_collector_values_file)"
    want="$(k8s_collector_values_file)"

    # Manipulate the "want" values to remove empty strings
    #
    # Empty values can exist if you run the install.sh as an upgrade. In this case, fields like csp.clientSecret
    # and `telegraf.extraEnvironmentVars.ACCESS_KEY` can potentially be unset because they are not stored and are
    # irretrievable after they are provided during install.
    yq -i 'del(.. | select(length == 0))' "${want}"

    # shellcheck disable=SC2086
    run_command ${USABLE_HELM} upgrade \
      aria-k8s-collector \
      "${K8S_COLLECTOR_HELM_REPO}" \
      ${HELM_DEBUG_OPT} \
      --namespace "${ARIA_NAMESPACE}" \
      --version "${K8S_COLLECTOR_CHART_VERSION}" \
      --reset-values \
      --values "${have}" \
      --values "${want}" \
      ${HELM_WAIT_OPT}
  fi
) || exit 1

ohai "Installation successful!"
echo

ring_bell

if [ "${VMW_CLEANUP_OLD_RESOURCES}" -eq 1 ] && [ "$(has_old_resources)" ]
then
  ohai "Old resources were found which will be deleted:"

  print_resources_to_cleanup

  if [[ -z "${NONINTERACTIVE-}" ]]
  then
    ring_bell
    wait_for_user
  fi
  (
    remove_old_k8s_resources
    ohai "Cleanup successful!"
    echo
  ) || exit 1
fi

cat <<EOS
- Further documentation:
    ${tty_underline}https://docs.vmware.com/${tty_reset}

EOS
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  parse_args "$@"
  main "$@"
fi
