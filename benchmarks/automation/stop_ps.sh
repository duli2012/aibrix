#!/bin/bash
echo -e "\033[1;33m===== Stopping ProductionStack deployment =====\033[0m"

set -e

# Function to safely delete resources
safe_delete() {
    local resource=$1
    if kubectl get $resource >/dev/null 2>&1; then
        echo "Deleting $resource..."
        kubectl delete $resource --ignore-not-found=true
    else
        echo "Resource $resource not found, skipping..."
    fi
}

# Delete ProductionStack resources (based on ps_stack.yaml)
echo "Cleaning up ProductionStack resources..."

# Delete deployments
safe_delete "deployment/vllm-deepseek-r1-deployment"
safe_delete "deployment/vllm-deployment-router"

# Delete services
safe_delete "service/deepseek-r1-distill-llama-8b"
safe_delete "service/vllm-engine-service"
safe_delete "service/vllm-router-service"

# Delete RBAC resources
safe_delete "rolebinding/vllm-router-rb"
safe_delete "role/vllm-router-role"
safe_delete "serviceaccount/vllm-router-sa"

# Wait for resources to be fully deleted
echo "Waiting for ProductionStack resources to be cleaned up..."
kubectl wait --for=delete deployment/vllm-deepseek-r1-deployment --timeout=60s 2>/dev/null || true
kubectl wait --for=delete deployment/vllm-deployment-router --timeout=60s 2>/dev/null || true

# Clean up local production-stack directory
if [ -d "production-stack" ]; then
    echo "Removing local production-stack directory..."
    rm -rf production-stack
fi

echo -e "\033[1;32m===== ProductionStack deployment stopped successfully =====\033[0m"
echo -e "• Base infrastructure (K8s, Prometheus) is still running"
echo -e "• You can now run 'make install-aibrix' to switch to AIBrix"
echo -e "• Or run 'make install-ps' to reinstall ProductionStack" 