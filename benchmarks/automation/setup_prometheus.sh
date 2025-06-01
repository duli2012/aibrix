#!/bin/bash

set -e  # Exit on error

# Clean up any existing installation
echo "Cleaning up any existing installation..."
kubectl delete namespace kube-prometheus-stack --force --grace-period=0 2>/dev/null || true
pkill -f "kubectl port-forward" 2>/dev/null || true
sleep 5

# Install kube-prometheus-stack
echo "Installing kube-prometheus-stack"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Create namespace first
echo "Creating kube-prometheus-stack namespace..."
kubectl create namespace kube-prometheus-stack

# Install kube-prometheus-stack with custom configuration
echo "Installing kube-prometheus-stack Helm chart..."
helm install kube-prometheus-stack \
  --namespace kube-prometheus-stack \
  --set prometheus.configMapOverrideName=prometheus-config \
  --set prometheus.prometheusSpec.volumes[0].name=prometheus-logs \
  --set prometheus.prometheusSpec.volumes[0].persistentVolumeClaim.claimName=prometheus-logs \
  --set prometheus.prometheusSpec.volumeMounts[0].name=prometheus-logs \
  --set prometheus.prometheusSpec.volumeMounts[0].mountPath=/var/log/prometheus \
  --set prometheus.prometheusSpec.volumeMounts[0].subPath=logs \
  --set prometheus.prometheusSpec.securityContext.fsGroup=2000 \
  --set prometheus.prometheusSpec.securityContext.runAsUser=65534 \
  --set prometheus.prometheusSpec.securityContext.runAsGroup=2000 \
  --set prometheus.prometheusSpec.securityContext.runAsNonRoot=true \
  --set prometheus.prometheusSpec.queryLogFile=/var/log/prometheus/query.log \
  prometheus-community/kube-prometheus-stack

# Wait for the namespace to be ready
echo "Waiting for the kube-prometheus-stack namespace to be ready..."
while ! kubectl get namespace kube-prometheus-stack &> /dev/null; do
  sleep 1
done

# Apply Prometheus configuration
echo "Applying Prometheus configuration..."
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
DASHBOARD_FILE="${SCRIPT_DIR}/full_unified_dashboard_import.json"
kubectl apply -f "${SCRIPT_DIR}/prometheus.yaml"

# Wait for Prometheus to be ready
echo "Waiting for Prometheus to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus -n kube-prometheus-stack --timeout=300s

# Port-forward Prometheus UI to localhost:9090
echo "Setting up port-forward for Prometheus UI..."
kubectl port-forward -n kube-prometheus-stack svc/kube-prometheus-stack-prometheus 9090:9090 &
# Wait for port-forward to be ready
sleep 5
if ! curl -s http://localhost:9090 > /dev/null; then
  echo "Warning: Prometheus port-forward might not be working. Please check manually."
else
  echo "Prometheus UI is accessible at http://localhost:9090"
fi

# Set up log exporter and port-forward for log access
echo "Setting up port-forward for log access..."
kubectl wait --for=condition=available --timeout=120s -n kube-prometheus-stack deployment/log-exporter
kubectl port-forward -n kube-prometheus-stack svc/log-exporter 18080:8080 &
# Wait for port-forward to be ready
sleep 5
if ! curl -s http://localhost:18080 > /dev/null; then
  echo "Warning: Log exporter port-forward might not be working. Please check manually."
else
  echo "Logs are accessible at http://localhost:18080/query.log"
fi

# Set up Grafana port-forward
echo "Setting up port-forward for Grafana..."
kubectl wait --for=condition=available --timeout=120s -n kube-prometheus-stack deployment/kube-prometheus-stack-grafana
kubectl port-forward -n kube-prometheus-stack svc/kube-prometheus-stack-grafana 3000:80 &
# Wait for port-forward to be ready
sleep 5
if ! curl -s http://localhost:3000 > /dev/null; then
  echo "Warning: Grafana port-forward might not be working. Please check manually."
else
  echo "Grafana is accessible at http://localhost:3000"
  echo "Default credentials:"
  echo "  Username: admin"
  echo "  Password: prom-operator"
fi

# Import unified vLLM dashboard
import_dashboard() {
    echo "Importing unified vLLM dashboard..."
    
    if [ ! -f "$DASHBOARD_FILE" ]; then
        echo "Warning: Dashboard file not found: $DASHBOARD_FILE"
        echo "Skipping dashboard import. You can manually import it later via Grafana UI."
        return 0
    fi
    
    # Get Grafana admin password
    GRAFANA_PASSWORD=$(kubectl get secret -n kube-prometheus-stack kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 --decode)
    
    # Import dashboard via API
    echo "Importing dashboard via Grafana API..."
    
    IMPORT_PAYLOAD=$(cat "$DASHBOARD_FILE")
    
    RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -u "admin:$GRAFANA_PASSWORD" \
        -d "$IMPORT_PAYLOAD" \
        http://localhost:3000/api/dashboards/db)
    
    if echo "$RESPONSE" | jq -e '.status == "success"' > /dev/null 2>&1; then
        DASHBOARD_URL=$(echo "$RESPONSE" | jq -r '.url')
        echo "✅ Dashboard imported successfully!"
        echo "Dashboard URL: http://localhost:3000$DASHBOARD_URL"
    else
        echo "❌ Failed to import dashboard. Response: $RESPONSE"
        echo "You can manually import the dashboard from: $DASHBOARD_FILE"
    fi
}

# Import the dashboard
import_dashboard

echo ""
echo "🎉 Prometheus setup completed!"
echo ""
echo "📊 Access URLs:"
echo "  • Prometheus: http://localhost:9090"
echo "  • Grafana: http://localhost:3000 (admin/prom-operator)"
echo "  • Logs: http://localhost:18080/query.log"
echo ""
echo "📈 Dashboard:"
echo "  • Unified vLLM Monitoring: http://localhost:3000/d/complete-unified-vllm-monitoring/complete-unified-vllm-monitoring-aibrix-and-ps"
echo ""
echo "🔧 Next steps:"
echo "  • Deploy vLLM services with monitoring labels"
echo "  • Send test requests to generate metrics"
echo "  • View metrics in the dashboard" 