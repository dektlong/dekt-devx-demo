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
# Script Name	  : vss_azure_bulk_event_stream_setup.sh
# Description	  : The script uses az cli and for each subscriptions 1) Create a resource group for the action group; 2) Deploy template which creates an action group in Azure for our webhook;
#  3) Deploy template which creates an alert for activity log events in Azure forwarding to our webhook; 4) Send stream hookup success event.
# Usage         : ./vss_azure_bulk_event_stream_setup.sh  <Subscription_1> <Subscription_2>
# Author       	: vss lifters
# Email         : support@cloudhealthtech.com
###################################################################
readonly COMMAND_USAGE='Usage: bash vss_azure_bulk_event_stream_setup.sh  <Subscription_1> <Subscription_2> <Subscription_3>'
readonly ALERT_DEPLOY_FILE="azure_webhook_alert.json"
readonly ACTION_DEPLOY_FILE="azure_webhook_action.json"
readonly RESOURCE_GROUP="cc_az_webhook_resource_group"
readonly FAILED_PREFIX="failed_subs_"
readonly ACTION_DEPLOYMENT_NAME="cc_az_action_group_deployment"
readonly ACTION_GROUP="cc_az_webhook_action_group"
readonly ACTION_GROUP_SHORT="cc_az_ag"
readonly WEBHOOK_RECEIVER_NAME="cc_az_webhook"
readonly ALERT_DEPLOYMENT_NAME="cc_az_alert_deployment"
readonly ALERT_NAME="cc_az_activity_log_alert"

readonly MAXIMUM_NUMBER_OF_ARGUMENTS=100
readonly DEFAULT_REGION="eastus"
readonly WEBHOOK_ALERT_TEMPLATE_URL="https://api.securestate.vmware.com/download/onboarding/azure/bulk/azure_webhook_alert.json"
readonly WEBHOOK_ACTION_TEMPLATE_URL="https://api.securestate.vmware.com/download/onboarding/azure/bulk/azure_webhook_action.json"
readonly WEBHOOK_SERVICE_URI="https://r62g0jx9a9.execute-api.us-west-2.amazonaws.com/LATEST/"

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
#   non-zero on error.
#######################################
function validate_environment(){
  # Checks whether az command exists - exit if not
  if ! command -v az >/dev/null 2>&1
  then
    log  "$E Please install AZ Command Line Interface first: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
  fi
}

#######################################
# Validates and extracts inputs of script
# Arguments:
#   Array of the following string entries: <Subscription_1>,<Region_1> <Subscription_2>,<Region_2> <Subscription_3>,<Region_3>... where <Region_X> is optional
# Outputs:
#   non-zero on error.
#######################################
function extract_input_arguments() {
  if [ "$#" -lt 1 ]; then
    log  "$E Number of input arguments is 0 please provide input arguments. $COMMAND_USAGE "
    exit 1
  fi

  # Check if arguments are more than the limit
  if [ "$#" -gt $MAXIMUM_NUMBER_OF_ARGUMENTS ]; then
    log  "$E Number of input arguments exceeds the limit of ${MAXIMUM_NUMBER_OF_ARGUMENTS}"
    exit 1
  fi

  # Extract arguments
  local index=0
  for tuple in "$@"; do
    index=${index}+1
    IFS=, read sub_id location <<< "$tuple"

    if [ -z "${sub_id}" ]; then
      log  "$E on $index argument with value $var\n The arguments should be <SUBS_1>,<REGION_1> where <REGION_1> is optional. $COMMAND_USAGE"
      exit 1
    fi

    if [ -z "${location}" ]; then
      location=$DEFAULT_REGION
    fi

    SUBSCRIPTIONS_INFO_ARRAY+=("$sub_id,$location")
  done
}

#######################################
# Download predefined templates using for "az deployment group create"
#######################################
function vss_download_templates() {
  log  "$I Start downloads $ALERT_DEPLOY_FILE and $ACTION_DEPLOY_FILE"
  curl $WEBHOOK_ALERT_TEMPLATE_URL --output $ALERT_DEPLOY_FILE && curl $WEBHOOK_ACTION_TEMPLATE_URL --output $ACTION_DEPLOY_FILE
}

#######################################
# Adds unsuccessful Subscriptions for individual examination
# Arguments:
#   String:  "<Subscription_1>"
#######################################
function fail_subscriptions() {
  log  >> $FAILED_PREFIX$1
}

#######################################
# Check for failed subscriptions and print
#######################################
function read_failed_subscriptions() {
  failed_subs=$(ls | grep $FAILED_PREFIX)
  if [ ! -z "$failed_subs" ]; then
    log
    log  "${_COLOR_RED}********FAILED SUBSCRIPTIONS LIST********${_COLOR_RESET}"
    for f in $failed_subs
    do
      rm $f
      f_sub_id=${f//$FAILED_PREFIX/""}
      log  "${_COLOR_RED}$f_sub_id ${_COLOR_RESET}"
    done
  else
    log  "${_COLOR_GREEN}INFO: All subscriptions passed successfully.${_COLOR_RESET}"
  fi
}

#######################################
# Setup subscription:
#   Create resource group
#   Create an action group with deployment
#   Create an alert with deployment
#   Create an alert with deployment
#   Send stream hookup success event to CHSS
# Arguments:
#   Subscription
#   Location
# Outputs:
#   non-zero on error.
#######################################
function vss_az_subs_setup() {
  local sub_id=$1
  local location=$2
  log  "$I Start onboard for $sub_id subscription in $location location"

  # Create a resource group for the action group
  local created_group=$(az group create --name $RESOURCE_GROUP --location $location --subscription $sub_id)
  if [ -z "$created_group" ]; then
    log  "$E Failed when try to create resource group for subscription $sub_id"
    fail_subscriptions "$sub_id"
    return 1
  else
    log  "$I Successfully created resource group $RESOURCE_GROUP for subscription $sub_id "
  fi

  # Deploy template which creates an action group in Azure for our webhook
  local created_action_deployment=$(az deployment group create --name $ACTION_DEPLOYMENT_NAME --resource-group $RESOURCE_GROUP --template-file $ACTION_DEPLOY_FILE --subscription $sub_id --parameters actionGroupName=$ACTION_GROUP actionGroupShortName=$ACTION_GROUP_SHORT webhookReceiverName=$WEBHOOK_RECEIVER_NAME webhookServiceUri=$WEBHOOK_SERVICE_URI)
  if [ -z "$created_action_deployment" ]; then
    log  "$E Failed when try to create action group deployment for subscription $sub_id"
    fail_subscriptions "$sub_id"
    return 1
  else
    log  "$I Successfully created action group $ACTION_GROUP with deployment $ACTION_DEPLOYMENT_NAME for subscription $sub_id "
  fi

  # Deploy template which creates an alert for activity log events in Azure forwarding to our webhook
  local created_alert_deployment=$(az deployment group create --name $ALERT_DEPLOYMENT_NAME --resource-group $RESOURCE_GROUP --template-file $ALERT_DEPLOY_FILE --subscription $sub_id --parameters activityLogAlertName=$ALERT_NAME actionGroupResourceId="/subscriptions/${sub_id}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Insights/actionGroups/${ACTION_GROUP}")
  if [ -z "$created_alert_deployment" ]; then
    log  "$E Failed when try to create alert group deployment for subscription $sub_id"
    fail_subscriptions "$sub_id"
    return 1
  else
    log  "$I Successfully created alert $ALERT_NAME with deployment $ALERT_DEPLOYMENT_NAME for subscription $sub_id "
  fi

  # Send stream hookup success event.
  local chss_stream_ready_event=$(curl -X POST $WEBHOOK_SERVICE_URI -H 'Content-Type: application/json' -d '{"data": {"context": {"activityLog": {"subscriptionId": "'"$sub_id"'", "operationName": "AzureStreamReady"}}}}')
  if [ "$chss_stream_ready_event" == "null" ]; then
    log  "$I Successfully send stream hookup event to CHSS $WEBHOOK_SERVICE_URI for subscription $sub_id "
  else
    log  "$E Failed when send stream hookup success event for subscription $sub_id $chss_stream_ready_event"
    fail_subscriptions "$sub_id"
    return 1
  fi
}

#######################################
# Starts the process for Subscription Onboarding for each subs specified
# Globals:
#   SUBSCRIPTIONS_INFO_ARRAY
#######################################
function vss_bulk_subs_setup() {
  for subs in "${SUBSCRIPTIONS_INFO_ARRAY[@]}"; do
    IFS=, read sub_id location <<< "$subs"
    vss_az_subs_setup $sub_id $location &
  done
  wait
}

function main() {
  validate_environment
  log  "$I Running for $# subscriptions."
  extract_input_arguments "$@"
  vss_download_templates
  vss_bulk_subs_setup
  read_failed_subscriptions
}

main "$@"