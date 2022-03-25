#!/bin/bash

set -e -o pipefail

# Note script should be idempotent

if command -v xattr &>/dev/null; then
	xattr -d com.apple.quarantine imgpkg kapp kbld ytt 1>/dev/null 2>&1 || true
fi

ns_name=tanzu-cluster-essentials
echo "## Creating namespace $ns_name"
kubectl create ns $ns_name 2>/dev/null || true

echo "## Pulling bundle from $INSTALL_REGISTRY_HOSTNAME (username: $INSTALL_REGISTRY_USERNAME)"

[ -z "$INSTALL_BUNDLE" ]            && { echo "INSTALL_BUNDLE env var must not be empty"; exit 1; }
[ -z "$INSTALL_REGISTRY_HOSTNAME" ] && { echo "INSTALL_REGISTRY_HOSTNAME env var must not be empty"; exit 1; }
[ -z "$INSTALL_REGISTRY_USERNAME" ] && { echo "INSTALL_REGISTRY_USERNAME env var must not be empty"; exit 1; }
[ -z "$INSTALL_REGISTRY_PASSWORD" ] && { echo "INSTALL_REGISTRY_PASSWORD env var must not be empty"; exit 1; }

export IMGPKG_REGISTRY_HOSTNAME_0=$INSTALL_REGISTRY_HOSTNAME
export IMGPKG_REGISTRY_USERNAME_0=$INSTALL_REGISTRY_USERNAME
export IMGPKG_REGISTRY_PASSWORD_0=$INSTALL_REGISTRY_PASSWORD
./imgpkg pull -b $INSTALL_BUNDLE -o ./bundle/

export YTT_registry__server=$INSTALL_REGISTRY_HOSTNAME
export YTT_registry__username=$INSTALL_REGISTRY_USERNAME
export YTT_registry__password=$INSTALL_REGISTRY_PASSWORD

echo "## Deploying kapp-controller"
./ytt -f ./bundle/kapp-controller/config/ -f ./bundle/registry-creds/ --data-values-env YTT --data-value-yaml kappController.deployment.concurrency=10 \
	| ./kbld -f- -f ./bundle/.imgpkg/images.yml \
	| ./kapp deploy -a kapp-controller -n $ns_name -f- --yes

echo "## Deploying secretgen-controller"
./ytt -f ./bundle/secretgen-controller/config/ -f ./bundle/registry-creds/ --data-values-env YTT \
	| ./kbld -f- -f ./bundle/.imgpkg/images.yml \
	| ./kapp deploy -a secretgen-controller -n $ns_name -f- --yes
