#!/bin/bash
#
# Copyright (c) 2023-2024 VMware Inc. All Rights Reserved.
#

# Default Parameters
COMMAND_USAGE='Usage: sh cloud_account_onboarding_template.sh --endpoint=<endpoint> --project-ids=<project-id1,project-id2,project-id3...>'
TEMPLATE_FILE="gcp-event-bridge.jinja"
DEPLOYMENT_NAME="vmw-securestate-events"
VERSION="1.1.0"
SERVICE_NAME="vmw-securestate"

# Validate gcloud provisioning
# Checks whether gcloud command exists - exit if not
if ! command -v gcloud >/dev/null 2>&1; then
  echo "Please install Google Cloud Command Line Interface: https://cloud.google.com/sdk/install"
  exit 1
fi

for i in "$@"; do
  case $i in
  -e=* | --endpoint=*)
    ENDPOINT="${i#*=}"
    shift
    ;;
  -p=* | --project-ids=*)
    PROJECT_IDS="${i#*=}"
    shift
    ;;
  *)
    echo "$COMMAND_USAGE"
    exit 1
    ;;
  esac
done

if [ -z "$ENDPOINT" ] || [ -z "$PROJECT_IDS" ]; then
  echo "ERROR: Endpoint(--endpoint) and a comma separated list of Project Ids(--project-ids) are required. $COMMAND_USAGE"
  exit 1
fi

PROJECT_IDS=$(echo "$PROJECT_IDS" | tr "," "\n")

for PROJECT_ID in $PROJECT_IDS; do
  # Set project
  echo "Setting event stream for project: $PROJECT_ID"
  gcloud config set project "$PROJECT_ID"

  PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")

  echo "Providing deployment manager service account the permissions for creating logging sink"
  gcloud projects add-iam-policy-binding "$PROJECT_ID" --member serviceAccount:"$PROJECT_NUMBER"@cloudservices.gserviceaccount.com --role roles/logging.configWriter

  echo "Providing deployment manager service account permissions for creating a resource policy so logsink can publish to pubsub topic."
  gcloud projects add-iam-policy-binding "$PROJECT_ID" --member serviceAccount:"$PROJECT_NUMBER"@cloudservices.gserviceaccount.com --role roles/iam.securityAdmin

  echo "Providing pubsub service account permissions to create jwt token for authentication."
  gcloud projects add-iam-policy-binding "$PROJECT_ID" --member serviceAccount:service-"$PROJECT_NUMBER"@gcp-sa-pubsub.iam.gserviceaccount.com --role roles/iam.serviceAccountTokenCreator

  # Enable deployment manager service
  gcloud services enable deploymentmanager.googleapis.com
  if [ $? -ne 0 ]; then
    echo "ERROR: Failed to enable deployment manager service- deploymentmanager.googleapis.com"
    exit 1
  fi

  # Fetch deployment manager template to determine create/update command to be executed.
  RESULT=$(gcloud deployment-manager deployments describe --format="value(deployment.name)" "$DEPLOYMENT_NAME" 2>/dev/null)
  if [ -z "$RESULT" ]; then
    echo "Creating new deployment $DEPLOYMENT_NAME"
    gcloud deployment-manager deployments create "$DEPLOYMENT_NAME" \
      --template "$TEMPLATE_FILE" \
      --properties endpoint:"$ENDPOINT",audience:"$SERVICE_NAME" \
      --automatic-rollback-on-error
  else
    echo "Updating existing deployment $DEPLOYMENT_NAME"
    gcloud deployment-manager deployments update "$DEPLOYMENT_NAME" \
      --template "$TEMPLATE_FILE" \
      --properties endpoint:"$ENDPOINT",audience:"$SERVICE_NAME"
  fi

  if [ $? -ne 0 ]; then
    echo "WARN: Failed to execute deployment manager template for project $PROJECT_ID. Continuing ..."
  else
    # Write a success message to pub sub topic.
    echo "Sending ACK for successful setup of event stream in project: $PROJECT_ID."
    TOPIC_NAME="topic-${DEPLOYMENT_NAME}"
    gcloud pubsub topics publish "$TOPIC_NAME" --message "{ProjectId: $PROJECT_ID, EventStatus: connected}" --attribute "project-id=$PROJECT_ID,vmw-securestate-events=connected"
  fi
done
