.PHONY: all clean setup-env setup-k8s setup-prometheus install-aibrix deploy-model benchmark stop-aibrix stop-ps switch-to-aibrix switch-to-ps
all: help

help:
	@echo "Available targets:"
	@echo "  aibrix         - Setup environment, K8s, install AIBrix, and run benchmarks"
	@echo "  ps             - Setup environment, K8s, install ProductionStack, and run benchmarks"
	@echo "  setup-env      - Setup the environment"
	@echo "  setup-k8s      - Setup Kubernetes cluster"
	@echo "  setup-prometheus - Setup Prometheus monitoring"
	@echo "  install-aibrix - Install AIBrix and deploy model"
	@echo "  install-ps     - Install ProductionStack and deploy model"
	@echo "  stop-aibrix    - Stop/uninstall AIBrix (keeps base infrastructure)"
	@echo "  stop-ps        - Stop/uninstall ProductionStack (keeps base infrastructure)"
	@echo "  switch-to-aibrix - Stop PS and start AIBrix (fast switching)"
	@echo "  switch-to-ps   - Stop AIBrix and start PS (fast switching)"
	@echo "  benchmark      - Run benchmarking tests"
	@echo "  clean          - Clean up resources and terminate K8s cluster"

aibrix: setup-env setup-k8s setup-prometheus install-aibrix #benchmark
ps: setup-env setup-k8s setup-prometheus install-ps #benchmark

setup-env:
	@echo "Setting up environment..."
	@chmod +x setup_environment.sh
	@./setup_environment.sh

setup-k8s:
	@echo "Setting up Kubernetes cluster..."
	@chmod +x launch_k8s.sh
	@./launch_k8s.sh

setup-prometheus:
	@echo "Setting up Prometheus monitoring..."
	@chmod +x setup_prometheus.sh
	@./setup_prometheus.sh

install-aibrix:
	@echo "Installing AIBrix..."
	@chmod +x install_aibrix.sh
	@./install_aibrix.sh
	@chmod +x deploy_model.sh
	@./deploy_model.sh

install-ps:
	@echo "Installing ProductonStack..."
	@chmod +x install_deploy_ps.sh
	@./install_deploy_ps.sh

stop-aibrix:
	@echo "Stopping AIBrix deployment..."
	@chmod +x stop_aibrix.sh
	@./stop_aibrix.sh

stop-ps:
	@echo "Stopping ProductionStack deployment..."
	@chmod +x stop_ps.sh
	@./stop_ps.sh

switch-to-aibrix: stop-ps install-aibrix
	@echo "Successfully switched to AIBrix!"

switch-to-ps: stop-aibrix install-ps
	@echo "Successfully switched to ProductionStack!"

benchmark:
	@echo "Running benchmark..."
	@chmod +x benchmarking.sh
	@./benchmarking.sh

clean:
	@echo "Cleaning up..."
	@echo "Terminating Kubernetes cluster..."
	@sky down -y k8s || true
	@rm -rf aibrix
	@rm -rf .venv
	@echo "Cleanup complete" 