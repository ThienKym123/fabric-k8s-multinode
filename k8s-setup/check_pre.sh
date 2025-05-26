#!/usr/bin/env bash
#
# Copyright IBM Corp All Rights Reserved
#
# SPDX-License-Identifier: Apache-2.0
#

source k8s-setup/utils.sh

function check_prerequisites() {
  local mode="$1"  # 'cluster' or 'kubeadm'
  push_fn "Checking prerequisites for ${mode} setup"

  local CONTAINER_CLI="docker"
  local K8S_VERSION="1.33.0"
  local cmds=("$CONTAINER_CLI" "kubectl")
  if [ "$mode" == "kubeadm" ]; then
    cmds+=("kubeadm" "kubelet" "openssl" "curl")
  fi

  # Check for required commands
  for cmd in "${cmds[@]}"; do
    if ! command -v "$cmd" > /dev/null; then
      log "ERROR: $cmd is not installed. Please install it."
      pop_fn 1
      exit 1
    fi
  done

  # Verify kubectl version
  local kubectl_version
  kubectl_version=$(kubectl version --client 2>&1 | grep 'Client Version' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
  if [ "$kubectl_version" != "$K8S_VERSION" ]; then
    log "ERROR: kubectl version $kubectl_version does not match required $K8S_VERSION."
    pop_fn 1
    exit 1
  fi

  # Verify kubeadm version (if applicable)
  if [ "$mode" == "kubeadm" ]; then
    local kubeadm_version
    kubeadm_version=$(kubeadm version -o short | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    if [ "$kubeadm_version" != "$K8S_VERSION" ]; then
      log "ERROR: kubeadm version $kubeadm_version does not match required $K8S_VERSION."
      pop_fn 1
      exit 1
    fi
  fi

  # Check if container runtime is running
  if ! sudo systemctl is-active "$CONTAINER_CLI" > /dev/null; then
    log "WARNING: $CONTAINER_CLI is not running. Attempting to start..."
    sudo systemctl start "$CONTAINER_CLI"
    sleep 2
    if ! sudo systemctl is-active "$CONTAINER_CLI" > /dev/null; then
      log "ERROR: $CONTAINER_CLI failed to start. Check logs with: sudo journalctl -u $CONTAINER_CLI"
      pop_fn 1
      exit 1
    fi
  fi

  pop_fn 0
}

function check_prerequisites_cluster() {
  check_prerequisites "cluster"
}

function check_prerequisites_kubeadm() {
  check_prerequisites "kubeadm"
}

function check_image_exists() {
  local image="$1"
  local CONTAINER_CLI="docker"
  "$CONTAINER_CLI" image inspect "$image" >/dev/null 2>&1
  return $?
}