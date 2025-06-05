#!/bin/bash
echo -e "\033[1;33m===== Stopping AIBrix deployment =====\033[0m"

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

# Delete AIBrix model deployment and service
echo "Cleaning up AIBrix model resources..."
safe_delete "deployment/deepseek-r1-distill-llama-8b"
safe_delete "service/deepseek-r1-distill-llama-8b"

# Delete AIBrix components (reverse order of installation)
echo "Uninstalling AIBrix components..."
if kubectl get namespace aibrix-system >/dev/null 2>&1; then
    kubectl delete -k "github.com/vllm-project/aibrix/config/overlays/release?ref=v0.2.1" --ignore-not-found=true
    kubectl delete -k "github.com/vllm-project/aibrix/config/dependency?ref=v0.2.1" --ignore-not-found=true
else
    echo "AIBrix namespace not found, components already removed"
fi

# Wait for resources to be fully deleted
echo "Waiting for AIBrix resources to be cleaned up..."
kubectl wait --for=delete deployment/deepseek-r1-distill-llama-8b --timeout=60s 2>/dev/null || true
kubectl wait --for=delete namespace/aibrix-system --timeout=60s 2>/dev/null || true

# Clean up local AIBrix directory
if [ -d "aibrix" ]; then
    echo "Removing local aibrix directory..."
    rm -rf aibrix
fi

echo -e "\033[1;32m===== AIBrix deployment stopped successfully =====\033[0m"
echo -e "• Base infrastructure (K8s, Prometheus) is still running"
echo -e "• You can now run 'make install-ps' to switch to ProductionStack"
echo -e "• Or run 'make install-aibrix' to reinstall AIBrix" 