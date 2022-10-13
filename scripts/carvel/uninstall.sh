#!/bin/bash

set -e -o pipefail

# Note script should be idempotent

if [ "$(uname)" == "Darwin" ]; then
	if command -v xattr &>/dev/null; then
		xattr -d com.apple.quarantine imgpkg kapp kbld ytt 1>/dev/null 2>&1 || true
	fi
fi

ns_name=tanzu-cluster-essentials

echo "## Deleting kapp-controller"
./kapp delete -a kapp-controller -n $ns_name "$@"

echo "## Deleting secretgen-controller"
./kapp delete -a secretgen-controller -n $ns_name "$@"

echo "## Keeping namespace '${ns_name}'"
