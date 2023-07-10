#!/bin/bash
# Copyright (c) 2023-2024 VMware Inc.
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



readonly COMMAND_USAGE='Usage: bash gcp_single_project_onboarding.sh  <ProjectID>'
readonly MAXIMUM_NUMBER_OF_ARGUMENTS=1
readonly custom_role_id='vmwareSecureStateRole'
readonly vss_service_account='vmware-secure-state-account'
declare -a PROJECT_INFO


readonly _COLOR_GREEN=`tput setaf 2`
readonly _COLOR_RED=`tput setaf 1`
readonly _COLOR_YELLOW=`tput setaf 3`
readonly _COLOR_MAGENTA=`tput setaf 5`
readonly _COLOR_RESET=`tput sgr0`
readonly I=${_COLOR_GREEN}INFO:${_COLOR_RESET}
readonly W=${_COLOR_YELLOW}WARNING:${_COLOR_RESET}
readonly E=${_COLOR_RED}ERROR:${_COLOR_RESET}

#######################################
# Validates environment in which script is run.
# Returns:
#   0 if ok, non-zero on error.
#######################################
function validate_environment(){
  # Checks whether gcp command exists - exit if not
  if ! command -v gcloud >/dev/null 2>&1
  then
    echo "${_COLOR_RED}ERROR:${_COLOR_RESET} Please install gcloud Command Line Interface first: https://cloud.google.com/sdk/docs/install"
    exit 1
  fi
}

#######################################
# Validates and extracts inputs of script
# Arguments:
#   String entries: <Project_1>
# Outputs:
#   non-zero on error.
#######################################
function extract_input_arguments() {
  # Check if arguments are more than the limit
  if [ "$#" -lt 1 ]; then
    echo "$E Number of input arguments is 0 please provide input arguments. $COMMAND_USAGE "
    exit 1
  fi

  # Check if arguments are more than the limit
  if [ "$#" -gt $MAXIMUM_NUMBER_OF_ARGUMENTS ]; then
    echo "$E Number of input arguments exceeds the limit of ${MAXIMUM_NUMBER_OF_ARGUMENTS}"
    exit 1
  fi

  # Extract arguments
  for proj in "$@"; do
    PROJECT_INFO+=("$proj")
  done
}

#######################################
# GCP onboarding steps
# Arguments:
#   String entries: <Project_1>
# Outputs:
#   non-zero on error.
#######################################
function vss_gcp_onboard() {
  local proj_id=$1
  echo "$I Start onboarding $proj_id project"
  gcloud config set project $proj_id  && l_ok=OK || l_ok=""
  if [ -z "$l_ok" ]; then
    echo "$E Failed when set project $proj_id"
    return 1
   fi

  echo "$I Going to Enable the GCP APIs for service monitoring"
  gcloud services enable appengine.googleapis.com bigquery.googleapis.com bigtable.googleapis.com cloudapis.googleapis.com cloudasset.googleapis.com cloudfunctions.googleapis.com dataflow.googleapis.com dns.googleapis.com dataproc.googleapis.com cloudresourcemanager.googleapis.com cloudkms.googleapis.com sqladmin.googleapis.com compute.googleapis.com storage-component.googleapis.com recommender.googleapis.com iam.googleapis.com container.googleapis.com monitoring.googleapis.com logging.googleapis.com containerthreatdetection.googleapis.com && l_ok=OK || l_ok=""
  if [ -z "$l_ok" ]; then
    echo "$E Failed when try Enable the GCP APIs for service monitoring for project $proj_id"
    return 1
   fi

  echo "$I Going to create the required custom role vmwareSecureStateRole in the project"
  command="create"
  role_name=$(gcloud iam roles describe --format="value(name)" $custom_role_id --project=$proj_id 2> /dev/null)
  if [ ! -z "$role_name" ];
  then
    gcloud iam roles undelete "$custom_role_id" --project=$proj_id > /dev/null 2>&1
    command="update"
  fi

  gcloud iam roles $command "$custom_role_id" --project=$proj_id --title="VMware Secure State Viewer" --description="Custom role including additional read permissions required for Secure state." --permissions=storage.buckets.get --stage=GA  && l_ok=OK || l_ok=""
    if [ -z "$l_ok" ]; then
      echo "$E Failed when create the required custom role VMware Secure State Viewer in the project $proj_id"
      return 1
    fi

  serviceAccName=$vss_service_account@$proj_id.iam.gserviceaccount.com
  echo "$I Going to create a serviceAccount:$serviceAccName in the project"
    gcloud iam service-accounts describe $serviceAccName && l_ok=OK || l_ok=""
    if [ -z "$l_ok" ];
    then
       echo "$I Going to CREATED"
        gcloud iam service-accounts create "$vss_service_account" --project=$proj_id  && l_ok=OK || l_ok=""
              if [ -z "$l_ok" ]; then
                echo "$E Failed when create a service account in the project $proj_id"
                return 1
              fi
    fi



  echo "$I Going to add-iam-policy-binding to serviceAccount with roles[vmwareSecureStateRole; viewer; iam.securityReviewer]"
  gcloud projects add-iam-policy-binding $proj_id --member serviceAccount:$serviceAccName --role projects/$proj_id/roles/vmwareSecureStateRole && l_ok=OK || l_ok=""
    if [ -z "$l_ok" ]; then
      echo "$E Failed when add-iam-policy-binding to serviceAccount with roles projects/$proj_id/roles/vmwareSecureStateRole"
      return 1
     fi
  gcloud projects add-iam-policy-binding $proj_id --member serviceAccount:$serviceAccName --role roles/viewer && l_ok=OK || l_ok=""
    if [ -z "$l_ok" ]; then
      echo "$E Failed when add-iam-policy-binding to serviceAccount with roles roles/viewer"
      return 1
     fi
  gcloud projects add-iam-policy-binding $proj_id --member serviceAccount:$serviceAccName --role roles/iam.securityReviewer && l_ok=OK || l_ok=""
    if [ -z "$l_ok" ]; then
      echo "$E Failed when add-iam-policy-binding to serviceAccount with roles roles/iam.securityReviewer"
      return 1
     fi

  echo "$I Going to create the service account key file"
  gcloud iam service-accounts keys create --iam-account vmware-secure-state-account@$proj_id.iam.gserviceaccount.com vmw-aria-sa-key.json && l_ok=OK || l_ok=""
      if [ -z "$l_ok" ]; then
        echo "$E Failed when create the service account key file for $proj_id"
        return 1
      fi

  echo "$I${_COLOR_GREEN}Project $proj_id  was onboarded${_COLOR_RESET}"
}


#######################################
# Starts the process for vss_proj_onboard
# Globals:
#   PROJECT_INFO
#######################################
function vss_proj_onboard() {
  for proj in "${PROJECT_INFO[@]}"; do
    vss_gcp_onboard $proj &
  done
  wait
}

function main() {
  validate_environment
  echo "$I Running onboarding for $# GCP project."
  extract_input_arguments "$@"
  vss_proj_onboard
}

main "$@"
