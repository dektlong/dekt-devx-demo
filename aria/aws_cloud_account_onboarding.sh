#!/bin/bash

#
# Copyright (c) 2022 VMware, Inc. All Rights Reserved.
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
# Script Name	  : vss_aws_bulk_account_onboarding.sh
# Description	  : The script uses administrator IAM user with AdministratorAccess permissions https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_accounts_access.html#orgs_manage_accounts_access-cross-account-role
# Usage         : ./vss_aws_bulk_account_onboarding.sh 857350542564 739636793709 905467601150,OrganizationAccountAccessRole_3
# Author       	: vss lifters
# Email         : support@cloudhealthtech.com
###################################################################

readonly COMMAND_USAGE='Usage: bash vss_aws_bulk_account_onboarding.sh  <<AccountID_1>{,AriaHubRoleName}{,<RootRoleName_1>} <AccountID_2>{,AriaHubRoleName}{,<RootRoleName_2>} where AriaHubRoleName is optional but must be specified to allow the Hub UI to gather cost and metrics data, and RootRoleName_1 is optional'
readonly MAXIMUM_NUMBER_OF_ARGUMENTS=100
readonly AWS_DEFAULT_ROOT_ROLE="OrganizationAccountAccessRole"
readonly DEFAULT_ARIA_HUB_ROLE_NAME="AriaSecurityAudit"
readonly VERSION=1
readonly VSS_QUEUE_ARN="arn:aws:sqs:us-west-2:910887748405:cloudcoreo-events-queue"
readonly VSS_TOPIC_NAME="cloudcoreo-events"
readonly VSS_MONITORING_RULE="cloudcoreo-events"
readonly VSS_TOPIC_ENCRYPTION_KEY_NAME="cloudcoreo-events"
readonly STACK=cloudcoreo-events
readonly TEMPLATE_URL="https://s3.amazonaws.com/cloudcoreo-files/devtime/devtime_cfn.yml"


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
function validate_environment(){
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
function extract_input_arguments() {
  local index=0

  # Check if arguments are more than the limit
  if [ "$#" -gt $MAXIMUM_NUMBER_OF_ARGUMENTS ]; then
    log "${_COLOR_RED}ERROR:${_COLOR_RESET} Number of input arguments exceeds the limit of ${MAXIMUM_NUMBER_OF_ARGUMENTS}"
    exit 1
  fi

  # Extract arguments
  for tuple in "$@"; do
    index=${index}+1

    IFS=, read acc_id hub_role root_role <<< "$tuple"

    if [ -z "${acc_id}" ]; then
      log "${_COLOR_RED}ERROR:${_COLOR_RESET} on $index argument with value $var\nThe arguments <AccountID_1>,<HubRoleName>,<RootRoleName_1> are required. $COMMAND_USAGE"
      exit 1
    fi

    if [ -z "${root_role}" ]; then
      root_role="${AWS_DEFAULT_ROOT_ROLE}"
    fi

    if [ -z "${hub_role}" ]; then
	hub_role="${DEFAULT_ARIA_HUB_ROLE_NAME}"
    fi

    ACCOUNTS_INFO_ARRAY+=("$acc_id,$hub_role,$root_role")

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
function assume_role() {
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
function vss_onboard_accounts() {

  for account in "${ACCOUNTS_INFO_ARRAY[@]}";  do
    IFS=, read acc_id hub_role root_role <<< "$account"

    # Skip assume role for root account
    if [ "${acc_id}" != "${ROOT_ACCOUNT}" ]; then
      assume_role "${acc_id}" "${root_role}"
    fi

    if { [ -z "${AWS_ACCESS_KEY_ID}" ] || [ -z "${AWS_SECRET_ACCESS_KEY}" ] || [ -z "${AWS_SESSION_TOKEN}" ]; } && [ "${acc_id}" != "${ROOT_ACCOUNT}" ]; then
      log "${_COLOR_MAGENTA}WARNING: ${_COLOR_RESET}Account $acc_id is skipped, due to error when fetching credentials"
      fail_account "$account"
    else
      onboard_account "${acc_id}" "${hub_role}"
      if [ ! $? -eq 0 ]; then
        log "${_COLOR_RED}ERROR:${_COLOR_RESET} Account Onboarding process for $account failed."
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
function onboard_account() {
  local acc_id_param=$1
  local hub_role_param=${2:-}

  log  "${_COLOR_GREEN}INFO:${_COLOR_RESET} Starting onboarding process for account ${acc_id_param} "

  # Refresh Enabled Regions for account
  if ! refresh_enabled_regions "${acc_id_param}"; then
    log "${_COLOR_RED}ERROR:${_COLOR_RESET} Getting regions for ${acc_id_param} failed."
    return 1
  fi

  # Check if there is a multi-region trail
  # IMPORTANT: if there is a multi-region trail, it will be taken and all others will be omitted. Account holder, needs to
  # ensure it is enabled. If it is disabled, it should be deleted.
  cloud_trail_region=$(aws cloudtrail describe-trails --output json --query "trailList[*][IsMultiRegionTrail, HomeRegion]")
  has_multi_region=$(echo "${cloud_trail_region}" | grep true)
  if [ -n "${has_multi_region}" ]; then
    home_region=$(echo "$cloud_trail_region" | grep -o -m 1 "[[:alpha:]]\+\-[[:alpha:]]\+\-[0-9]")
    if [ -z "${home_region}" ]; then
      log "${_COLOR_RED}ERROR:${_COLOR_RESET} Unable to extract region for MultiRegionTrail: ${cloud_trail_region}."
      return 1
    fi
    log  "${_COLOR_GREEN}INFO:${_COLOR_RESET} Account ${acc_id_param} has a MultiRegionTrail with HomeRegion: ${home_region}"
  else
    log  "${_COLOR_RED}WARNING:${_COLOR_RESET} Account ${acc_id_param} doesn't have a MultiRegionTrail"
  fi

  region_count=0
  for region in "${ENABLED_REGIONS[@]}";  do
    region_count=$((region_count + 1))
    ## run this only one time on the first region since IAM is global  
    if [ "$region_count" == "1" ]; then
	add_extra_hub_policies "${acc_id_param}" "${hub_role_param}"
    fi
    install_cf_stack "${acc_id_param}" "${region}" "${home_region}" &
  done
  wait
}

GuardrailsInventoryPermissions=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "budgets:DescribeBudgetAction",
                "budgets:ViewBudget",
                "ce:DescribeCostCategoryDefinition",
                "ce:GetAnomalyMonitors",
                "ce:GetAnomalySubscriptions",
                "ce:GetCostCategories",
                "ce:ListCostCategoryDefinitions",
                "cloudtrail:DescribeTrails",
                "cloudtrail:GetEventSelectors",
                "cloudtrail:GetInsightSelectors",
                "cloudtrail:GetTrail",
                "cloudtrail:GetTrailStatus",
                "cloudtrail:ListTags",
                "cloudtrail:ListTrails",
                "cloudwatch:DescribeAlarms",
                "cloudwatch:GetMetricData",
                "cloudwatch:ListTagsForResource",
                "config:DescribeConfigRules",
                "config:DescribeConfigurationRecorderStatus",
                "config:DescribeConfigurationRecorders",
                "config:DescribeDeliveryChannels",
                "config:GetComplianceDetailsByConfigRule",
                "config:ListDiscoveredResources",
                "config:ListTagsForResource",
                "ec2:DescribeAddresses",
                "ec2:DescribeAvailabilityZones",
                "ec2:DescribeInstanceAttribute",
                "ec2:DescribeInstanceStatus",
                "ec2:DescribeInstanceTypes",
                "ec2:DescribeInstances",
                "ec2:DescribeImages",
                "ec2:DescribeInternetGateways",
                "ec2:DescribeLaunchTemplateVersions",
                "ec2:DescribeLaunchTemplates",
                "ec2:DescribeNetworkAcls",
                "ec2:DescribeNetworkInterfaces",
                "ec2:DescribeRouteTables",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeSnapshots",
                "ec2:DescribeSubnets",
                "ec2:DescribeVolumes",
                "ec2:DescribeVpcAttribute",
                "ec2:DescribeVpcs",
                "ec2:GetConsoleOutput",
                "ecs:ListClusters",
                "eks:AccessKubernetesApi",
                "eks:DescribeAddonVersions",
                "eks:DescribeCluster",
                "eks:DescribeNodegroup",
                "eks:ListAddons",
                "eks:ListClusters",
                "eks:ListFargateProfiles",
                "eks:ListIdentityProviderConfigs",
                "eks:ListNodegroups",
                "events:DescribeRule",
                "events:ListRules",
                "events:ListTagsForResource",
                "events:ListTargetsByRule",
                "guardduty:GetDetector",
                "guardduty:ListDetectors",
                "iam:GetAccountPasswordPolicy",
                "iam:GetAccountSummary",
                "iam:GetInstanceProfile",
                "iam:GetPolicy",
                "iam:GetPolicyVersion",
                "iam:GetRole",
                "iam:GetRolePolicy",
                "iam:GetServiceLinkedRoleDeletionStatus",
                "iam:GetUser",
                "iam:ListAttachedRolePolicies",
                "iam:ListAttachedUserPolicies",
                "iam:ListInstanceProfilesForRole",
                "iam:ListPolicies",
                "iam:ListPolicyTags",
                "iam:ListRolePolicies",
                "iam:ListRoleTags",
                "iam:ListRoles",
                "iam:ListUsers",
                "iam:PassRole",
                "kms:DescribeKey",
                "kms:GetKeyPolicy",
                "kms:GetKeyRotationStatus",
                "kms:ListAliases",
                "kms:ListKeys",
                "kms:ListResourceTags",
                "logs:DescribeLogGroups",
                "logs:ListTagsLogGroup",
                "s3:GetReplicationConfiguration",
                "s3:GetBucketVersioning",
                "s3:GetEncryptionConfiguration",
                "s3:GetAccountPublicAccessBlock",
                "s3:GetBucketAcl",
                "s3:GetBucketLocation",
                "s3:GetBucketObjectLockConfiguration",
                "s3:GetBucketOwnershipControls",
                "s3:GetBucketPolicy",
                "s3:GetBucketPolicyStatus",
                "s3:GetBucketPublicAccessBlock",
                "s3:GetBucketTagging",
                "s3:GetBucketWebsite",
                "s3:GetLifecycleConfiguration",
                "s3:GetStorageLensConfiguration",
                "s3:ListAccessPoints",
                "s3:ListAllMyBuckets",
                "s3:ListBucket",
                "s3:ListBucketVersions",
                "s3:ListMultiRegionAccessPoints",
                "sns:GetSubscriptionAttributes",
                "sns:GetTopicAttributes",
                "sns:ListSubscriptions",
                "sns:ListTagsForResource",
                "sns:ListTopics",
                "sns:ListSubscriptionsByTopic",
                "sts:AssumeRole",
                "wafv2:AssociateWebACL",
                "wafv2:GetIPSet",
                "wafv2:GetWebACL",
                "wafv2:GetWebACLForResource",
                "wafv2:ListIPSets",
                "wafv2:ListResourcesForWebACL",
                "wafv2:ListTagsForResource",
                "wafv2:ListWebACLs",
                "organizations:DescribeAccount",
                "organizations:DescribeCreateAccountStatus",
                "organizations:DescribeEffectivePolicy",
                "organizations:DescribeOrganization",
                "organizations:DescribeOrganizationalUnit",
                "organizations:DescribePolicy",
                "organizations:ListAWSServiceAccessForOrganization",
                "organizations:ListAccounts",
                "organizations:ListOrganizationalUnitsForParent",
                "organizations:ListParents",
                "organizations:ListPolicies",
                "organizations:ListPoliciesForTarget",
                "organizations:ListRoots",
                "organizations:ListTagsForResource",
                "organizations:ListTargetsForPolicy"
            ],
            "Resource": "*"
        }
    ]
}
EOF
		     )

AriaHubGetCostingData=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ce:GetCostAndUsage",
                "ce:GetCostForecast"
            ],
            "Resource": "*"
        }
    ]
}
EOF
		     )

AriaHubListCloudwatchMetrics=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "cloudwatch:GetMetricData",
                "cloudwatch:ListMetrics"
            ],
            "Resource": "*"
        }
    ]
}
EOF
			       )

function add_extra_hub_policies(){
    local acc_id_param=$1
    local hub_role_param=$2

    if [ "x${hub_role_param}" == "x" ]; then
	log "${_COLOR_RED}WARNING:${_COLOR_RESET} Hub Role not specified - skipping additional hub functionality enablement"
	return 0
    fi

    listMetricsPolicyName="AriaHubListCloudwatchMetrics"
    getCostDataPolicyName="AriaHubGetCostingData"
    guardrailsInventoryPolicyName="GuardrailsInventoryPermissions"
    
    role=$(aws iam list-attached-role-policies --role-name "${hub_role_param}")

    for policy_name in "${listMetricsPolicyName}" "${getCostDataPolicyName}" "${guardrailsInventoryPolicyName}"; do
	echo "ensuring policy exists: ${policy_name}"
        ## the policy is not listed - need to add it
        create_or_update_policy "${acc_id_param}" "${policy_name}"
	if ! echo $role | grep -q "${policy_name}"; then
	    attach_policy_to_role "${acc_id_param}" "${hub_role_param}" "${policy_name}"
	fi
    done
}

function create_or_update_policy(){
    local acct_id_param=$1
    local policy_name_param=$2
    if echo $(aws iam get-policy --policy-arn "arn:aws:iam::${acct_id_param}:policy/${policy_name_param}" 2>&1) | grep -q "not found"; then
	new_policy=$(aws iam create-policy --policy-name "${policy_name_param}" --policy-document "$(eval echo '$'${policy_name_param})")
	if ! echo "$?" | grep -q "0"; then
	    log "${_COLOR_RED}ERROR:${_COLOR_RESET} Account Onboarding process for ${acc_id_param} failed."
	    return 1
	fi
    else
	## delete the old policy version now
	old_policy_versions=$(aws iam list-policy-versions --policy-arn "arn:aws:iam::${acct_id_param}:policy/${policy_name_param}" --query 'Versions[?IsDefaultVersion==`false`].VersionId[]' --output text)
	for pv in $old_policy_versions; do
	    echo "deleteing old pv: $pv"
	    pv_delete=$(aws iam delete-policy-version --policy-arn "arn:aws:iam::${acct_id_param}:policy/${policy_name_param}" --version-id "${pv}")
	    if ! echo "$?" | grep -q "0"; then
		log "${_COLOR_RED}ERROR:${_COLOR_RESET} couldnt delete obsolete policy version."
		return 1
	    fi
	done
	echo "existing policy: ${policy_name_param}"
	new_policy_version=$(aws iam create-policy-version --set-as-default --policy-arn "arn:aws:iam::${acct_id_param}:policy/${policy_name_param}" --policy-document "$(eval echo '$'${policy_name_param})")
	if ! echo "$?" | grep -q "0"; then
	    log "${_COLOR_RED}ERROR:${_COLOR_RESET} Account Onboarding process for ${acc_id_param} failed."
	    return 1
	fi
    fi
    return 0
}

function attach_policy_to_role(){
    local acct_id_param=$1
    local hub_role_param=$2
    local policy_name_param=$3

    attach_role=$(aws iam attach-role-policy --role-name "${hub_role_param}" --policy-arn "arn:aws:iam::${acct_id_param}:policy/${policy_name_param}")
    if ! echo "$?" | grep -q "0"; then
	log "${_COLOR_RED}ERROR:${_COLOR_RESET} could not attach policy(arn:aws:iam::${acct_id_param}:policy/${policy_name_param}) to role(${hub_role_param})."
	return 1
    fi
    return 0
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
function install_cf_stack(){
  local acc_id_param=$1
  local region_name=$2
  local multi_region_trial_home=$3

  log  "${_COLOR_GREEN}INFO:${_COLOR_RESET} Starting application of cloudformation stack for account ${acc_id_param} in region ${region_name}"

  # Ensure region has cloud trail when missing multi region cloud trail
  if [ -z "${multi_region_trial_home}" ]; then
    check=$(aws cloudtrail describe-trails --region "${region_name}" --output json --query "trailList[].HomeRegion" | grep "${region_name}")
    if [ -z "$check" ]; then
      log "${_COLOR_RED}WARNING:${_COLOR_RESET} Account Onboarding process for account $acc_id_param at region ${region_name} is skipped, as CloudTrail is not enabled for the region."
      return 0
    fi
  fi

  if aws cloudformation describe-stacks --stack-name $STACK --region "${region_name}" >/dev/null 2>&1; then
    log  "${_COLOR_GREEN}INFO:${_COLOR_RESET} Updating stack ${STACK} with version ${VERSION}"
    aws_cloudformation_command="update-stack"
  else
    log  "${_COLOR_GREEN}INFO:${_COLOR_RESET} Creating stack ${STACK} with version ${VERSION}"
    aws_cloudformation_command="create-stack"
  fi

  stack=$(aws cloudformation ${aws_cloudformation_command} \
    --stack-name $STACK \
    --region "${region_name}" \
    --template-url ${TEMPLATE_URL} \
    --parameters \
        ParameterKey=CloudCoreoDevTimeQueueArn,ParameterValue=${VSS_QUEUE_ARN} \
        ParameterKey=CloudCoreoDevTimeTopicName,ParameterValue=${VSS_TOPIC_NAME} \
        ParameterKey=CloudCoreoDevTimeMonitorRule,ParameterValue=${VSS_MONITORING_RULE} \
        ParameterKey=CloudCoreoDevTimeTopicEncryptionKeyName,ParameterValue=${VSS_TOPIC_ENCRYPTION_KEY_NAME} \
    --tags \
        Key=Version,Value=${VERSION} Key=LastUpdatedTime,Value="$(date)")

  if [ $? -eq 0 ]; then
    log  "${_COLOR_GREEN}INFO:${_COLOR_RESET} Successfully applied cloudformation stack for account ${acc_id_param} in region ${region_name}"
    return 0
  else
    log "${_COLOR_RED}ERROR:${_COLOR_RESET} Account Onboarding process for ${acc_id_param} failed."
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
function refresh_enabled_regions(){
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
# List all unsuccessful accounts
# Globals:
#   UNSUCCESSFUL_ACCOUNTS
#######################################
function list_failed_accounts() {
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
function fail_account() {
  UNSUCCESSFUL_ACCOUNTS+=("$1")
}


function log() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
}


#######################################
# Clears all aws creds so that the aws cli uses the ~/.aws/credentials file as source for creds
#######################################
function use_aws_credentials_file() {
  export AWS_ACCESS_KEY_ID=
  export AWS_SECRET_ACCESS_KEY=
  export AWS_SESSION_TOKEN=
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


function main() {
  log "${_COLOR_GREEN}INFO:${_COLOR_RESET} Running for $# accounts."
  validate_environment
  extract_input_arguments "$@"
  get_root_account
  vss_onboard_accounts
  list_failed_accounts
}

main "$@"
