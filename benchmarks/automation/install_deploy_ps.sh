#!/bin/bash
echo -e "\033[1m===== Deploying PS using ps_stack.yaml =====\033[0m"

set -e

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "kubectl is not installed. Please install it first."
    exit 1
fi

# Remove existing aibrix directory if it exists
if [ -d "production-stack" ]; then
    echo "Removing existing production-stack directory..."
    rm -rf production-stack
fi

echo "Cloning vLLM production-stack repository..."
git clone https://github.com/vllm-project/production-stack.git

# Deploy the model
echo "Deploying PS from ps_stack.yaml..."
kubectl apply -f ps_stack.yaml

# Wait for the deployment to be ready
echo "Waiting for PS deployment to be ready..."
# kubectl wait --for=condition=available --timeout=300s deployment/deepseek-r1-distill-llama-8b
kubectl wait --for=condition=available --timeout=300s deployment/vllm-deepseek-r1-deployment


echo -e "\033[1m===== Model deployment complete =====\033[0m"
echo -e "You can check the deployment status with: \033[1mkubectl get pods\033[0m"
# echo -e "To view the logs: \033[1mkubectl logs -f deployment/deepseek-r1-distill-llama-8b\033[0m" 
echo -e "To view the logs: \033[1mkubectl logs -f deployment/vllm-deepseek-r1-deployment\033[0m"
