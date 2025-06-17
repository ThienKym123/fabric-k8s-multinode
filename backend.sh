#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0

# Load environment variables
. k8s-setup/envVar.sh

set -e

# Deploy backend pod, service, ingress
deploy_backend() {
  echo "🚀 Deploying backend to namespace ${KUBE_NAMESPACE}..."

  # Ensure namespace exists
  if ! kubectl get namespace ${KUBE_NAMESPACE} &> /dev/null; then
    echo "🔧 Creating namespace ${KUBE_NAMESPACE}..."
    kubectl create namespace ${KUBE_NAMESPACE}
  fi

  # Deploy PVC fabric-wallet (if not exist)
  if ! kubectl get pvc fabric-wallet -n ${KUBE_NAMESPACE} &> /dev/null; then
    echo "📦 Creating PVC fabric-wallet..."
    envsubst < kube/fabric-wallet-pvc.yaml | kubectl apply -f -
  else
    echo "📦 PVC fabric-wallet already exists."
  fi

  # Build Docker image
  echo "🔨 Building backend Docker image..."
  cd backend
  ${CONTAINER_CLI} build -t test-network-backend:latest .
  
  # Push to local registry
  echo "📦 Pushing image to local registry ${CONTROL_PLANE_IP}:${LOCAL_REGISTRY_PORT}..."
  ${CONTAINER_CLI} tag test-network-backend:latest ${CONTROL_PLANE_IP}:${LOCAL_REGISTRY_PORT}/test-network-backend:latest
  ${CONTAINER_CLI} push ${CONTROL_PLANE_IP}:${LOCAL_REGISTRY_PORT}/test-network-backend:latest
  cd ..

  # Deploy backend Deployment + Service + Ingress
  echo "📁 Creating backend deployment, service, and ingress..."

  envsubst < kube/backend-deployment.yaml | kubectl apply -f -
  envsubst < kube/backend-service.yaml | kubectl apply -f -
  envsubst < kube/backend-ingress.yaml | kubectl apply -f -

  # Wait for deployment to become ready
  echo "⏳ Waiting for backend deployment to be ready..."
  kubectl rollout status deployment/backend -n ${KUBE_NAMESPACE} --timeout=120s

  # Wait for pod to be running
  echo "🔍 Ensuring backend pod is running..."
  kubectl wait --for=condition=Ready pod -l app=backend -n ${KUBE_NAMESPACE} --timeout=60s

  echo "✅ Backend deployed successfully!"
  kubectl get pods -n ${KUBE_NAMESPACE} -l app=backend
  kubectl get svc -n ${KUBE_NAMESPACE} -l app=backend
  kubectl get ingress -n ${KUBE_NAMESPACE} -l app=backend

  echo ""
  echo "🌍 Access the backend at: https://backend.${DOMAIN}/health"
  echo "🔁 Example curl:"
  echo "curl -k https://backend.${DOMAIN}/health"
}

# Clean up backend resources
clean_backend() {
  echo "🧹 Cleaning backend deployment, services, ingress..."

  kubectl delete deployment backend -n ${KUBE_NAMESPACE} --ignore-not-found
  kubectl delete svc backend -n ${KUBE_NAMESPACE} --ignore-not-found
  kubectl delete ingress backend-ingress -n ${KUBE_NAMESPACE} --ignore-not-found

  echo "⏳ Waiting for resources to be terminated..."
  kubectl wait --for=delete pod -l app=backend -n ${KUBE_NAMESPACE} --timeout=60s || true
  kubectl wait --for=delete svc/backend -n ${KUBE_NAMESPACE} --timeout=30s || true
  kubectl wait --for=delete ingress/backend-ingress -n ${KUBE_NAMESPACE} --timeout=30s || true
  kubectl delete pvc fabric-wallet -n ${KUBE_NAMESPACE} --ignore-not-found

  echo "🗑 Removing local Docker images..."
  ${CONTAINER_CLI} rmi ${CONTROL_PLANE_IP}:${LOCAL_REGISTRY_PORT}/test-network-backend:latest || true
  ${CONTAINER_CLI} rmi test-network-backend:latest || true

  echo "✅ Backend cleanup completed!"
}
