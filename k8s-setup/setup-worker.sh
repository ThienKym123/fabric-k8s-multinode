#!/usr/bin/env bash
#
# Copyright IBM Corp All Rights Reserved
#
# SPDX-License-License-Identifier: Apache-2.0
#

# Variables
K8S_VERSION="1.33.0"
CONTROL_PLANE_IP="192.168.208.1"
LOCAL_REGISTRY_PORT="5000"
CERT_DIR="/etc/docker/certs.d/$CONTROL_PLANE_IP:$LOCAL_REGISTRY_PORT"
REGISTRY_CERT="registry.crt"
CONTAINER_CLI="docker"

function log() {
  echo "[$(date +%Y-%m-%d\ %H:%M:%S)] $@"
}

function push_fn() {
  log "Starting: $@"
}

function pop_fn() {
  log "Completed: $@"
}

function check_prerequisites() {
  push_fn "Checking prerequisites"

  for cmd in $CONTAINER_CLI kubeadm kubelet; do
    if ! command -v $cmd > /dev/null; then
      log "ERROR: $cmd is not installed. Please install it."
      exit 1
    fi
  done

  kubeadm_version=$(kubeadm version -o short | grep -oE '[0-1]\.[0-9]+\.[0-9]+')
  if [ "$kubeadm_version" != "1.33.0" ]; then
    log "ERROR: kubeadm version $kubeadm_version does not match required $K8S_VERSION."
    exit 1
  fi

  sudo systemctl is-active $CONTAINER_CLI > /dev/null
  if [ $? -ne 0 ]; then
    log "WARNING: $CONTAINER_CLI is not running. Attempting to start..."
    sudo systemctl start $CONTAINER_CLI
    sleep 2
    sudo systemctl is-active $CONTAINER_CLI > /dev/null
    if [ $? -ne 0 ]; then
      log "ERROR: $CONTAINER_CLI failed to start. Check logs with: sudo journalctl -u $CONTAINER_CLI"
      exit 1
    fi
  fi

  sudo swapoff -a
  sudo sed -i '/ swap / s/^/#/' /etc/fstab

  pop_fn "Prerequisites verified"
}

function install_registry_cert() {
  push_fn "Installing registry certificate"

  if [ ! -f "$REGISTRY_CERT" ]; then
    log "ERROR: $REGISTRY_CERT not found. Copy it from control plane."
    exit 1
  fi

  # Install for Docker
  sudo mkdir -p "$CERT_DIR"
  sudo cp "$REGISTRY_CERT" "$CERT_DIR/ca.crt"
  sudo chmod 644 "$CERT_DIR/ca.crt"

  # Install for system-wide trust (Kubelet)
  sudo mkdir -p /usr/local/share/ca-certificates/registry
  sudo cp "$REGISTRY_CERT" /usr/local/share/ca-certificates/registry/registry.crt
  sudo update-ca-certificates
  if [ $? -ne 0 ]; then
    log "ERROR: Failed to update CA certificates."
    exit 1
  fi

  if ! grep -Fx "registry/registry.crt" /etc/ca-certificates.conf >/dev/null; then
    echo "registry/registry.crt" | sudo tee -a /etc/ca-certificates.conf
  fi

  sudo update-ca-certificates
  if [ $? -ne 0 ]; then
    log "ERROR: Failed to update CA certificates."
    exit 1
  fi
  

  # Restart services
  sudo systemctl restart $CONTAINER_CLI
  sleep 2
  sudo systemctl is-active $CONTAINER_CLI > /dev/null
  if [ $? -ne 0 ]; then
    log "ERROR: $CONTAINER_CLI failed to restart after installing certificate."
    exit 1
  fi

  pop_fn
}

function join_cluster() {
  push_fn "Joining cluster"

  if [ ! -f join-cluster.sh ]; then
    log "ERROR: join-cluster.sh not found. Copy it from control plane."
    exit 1
  fi

  sudo bash join-cluster.sh >/dev/null
  if [ $? -ne 0 ]; then
    log "ERROR: Failed to join cluster. Check join-cluster.sh or control plane status."
    exit 1
  fi

  pop_fn
}

function cluster_clean() {
  push_fn "Cleaning worker node"

  sudo kubeadm reset -f >/dev/null
  sudo rm -rf /etc/kubernetes /var/lib/kubelet $CERT_DIR

  sudo ip link delete cni0 || true
  sudo ip link delete flannel.1 || true
  sudo rm -rf /var/lib/cni/ /run/flannel/ /etc/cni/net.d/*
  
  pop_fn
}

function restart_node() {
  push_fn "Restarting node services"

  # Ensure kubelet and container runtime are running
  sudo systemctl restart $CONTAINER_CLI
  sudo systemctl enable kubelet --now
  sudo systemctl restart kubelet

  sleep 3

  if ! systemctl is-active --quiet kubelet; then
    log "ERROR: kubelet is not running after restart."
    exit 1
  fi

  log "Node services restarted successfully."
  pop_fn
}


function cluster_command_group() {
  if [ "$#" -eq 0 ]; then
    COMMAND="init"
  else
    COMMAND=$1
    shift
  fi

  if [ "${COMMAND}" == "init" ]; then
    check_prerequisites
    install_registry_cert
    join_cluster
    log "🏁 Worker node joined cluster."
  elif [ "${COMMAND}" == "clean" ]; then
    check_prerequisites
    cluster_clean
    log "🏁 Worker node cleaned."
  elif [ "${COMMAND}" == "restart" ]; then
    check_prerequisites
    restart_node
    log "🏁 Node restarted successfully."  
  else
    log "Usage: $0 [init|clean|restart]"
    exit 1
  fi
}

cluster_command_group "$@"