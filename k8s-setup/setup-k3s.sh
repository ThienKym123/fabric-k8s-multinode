#!/usr/bin/env bash
#
# Copyright IBM Corp All Rights Reserved
#
# SPDX-License-License-Identifier: Apache-2.0
#

# Variables
CONTROL_PLANE_IP="192.168.208.1"           # IP control-plane server k3s
LOCAL_REGISTRY_PORT="5000"
CERT_DIR="/etc/docker/certs.d/$CONTROL_PLANE_IP:$LOCAL_REGISTRY_PORT"
REGISTRY_CERT="registry.crt"
CONTAINER_CLI="docker"

# **QUAN TRỌNG**: Thay token k3s này bằng token thực lấy từ server control-plane
K3S_TOKEN="YOUR_K3S_CLUSTER_TOKEN_HERE"

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

  # Kiểm tra k3s agent binary
  if ! command -v k3s > /dev/null; then
    log "ERROR: k3s binary not found. Please install k3s agent."
    exit 1
  fi

  # Kiểm tra docker hoặc containerd (tùy môi trường)
  if ! systemctl is-active --quiet $CONTAINER_CLI; then
    log "WARNING: $CONTAINER_CLI is not running. Attempting to start..."
    sudo systemctl start $CONTAINER_CLI
    sleep 2
    if ! systemctl is-active --quiet $CONTAINER_CLI; then
      log "ERROR: $CONTAINER_CLI failed to start. Check logs with: sudo journalctl -u $CONTAINER_CLI"
      exit 1
    fi
  fi

  pop_fn "Prerequisites verified"
}

function install_registry_cert() {
  push_fn "Installing registry certificate"

  if [ ! -f "$REGISTRY_CERT" ]; then
    log "ERROR: $REGISTRY_CERT not found. Copy it from control plane if needed."
    exit 1
  fi

  sudo mkdir -p $CERT_DIR
  sudo cp $REGISTRY_CERT $CERT_DIR/ca.crt
  sudo chmod 644 $CERT_DIR/ca.crt
  sudo systemctl restart $CONTAINER_CLI
  sleep 2
  if ! systemctl is-active --quiet $CONTAINER_CLI; then
    log "ERROR: $CONTAINER_CLI failed to restart after installing certificate."
    exit 1
  fi

  pop_fn
}

function join_cluster() {
  push_fn "Joining k3s worker node to cluster"

  if [ -z "$K3S_TOKEN" ]; then
    log "ERROR: K3S_TOKEN is not set. Please set your k3s cluster token."
    exit 1
  fi

  # Stop k3s-agent if running (clean start)
  sudo systemctl stop k3s-agent 2>/dev/null || true
  sudo killall k3s-agent 2>/dev/null || true

  # Start k3s agent to join cluster
  sudo k3s agent --server https://$CONTROL_PLANE_IP:6443 --token $K3S_TOKEN &
  sleep 5

  if ! pgrep -f "k3s agent" > /dev/null; then
    log "ERROR: k3s agent failed to start and join cluster."
    exit 1
  fi

  pop_fn
}

function cluster_clean() {
  push_fn "Cleaning k3s worker node"

  sudo systemctl stop k3s-agent 2>/dev/null || true
  sudo killall k3s-agent 2>/dev/null || true

  # Xóa data k3s agent
  sudo rm -rf /etc/rancher/k3s /var/lib/rancher/k3s $CERT_DIR

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
    log "🏁 Worker node joined k3s cluster."
  elif [ "${COMMAND}" == "clean" ]; then
    check_prerequisites
    cluster_clean
    log "🏁 Worker node cleaned."
  else
    log "Usage: $0 [init|clean]"
    exit 1
  fi
}

cluster_command_group "$@"
