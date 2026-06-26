#!/bin/bash
set -ex

/etc/eks/bootstrap.sh "${cluster_name}" \
  --b64-cluster-ca "${cluster_ca}" \
  --apiserver-endpoint "${cluster_endpoint}" \
  --kubelet-extra-args "--node-labels=${node_labels} --register-with-taints=${node_taints}"
