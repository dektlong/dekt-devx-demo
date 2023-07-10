#!/bin/bash
#
# Copyright (c) 2022-2023 VMware Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

###################################################################
# Script Name	  : vss_azure_bulk_event_stream_deactivate.sh
# Description	  : The script uses az cli and for each subscriptions 1) Delete exist CHSS cc_az_webhook_resource_group resource group 2)  Send stream not ready hookup event to CHSS.
#                 CSP_REFRESH_TOKEN https://docs.vmware.com/en/CloudHealth-Secure-State/services/api-reference/GUID-getting-started.html is used for authentication
# Usage         : ./vss_azure_bulk_event_stream_deactivate.sh <Subscription_1> <Subscription_2>
# Author       	: vss lifters
# Email         : support@cloudhealthtech.com
###################################################################

readonly COMMAND_USAGE='Usage: bash vss_azure_bulk_event_stream_deactivate.sh  <Subscription_1> <Subscription_2> <Subscription_3>'
readonly BASE_ARIA_SECURE_CLOUDS_FQDN="securestate.vmware.com"
readonly BASE_CSP_FQDN="console.cloud.vmware.com"

readonly MAXIMUM_NUMBER_OF_ARGUMENTS=100
readonly FAILED_PREFIX="failed_subs_"
readonly RESOURCE_GROUP="cc_az_webhook_resource_group"
readonly WEBHOOK_EVENT_STREAM_STATUS_URL="https://events.${BASE_ARIA_SECURE_CLOUDS_FQDN}/status"
readonly CSP_AUTH_URL="https://${BASE_CSP_FQDN}/csp/gateway/am/api/auth/api-tokens/authorize"

declare -a SUBSCRIPTIONS_INFO_ARRAY

readonly _COLOR_GREEN=`tput setaf 2`
readonly _COLOR_RED=`tput setaf 1`
readonly _COLOR_YELLOW=`tput setaf 3`
readonly _COLOR_MAGENTA=`tput setaf 5`
readonly _COLOR_RESET=`tput sgr0`
readonly I=${_COLOR_GREEN}INFO:${_COLOR_RESET}
readonly E=${_COLOR_RED}ERROR:${_COLOR_RESET}

function log() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
}

#######################################
# Validates environment in which script is run.
# Returns:
#   0 if ok, non-zero on error.
#######################################
function validate_environment(){
  # Checks whether az command exists - exit if not
  if ! command -v az >/dev/null 2>&1
  then
    echo "$E Please install AZ Command Line Interface: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
  fi

  # Checks whether CSP_REFRESH_TOKEN environment variable exists - exit if not
  if [ -z "${CSP_REFRESH_TOKEN}" ]; then
    log  "$E Please set CSP_REFRESH_TOKEN environment variable: https://docs.vmware.com/en/CloudHealth-Secure-State/services/api-reference/GUID-getting-started.html"
    exit 1
  fi
}

#######################################
# Validates and extracts inputs of script
# Arguments:
#   Array of the following string entries: <Subscription_1> <Subscription_2> <Subscription_3>
# Outputs:
#   non-zero on error.
#######################################
function extract_input_arguments() {
  # Check if arguments are more than the limit
  if [ "$#" -lt 1 ]; then
    log "$E Number of input arguments is 0, please provide input arguments. $COMMAND_USAGE "
    exit 1
  fi

  # Check if arguments are more than the limit
  if [ "$#" -gt $MAXIMUM_NUMBER_OF_ARGUMENTS ]; then
    log "$E Number of input arguments exceeds the limit of ${MAXIMUM_NUMBER_OF_ARGUMENTS}"
    exit 1
  fi

  # Extract arguments
  for sub in "$@"; do
    SUBSCRIPTIONS_INFO_ARRAY+=("$sub")
  done
}

#######################################
# Adds unsuccessful Subscriptions for individual examination
# Arguments:
#   String:  "<Subscription_1>"
#######################################
function fail_subscriptions() {
  log >> $FAILED_PREFIX"$1"
}

#######################################
# Check for failed subscriptions and print
#######################################
function read_failed_subscriptions() {
  failed_subs=$(ls | grep $FAILED_PREFIX)
  if [ -n "$failed_subs" ]; then
    log
    log "${_COLOR_RED}********FAILED SUBSCRIPTIONS LIST********${_COLOR_RESET}"
    for f in $failed_subs
    do
      rm $f
      f_sub_id=${f//$FAILED_PREFIX/""}
      log "${_COLOR_RED}$f_sub_id ${_COLOR_RESET}"
    done
  else
    log "${_COLOR_GREEN}INFO: All subscriptions passed successfully.${_COLOR_RESET}"
  fi
}

#######################################
# Deactivate event stream for subscription:
#   Delete resource group
#   Send stream not ready hookup event to CHSS
# Arguments:
#   Subscription
# Outputs:
#   non-zero on error.
#######################################
function vss_az_subs_deactivate() {
  local sub_id=$1
  log "$I Start deactivate event stream for $sub_id subscription."

  # Delete a resource group for the action group
  az group delete --resource-group $RESOURCE_GROUP --yes --subscription "$sub_id" && l_ok=OK || l_ok=""
  if [ -z "$l_ok" ]; then
    log "$E Failed when trying to delete resource group $RESOURCE_GROUP for subscription $sub_id"
    fail_subscriptions "$sub_id"
    return 1
  else
    log "$I Successfully deleted resource group $RESOURCE_GROUP for subscription $sub_id"
  fi

  # Send stream removal success event.
  local access_token=$(curl -s -X POST ${CSP_AUTH_URL} -d refresh_token="${CSP_REFRESH_TOKEN}" | jq -r .access_token)
      if [ "$access_token" != "null" ]; then
          log  "$I Successfully received bearer token"
      else
          log  "$E Failed to retrieve bearer token: refresh token is most likely incorrectly set"
          fail_subscriptions "$sub_id"
          return 1
      fi

  local stream_stop_event=$(curl -s -X POST ${WEBHOOK_EVENT_STREAM_STATUS_URL} -H "Authorization: Bearer ${access_token}" -d "{\"provider\": \"azure\", \"account_id\": \"${sub_id}\", \"active\": false }" )
      if [ "$stream_stop_event" == "Accepted" ]; then
          log  "$I Successfully sent stop stream hookup event to CHSS ${WEBHOOK_EVENT_STREAM_STATUS_URL} for subscription $sub_id"
      else
          log  "$E Failed to send stop stream hookup success event for subscription $sub_id $stream_stop_event"
        fail_subscriptions "$sub_id"
        return 1
      fi

}

#######################################
# Starts the process for event stream deactivated for each subs specified
# Globals:
#   SUBSCRIPTIONS_INFO_ARRAY
#######################################
function vss_bulk_subs_deactivate() {
  for subs in "${SUBSCRIPTIONS_INFO_ARRAY[@]}"; do
    vss_az_subs_deactivate "$subs" &
  done
  wait
}

function main() {
  validate_environment
  log "$I Running deactivate azure event streams for $# subscriptions."
  extract_input_arguments "$@"
  vss_bulk_subs_deactivate
  read_failed_subscriptions
}

main "$@"
