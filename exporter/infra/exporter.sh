#!/bin/bash
# This script collects and print into a ENV file the required vars for the manifest template processing
# WARNING!: This requires an available connection configured by OC CLI


# Print script usage flags
function print_usage() {
  echo "
  $0
    -k: Specifies the KUBECONFIG var to access to the source cluster. (Default: ~/.kube/config)
    -i: Introduces manually the desired cluster ID. (Default: obtained automatically)
    -r: Configures the results config dir. (Default: ./results)
    -h: Prints script's usage
  "
}

# Flags
while getopts 'k:i:r:h' flag; do
  case "${flag}" in
    k) KUBECONFIG="$OPTARG" ;;
    i) CLUSTER_ID="$OPTARG" ;;
    r) RESULTS_DIR="$OPTARG" ;;
    h) print_usage; exit 0 ;;
    *) echo "Error: unvalid flag. Exiting"; print_usage; exit 1 ;;
  esac
done


## Global vars
################################################################################
KUBECONFIG=${KUBECONFIG:-"$HOME/.kube/config"}
CLUSTER_ID=${CLUSTER_ID:-""}
RESULTS_DIR=${RESULTS_DIR:-"./results"}
PREFIX="cloned_"


## Init
################################################################################
echo "Initializing..."

# Configuring "oc CLI"
export KUBECONFIG

# Extracting API address
CLUSTER_API=$(oc cluster-info | \
	# removing color characters
  sed -e 's/\x1b\[[0-9;]*m//g' | \
	# API URL
  sed -r 's/.*is running at (.*)/\1/' | \
  head -1
)
# Check cluster API connection
[[ $? -ne 0 ]] && { echo "Not connected to a cluster. Exiting..."; exit; }

# Results dir creation
[[ ! -d $RESULTS_DIR ]] && { mkdir -p $RESULTS_DIR; }

# If any cluster_id was introduced by args, it will be query to the API
if [[ $CLUSTER_ID == "" ]]; then
  CLUSTER_ID="$(oc get clusterversion -o jsonpath='{.items[].spec.clusterID}{"\n"}')"
fi


## Main
################################################################################
echo "Copying cluster with ID: $CLUSTER_ID at $CLUSTER_API"

echo "Getting Cluster Info..."
export CLUSTER_NAME=$(echo "$PREFIX$CLUSTER_API" | sed -r 's/https:\/\/api.([0-9a-zA-Z\-]*)\.(.*):6443/\1/')
export CLUSTER_BASE_DOMAIN=$(echo "$CLUSTER_API" | sed -r 's/https:\/\/api.([0-9a-zA-Z\-]*)\.(.*):6443/\2/')
export CLUSTER_VERSION=$($OC get clusterversion -o go-template='{{range .items}}{{.status.desired.version}}{{"\n"}}{{end}}')


echo "Getting Infrastructure Info..."
export WORKER_COUNT=$($OC get nodes --selector=node-role.kubernetes.io/worker --no-headers | wc -l | sed 's/ //g')
export CLUSTER_NETWORK=$($OC get network.config/cluster -o go-template='{{range .spec.clusterNetwork}}{{.cidr}}{{"\n"}}{{end}}')
export HOST_PREFIX=$($OC get network.config/cluster -o go-template='{{range .spec.clusterNetwork}}{{.hostPrefix}}{{"\n"}}{{end}}')
export SERVICE_NETWORK=$($OC get network.config/cluster -o go-template='{{range .spec.serviceNetwork}}{{.}}{{"\n"}}{{end}}')
export NETWORK_TYPE=$($OC get network.config/cluster -o go-template='{{.spec.networkType}}')


echo "Getting Registry Info..."
# Don't need to export it because is a internal var
_REGISTRY_ROUTE_NAME="$($OC get routes -n openshift-image-registry -o=jsonpath='{.items[?(@.metadata.annotations.imageregistry\.openshift\.io=="true")].metadata.name}')"
export REGISTRY_ROUTE_HOSTNAME=$($OC get routes $_REGISTRY_ROUTE_NAME -n openshift-image-registry -o go-template='{{.spec.host}}' | sed -r "s/(.*).apps..*/\1.$CLUSTER_NAME.$CLUSTER_BASE_DOMAIN/g")
if [[ "$(echo $REGISTRY_ROUTE_INFO | wc -l)" -ne 0 ]]; then
  export REGISTRY_IS_EXPOSED="true"
else
  export REGISTRY_IS_EXPOSED="false"
fi


echo "Getting Cloud/Bare-Metal Provider Info..."
export PROV_CLOUD_PROVIDER=$($OC get Infrastructure cluster -o go-template='{{.status.platform}}')
if [ ! -z $PROV_CLOUD_PROVIDER ]; then
  export PROV_CLOUD_REGION=$($OC get Infrastructure cluster -o go-template="{{.status.platformStatus.$(echo $PROV_CLOUD_PROVIDER | tr '[:upper:]' '[:lower:]').region}}")
fi

echo "Generating Env var file..."
if [ -z $CLUSTER_ID ]; then
  RESULT_ENV_FILE="$RESULTS_DIR/${CLUSTER_NAME}_${CLUSTER_BASE_DOMAIN}.env"
else
  RESULT_ENV_FILE="$RESULTS_DIR/${CLUSTER_ID}.env"
fi
echo "# ${CLUSTER_NAME}_${CLUSTER_BASE_DOMAIN} Env generated file. Do not edit this file!
export CLUSTER_NAME=\"$CLUSTER_NAME\"
export CLUSTER_BASE_DOMAIN=\"$CLUSTER_BASE_DOMAIN\"
export CLUSTER_VERSION=\"$CLUSTER_VERSION\"
export WORKER_COUNT=\"$WORKER_COUNT\"
export CLUSTER_NETWORK=\"$CLUSTER_NETWORK\"
export HOST_PREFIX=\"$HOST_PREFIX\"
export SERVICE_NETWORK=\"$SERVICE_NETWORK\"
export NETWORK_TYPE=\"$NETWORK_TYPE\"
export REGISTRY_ROUTE_HOSTNAME=\"$REGISTRY_ROUTE_HOSTNAME\"
export REGISTRY_IS_EXPOSED=\"$REGISTRY_IS_EXPOSED\"
export PROV_CLOUD_PROVIDER=\"$PROV_CLOUD_PROVIDER\"
export PROV_CLOUD_REGION=\"$PROV_CLOUD_REGION\"
" > $RESULT_ENV_FILE

echo "Saved to $RESULT_ENV_FILE"

