#!/usr/bin/bash

set -eux
source utils.sh
source common.sh
source ocp_install_env.sh

# Note This logic will likely run in a container (on the bootstrap VM)
# for the final solution, but for now we'll prototype the workflow here
export OS_TOKEN=fake-token
export OS_URL=http://localhost:6385/

trap collect_info_on_failure TERM

wait_for_json ironic \
    "${OS_URL}/v1/nodes" \
    10 \
    -H "Accept: application/json" -H "Content-Type: application/json" -H "User-Agent: wait-for-json" -H "X-Auth-Token: $OS_TOKEN"
if [ $(sudo podman ps | grep -w -e "ironic$" -e "ironic-inspector$" -e "dnsmasq" -e "httpd" | wc -l) != 4 ] ; then
    echo "Can't find required containers"
    exit 1
fi

mkdir ocp/tf-master
cp ocp/master.ign ocp/tf-master

cat > ocp/tf-master/main.tf <<EOF
provider "ironic" {
  "url" = "http://localhost:6385/v1"
  "microversion" = "1.50"
}
EOF

IMAGE_SOURCE="http://172.22.0.1/images/$RHCOS_IMAGE_FILENAME_LATEST"
IMAGE_CHECKSUM=$(curl http://172.22.0.1/images/$RHCOS_IMAGE_FILENAME_LATEST.md5sum)

ROOT_GB="25"

for i in $(seq 0 2); do
  master_node_to_tf $i $IMAGE_SOURCE $IMAGE_CHECKSUM $ROOT_GB $ROOT_DISK >> ocp/tf-master/main.tf
done

echo "Deploying master nodes"
pushd ocp/tf-master
export TF_LOG=debug
terraform init
terraform apply --auto-approve
popd

echo "Master nodes active"

# Wait for nodes to appear and become ready
until oc get nodes; do sleep 5; done
NUM_NODES=$(oc get nodes -l node-role.kubernetes.io/master -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}' | wc -l)
while [ "$NUM_NODES" -ne 3 ]; do
  sleep 10
  NUM_NODES=$(oc get nodes -l node-role.kubernetes.io/master -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}' | wc -l)
done

# Update kube-system ep/host-etcd used by cluster-kube-apiserver-operator to
# generate storageConfig.urls
patch_ep_host_etcd "$CLUSTER_DOMAIN"

oc wait nodes -l node-role.kubernetes.io/master --for condition=ready --timeout=600s

wait_for_bootstrap_event

# disable NoSchedule taints for masters until we have workers deployed
oc adm taint nodes -l node-role.kubernetes.io/master node-role.kubernetes.io/master:NoSchedule-
oc label node -l node-role.kubernetes.io/master node-role.kubernetes.io/worker=''

#Verify Ingress controller functionality
echo "Verifying Ingress controller functionality, first we'll check that router pod responsive"
until curl -o /dev/null -kLs --fail  tst.apps.${CLUSTER_DOMAIN}:1936/healthz; do sleep 20 && echo "Router pod not responding"; done
echo "Router pod responding, checking connectivity to console via ingress controller"
until wget --no-check-certificate https://console-openshift-console.apps.${CLUSTER_DOMAIN}; do sleep 10 && echo "rechecking"; done
echo "Ingress controller is working!"

echo "Cluster up, you can interact with it via oc --config ${KUBECONFIG} <command>"
