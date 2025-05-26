#!/usr/bin/env bash
#
# Copyright IBM Corp All Rights Reserved
#
# SPDX-License-Identifier: Apache-2.0
#

# Variables
CLUSTER_NAME="fabric-cluster"
K8S_VERSION="v1.33.0+k3s1"
CONTROL_PLANE_IP="192.168.208.1"
LOCAL_REGISTRY_NAME="fabric-registry"
LOCAL_REGISTRY_PORT="5000"
LOCAL_REGISTRY_INTERFACE="0.0.0.0"
CERT_DIR="/etc/docker/certs"
REGISTRY_CERT="registry.crt"
REGISTRY_KEY="registry.key"
CONTAINER_CLI="docker"
CONTAINER_NAMESPACE=""
FABRIC_VERSION="2.5.11"
FABRIC_CA_VERSION="1.5.15"
COUCHDB_VERSION="3.4.2"
FABRIC_CONTAINER_REGISTRY="hyperledger"
FABRIC_PEER_IMAGE="${FABRIC_CONTAINER_REGISTRY}/fabric-peer:${FABRIC_VERSION}"

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

  for cmd in $CONTAINER_CLI kubectl curl; do
    if ! command -v $cmd > /dev/null; then
      log "ERROR: $cmd is not installed. Please install it."
      exit 1
    fi
  done

  # Check kubectl version
  kubectl_version=$(kubectl version --client 2>&1 | grep 'Client Version' | grep -oE '[0-1]\.[0-9]+\.[0-9]+')
  if [ "$kubectl_version" != "1.33.0" ]; then
    log "ERROR: kubectl version $kubectl_version does not match required 1.33.0."
    exit 1
  fi

  # Check Docker
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

  # Check firewall
  if command -v ufw > /dev/null; then
    ufw status | grep -q "Status: active"
    if [ $? -eq 0 ]; then
      log "WARNING: UFW firewall is active. Ensuring ports 6443, 5000 are open..."
      sudo ufw allow 6443/tcp
      sudo ufw allow 5000/tcp
    fi
  fi

  pop_fn "Prerequisites verified"
}

function generate_registry_certs() {
  push_fn "Generating TLS certificates for registry"

  sudo mkdir -p $CERT_DIR
  sudo openssl req -x509 -newkey rsa:4096 -nodes -days 365 \
    -keyout $CERT_DIR/$REGISTRY_KEY \
    -out $CERT_DIR/$REGISTRY_CERT \
    -subj "/CN=$CONTROL_PLANE_IP" \
    -addext "subjectAltName=IP:$CONTROL_PLANE_IP" >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    log "ERROR: Failed to generate TLS certificates."
    exit 1
  fi

  sudo chmod 600 $CERT_DIR/$REGISTRY_KEY
  sudo chmod 644 $CERT_DIR/$REGISTRY_CERT

  sudo mkdir -p /etc/docker/certs.d/$CONTROL_PLANE_IP:$LOCAL_REGISTRY_PORT
  sudo cp $CERT_DIR/$REGISTRY_CERT /etc/docker/certs.d/$CONTROL_PLANE_IP:$LOCAL_REGISTRY_PORT/ca.crt

  pop_fn
}

function launch_docker_registry() {
  push_fn "Launching container registry \"${LOCAL_REGISTRY_NAME}\" at $CONTROL_PLANE_IP:${LOCAL_REGISTRY_PORT}"

  running="$($CONTAINER_CLI inspect -f '{{.State.Running}}' "${LOCAL_REGISTRY_NAME}" 2>/dev/null || true)"
  if [ "${running}" != 'true' ]; then
    $CONTAINER_CLI run \
      --detach \
      --restart always \
      --name "${LOCAL_REGISTRY_NAME}" \
      --publish "${LOCAL_REGISTRY_INTERFACE}:${LOCAL_REGISTRY_PORT}:5000" \
      -v $CERT_DIR:/certs \
      -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/$REGISTRY_CERT \
      -e REGISTRY_HTTP_TLS_KEY=/certs/$REGISTRY_KEY \
      registry:2 >/dev/null
    if [ $? -ne 0 ]; then
      log "ERROR: Failed to launch registry. Check Docker logs: $CONTAINER_CLI logs $LOCAL_REGISTRY_NAME"
      exit 1
    fi
  fi

  sleep 2
  curl -k https://$CONTROL_PLANE_IP:$LOCAL_REGISTRY_PORT/v2/ >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    log "ERROR: Registry not accessible at https://$CONTROL_PLANE_IP:$LOCAL_REGISTRY_PORT"
    log "Check firewall (port 5000), certificates, or Docker logs: $CONTAINER_CLI logs $LOCAL_REGISTRY_NAME"
    exit 1
  fi

  pop_fn
}

function stop_docker_registry() {
  push_fn "Deleting container registry \"${LOCAL_REGISTRY_NAME}\" at $CONTROL_PLANE_IP:${LOCAL_REGISTRY_PORT}"

  $CONTAINER_CLI kill "${LOCAL_REGISTRY_NAME}" >/dev/null 2>&1 || true
  $CONTAINER_CLI rm "${LOCAL_REGISTRY_NAME}" >/dev/null 2>&1 || true

  pop_fn
}

function push_docker_images() {
  push_fn "Loading docker images to local registry"

  local images=(
    "${FABRIC_CONTAINER_REGISTRY}/fabric-ca:$FABRIC_CA_VERSION"
    "${FABRIC_CONTAINER_REGISTRY}/fabric-orderer:$FABRIC_VERSION"
    "${FABRIC_PEER_IMAGE}"
    "couchdb:$COUCHDB_VERSION"
    "ghcr.io/hyperledger/fabric-rest-sample:latest"
    "redis:6.2.5"
  )

  for image in "${images[@]}"; do
    local target_image
    case "$image" in
      "${FABRIC_CONTAINER_REGISTRY}/fabric-ca:"*)
        target_image="$CONTROL_PLANE_IP:$LOCAL_REGISTRY_PORT/fabric-ca:$FABRIC_CA_VERSION"
        ;;
      "${FABRIC_CONTAINER_REGISTRY}/fabric-orderer:"*)
        target_image="$CONTROL_PLANE_IP:$LOCAL_REGISTRY_PORT/fabric-orderer:$FABRIC_VERSION"
        ;;
      "${FABRIC_PEER_IMAGE}")
        target_image="$CONTROL_PLANE_IP:$LOCAL_REGISTRY_PORT/fabric-peer:$FABRIC_VERSION"
        ;;
      "couchdb:"*)
        target_image="$CONTROL_PLANE_IP:$LOCAL_REGISTRY_PORT/couchdb:$COUCHDB_VERSION"
        ;;
      "ghcr.io/hyperledger/fabric-rest-sample:"*)
        target_image="$CONTROL_PLANE_IP:$LOCAL_REGISTRY_PORT/fabric-rest-sample:latest"
        ;;
      "redis:"*)
        target_image="$CONTROL_PLANE_IP:$LOCAL_REGISTRY_PORT/redis:6.2.5"
        ;;
    esac

    log "Tagging ${CONTAINER_NAMESPACE}${image} to $target_image"
    $CONTAINER_CLI tag "${CONTAINER_NAMESPACE}${image}" "$target_image"
    log "Pushing $target_image"
    $CONTAINER_CLI push "$target_image"
    if [ $? -ne 0 ]; then
      log "ERROR: Failed to push $target_image. Check registry connectivity and certificates."
      exit 1
    fi
  done

  pop_fn
}

function init_control_plane() {
  push_fn "Creating cluster \"${CLUSTER_NAME}\""

  # Check if k3s is already installed
  if [ ! -f /usr/local/bin/k3s ] && [ ! -f /etc/rancher/k3s/k3s.yaml ]; then
    # Remove any existing enrollments
    rm -rf $PWD/build

    # Reset existing k3s if present
    sudo systemctl stop k3s >/dev/null 2>&1 || true
    sudo rm -rf /var/lib/rancher/k3s >/dev/null 2>&1 || true

    # Install k3s
    log "Installing k3s..."
    curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=$K8S_VERSION sh -s - \
      --write-kubeconfig-mode 644 \
      --disable traefik \
      --node-ip $CONTROL_PLANE_IP
    if [ $? -ne 0 ]; then
      log "ERROR: k3s installation failed. Check logs: sudo journalctl -u k3s"
      exit 1
    fi
  else
    log "k3s is already installed, starting service..."
    sudo systemctl start k3s
    if [ $? -ne 0 ]; then
      log "ERROR: Failed to start k3s. Check logs: sudo journalctl -u k3s"
      exit 1
    fi
  fi

  # Start k3s
  sudo systemctl enable k3s

  # Configure kubectl
  mkdir -p $HOME/.kube
  if [ ! -f $HOME/.kube/config ]; then
    sudo cp /etc/rancher/k3s/k3s.yaml $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
    chmod 600 $HOME/.kube/config
  fi
  export KUBECONFIG=$HOME/.kube/config

  # Wait for k3s to be ready
  sleep 5
  kubectl get nodes >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    log "ERROR: Control plane initialization failed. Check k3s logs: sudo journalctl -u k3s"
    exit 1
  fi

  pop_fn
}

function delete_control_plane() {
  push_fn "Deleting cluster ${CLUSTER_NAME}"

  sudo systemctl stop k3s
  log "k3s service stopped. Configuration preserved for reuse."

  pop_fn
}

function generate_join_command() {
  push_fn "Generating join command for worker nodes"

  TOKEN=$(sudo cat /var/lib/rancher/k3s/server/node-token)
  if [ -z "$TOKEN" ]; then
    log "ERROR: Failed to retrieve k3s join token. Check k3s status."
    exit 1
  fi

  JOIN_COMMAND="curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=$K8S_VERSION K3S_URL=https://$CONTROL_PLANE_IP:6443 K3S_TOKEN=$TOKEN sh -"
  echo "$JOIN_COMMAND" > join-cluster.sh
  chmod +x join-cluster.sh
  log "Join command saved to join-cluster.sh. Copy to worker nodes and run it."

  pop_fn
}

function k3s_init() {
  log "Initializing k3s cluster"
  check_prerequisites
  generate_registry_certs
  launch_docker_registry
  push_docker_images
  init_control_plane
  generate_join_command
  sudo cp /etc/docker/certs/registry.crt .
  log "🏁 - Cluster control plane is ready"
}

function k3s_clean() {
  log "Cleaning k3s cluster"
  delete_control_plane
  stop_docker_registry
  rm -f join-cluster.sh $REGISTRY_CERT
  log "🏁 - Cluster is cleaned"
}

function print_help() {
  log "Usage: $0 [init|clean]"
}

function k3s_command_group() {
  if [ "$#" -eq 0 ]; then
    COMMAND="init"
  else
    COMMAND=$1
    shift
  fi

  if [ "${COMMAND}" == "init" ]; then
    k3s_init
  elif [ "${COMMAND}" == "clean" ]; then
    k3s_clean
  else
    print_help
    exit 1
  fi
}

k3s_command_group "$@"