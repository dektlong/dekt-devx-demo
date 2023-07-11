#!/bin/bash

# Copyright (c) 2019-2020 VMware Inc.
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

###################################################################
# Script Name	  : vss_aws_bulk_deactivate_event_stream.sh
# Description	  : The script uses administrator IAM user with AdministratorAccess permissions https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_accounts_access.html#orgs_manage_accounts_access-cross-account-role
# Usage         : ./vss_aws_bulk_deactivate_event_stream.sh 857350542564 739636793709 905467601150,OrganizationAccountAccessRole_3
# Author       	: vss lifters
# Email         : support@cloudhealthtech.com
###################################################################

readonly COMMAND_USAGE='Usage: bash vss_aws_bulk_deactivate_event_stream.sh  <AccountID_1>{,<RootRoleName_1>} <AccountID_2>{,<RootRoleName_2>} where RootRoleName_1 is optional'
readonly MAXIMUM_NUMBER_OF_ARGUMENTS=100
readonly AWS_DEFAULT_ROOT_ROLE="OrganizationAccountAccessRole"
readonly VSS_TOPIC_NAME="cloudcoreo-events"
readonly STACK=cloudcoreo-events

declare -a ACCOUNTS_INFO_ARRAY
declare -a UNSUCCESSFUL_ACCOUNTS
declare -a ENABLED_REGIONS
declare ROOT_ACCOUNT

readonly _COLOR_GREEN=`tput setaf 2`
readonly _COLOR_RED=`tput setaf 1`
readonly _COLOR_YELLOW=`tput setaf 3`
readonly _COLOR_MAGENTA=`tput setaf 5`
readonly _COLOR_RESET=`tput sgr0`


#######################################
# Validates environment in which script is run.
# Returns:
#   0 if ok, non-zero on error.
#######################################
validate_environment(){
  # Checks whether aws command exists - exit if not
  if ! command -v aws >/dev/null 2>&1
  then
    log "${_COLOR_RED}ERROR:${_COLOR_RESET} Please install AWS Command Line Interface first: http://docs.aws.amazon.com/cli/latest/userguide/installing.html"
    exit 1
  fi
}


#######################################
# Validates and extracts inputs of script
# Arguments:
#   Array of the following string entries: <AccountID_1>,<RootRoleName_1>
# Outputs:
#   0 if ok, non-zero on error.
#######################################
extract_input_arguments() {
  local index=0

  # Check if arguments are more than the limit
  if [ "$#" -gt $MAXIMUM_NUMBER_OF_ARGUMENTS ]; then
    log "${_COLOR_RED}ERROR:${_COLOR_RESET} Number of input arguments exceeds the limit of ${MAXIMUM_NUMBER_OF_ARGUMENTS}"
    exit 1
  fi

  # Extract arguments
  for tuple in "$@"; do
    index=${index}+1

    IFS=, read acc_id root_role <<< "$tuple"

    if [ -z "${acc_id}" ]; then
      log "${_COLOR_RED}ERROR:${_COLOR_RESET} on $index argument with value $var\nThe arguments <AccountID_1>,<RootRoleName_1> are required. $COMMAND_USAGE"
      exit 1
    fi

    if [ -z "${root_role}" ]; then
      root_role="${AWS_DEFAULT_ROOT_ROLE}"
    fi

    ACCOUNTS_INFO_ARRAY+=("$acc_id,$root_role")

  done
}

#######################################
# Assumes role for root account
# Arguments:
#   AccountId
#   RootRoleName
# Outputs:
#   Exports aws creds
#######################################
assume_role() {
  use_aws_credentials_file

  log  "${_COLOR_GREEN}INFO:${_COLOR_RESET} Getting credentials for account ${1} for role ${2}"

  export $(printf "AWS_ACCESS_KEY_ID=%s AWS_SECRET_ACCESS_KEY=%s AWS_SESSION_TOKEN=%s" \
  $(aws sts assume-role \
  --role-arn arn:aws:iam::$1:role/$2 \
  --role-session-name session_in_acc_$1 \
  --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]" \
  --output text))
}

#######################################
# Starts the process for Accounts Onboarding for each account specified
# Globals:
#   ACCOUNTS_INFO_ARRAY
#######################################
vss_deactivate_streams() {

  for account in "${ACCOUNTS_INFO_ARRAY[@]}";  do
    IFS=, read acc_id root_role <<< "$account"

    # Skip assume role for root account
    if [ "${acc_id}" != "${ROOT_ACCOUNT}" ]; then
      assume_role "${acc_id}" "${root_role}"
    fi

    if { [ -z "${AWS_ACCESS_KEY_ID}" ] || [ -z "${AWS_SECRET_ACCESS_KEY}" ] || [ -z "${AWS_SESSION_TOKEN}" ]; } && [ "${acc_id}" != "${ROOT_ACCOUNT}" ]; then
      log "${_COLOR_MAGENTA}WARNING: ${_COLOR_RESET}Account $acc_id is skipped, due to error when fetching credentials"
      fail_account "$account"
    else
      account_stream_deactivation "${acc_id}"
      if [ ! $? -eq 0 ]; then
        log "${_COLOR_RED}ERROR:${_COLOR_RESET} Account Event Deactivation process for $account failed."
        fail_account "$account"
      fi
    fi

    use_aws_credentials_file
  done
}

#######################################
# Onboards an account
# Globals:
# Arguments:
#   AccountId
#######################################
account_stream_deactivation() {
  local acc_id_param=$1

  log  "${_COLOR_GREEN}INFO:${_COLOR_RESET} Starting account stream deactivation process for account ${acc_id_param} "

  # Refresh Enabled Regions for account
  if ! refresh_enabled_regions "${acc_id_param}"; then
    log "${_COLOR_RED}ERROR:${_COLOR_RESET} Getting regions for ${acc_id_param} failed."
    return 1
  fi

  for region in "${ENABLED_REGIONS[@]}";  do
    delete_cf_stack "${acc_id_param}" "${region}" &
  done
  wait
}

#######################################
# Installs CloudFormation Stack from Template
# Globals:
#   TEMPLATE_URL
#   VERSION
#   VSS_QUEUE_ARN
#   VSS_TOPIC_NAME
#   VSS_MONITORING_RULE
#   VSS_TOPIC_ENCRYPTION_KEY_NAME
# Arguments:
#   AccountId
#   RegionName
#######################################
delete_cf_stack(){
  local acc_id_param=$1
  local region_name=$2
  local topic_arn="arn:aws:sns:${region_name}:${acc_id_param}:${VSS_TOPIC_NAME}"

  list_topics=$(aws sns list-topics --output text --region "${region_name}")
  has_topic=$(echo "${list_topics}" | grep ${topic_arn})
  if [ -z "${has_topic}" ]; then
    # Region is skipped as it doesn't have the required topic.
    #log  "${_COLOR_GREEN}INFO:${_COLOR_RESET} Region ${region_name} is skipped as it doesn't have the topic ${topic_arn}"
    return 0
  fi

  log  "${_COLOR_GREEN}INFO:${_COLOR_RESET} Starting deletion of cloudformation stack for account ${acc_id_param} in region ${region_name}"
  topic_message=$(aws sns publish --topic-arn "${topic_arn}" --message UnsubscribeConfirmation --region "${region_name}")

  # Deleting stack if exists
  stack=$(aws cloudformation delete-stack --stack-name ${STACK} --region "${region_name}")

  if [ $? -eq 0 ]; then
    log  "${_COLOR_GREEN}INFO:${_COLOR_RESET} Successfully deleted cloudformation stack ${STACK} for account ${acc_id_param} in region ${region_name}"
    return 0
  else
    log "${_COLOR_RED}ERROR:${_COLOR_RESET} Account Stack Deletion process for ${acc_id_param} failed."
    return 1
  fi
}

#######################################
# Refresh List of Enabled Regions
# Globals:
#   ENABLED_REGIONS
# Arguments:
#   AccountId
#######################################
refresh_enabled_regions(){
  local regions=( "af-south-1" "eu-north-1" "ap-south-1" "eu-west-3" "eu-west-2" "eu-south-1" "eu-west-1" "ap-northeast-3" "ap-northeast-2" "me-south-1" "ap-northeast-1" "sa-east-1" "ca-central-1" "ap-east-1" "ap-southeast-1" "ap-southeast-2" "eu-central-1" "us-east-1" "us-east-2" "us-west-1" "us-west-2" )
  local acc_id_param=$1
  log  "${_COLOR_GREEN}INFO:${_COLOR_RESET} Getting regions for account ${acc_id_param} "

  enabled_regions=$(aws ec2 describe-regions --query "Regions[].{Name:RegionName}" --output text)

  if [ -z "${enabled_regions}" ]; then
    unset ENABLED_REGIONS
    ENABLED_REGIONS=("${regions[@]}")
  else
    unset ENABLED_REGIONS
    IFS=$'\n' read -r -d '' -a ENABLED_REGIONS <<< "$enabled_regions"
  fi
  echo "${ENABLED_REGIONS[@]}"
}

#######################################
# Clears all aws creds so that the aws cli uses the ~/.aws/credentials file as source for creds
#######################################
use_aws_credentials_file() {
  export AWS_ACCESS_KEY_ID=
  export AWS_SECRET_ACCESS_KEY=
  export AWS_SESSION_TOKEN=
}

#######################################
# List all unsuccessful accounts
# Globals:
#   UNSUCCESSFUL_ACCOUNTS
#######################################
list_failed_accounts() {
  if [ ${#UNSUCCESSFUL_ACCOUNTS[@]} -eq 0 ]; then
    log "${_COLOR_GREEN}INFO:${_COLOR_RESET} All accounts passed successfully."
  else
    log "${_COLOR_RED}Failed Accounts: ${_COLOR_YELLOW}${UNSUCCESSFUL_ACCOUNTS[*]}${_COLOR_RESET}"
  fi
}


#######################################
# Adds unsuccessful accounts for individual examination
# Arguments:
#   String: "<AccountID_1>{,<RootRoleName_1>}"
#######################################
fail_account() {
  UNSUCCESSFUL_ACCOUNTS+=("$1")
}


log() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
}

#######################################
# Gets root account
# Globals:
#   ROOT_ACCOUNT
#######################################
function get_root_account() {
  log  "${_COLOR_GREEN}INFO:${_COLOR_RESET} Getting root account id for session's aws credentials."

  ROOT_ACCOUNT=$(aws sts get-caller-identity --output text --query "Account")
  if [ $? -ne 0 ]; then
    log  "${_COLOR_RED}ERROR:${_COLOR_RESET} Couldn't get root account."
    exit 1
  fi
}

main() {
  log "${_COLOR_GREEN}INFO:${_COLOR_RESET} Running for $# accounts."
  validate_environment
  extract_input_arguments "$@"
  get_root_account
  vss_deactivate_streams
  list_failed_accounts
}

main "$@"
