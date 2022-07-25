#!/bin/bash

set -e -o pipefail

# Note script should be idempotent

if [ "$(uname)" == "Darwin" ]; then
	if command -v xattr &>/dev/null; then
		xattr -d com.apple.quarantine imgpkg kapp kbld ytt 1>/dev/null 2>&1 || true
	fi
fi

ns_name=tanzu-cluster-essentials
echo "## Creating namespace $ns_name"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: ${ns_name}
EOF

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
./kapp deploy -a kapp-controller -n $ns_name -f <(./ytt -f ./bundle/kapp-controller/config/ -f ./bundle/registry-creds/ --data-values-env YTT --data-value-yaml kappController.deployment.concurrency=10 | ./kbld -f- -f ./bundle/.imgpkg/images.yml) "$@"

echo "## Deploying secretgen-controller"
./kapp deploy -a secretgen-controller -n $ns_name -f <(./ytt -f ./bundle/secretgen-controller/config/ -f ./bundle/registry-creds/ --data-values-env YTT | ./kbld -f- -f ./bundle/.imgpkg/images.yml) "$@"
