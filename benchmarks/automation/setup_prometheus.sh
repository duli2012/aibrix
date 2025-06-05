#!/bin/bash

set -e  # Exit on error

# Parse command line arguments
FORCE_CLEAN=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --clean)
      FORCE_CLEAN=true
      shift
      ;;
    --help)
      echo "Usage: $0 [--clean] [--help]"
      echo "  --clean  Force clean installation (deletes all existing data)"
      echo "  --help   Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Backup existing metric exports if namespace exists
backup_metric_exports() {
    if kubectl get namespace kube-prometheus-stack &> /dev/null; then
        echo "🔄 Backing up existing metric exports..."
        BACKUP_DIR="/tmp/vllm_metrics_backup_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        
        # Try to backup exported files
        if kubectl get pod -n kube-prometheus-stack -l app=log-exporter &> /dev/null; then
            echo "   Copying metric exports to $BACKUP_DIR"
            kubectl exec -n kube-prometheus-stack deployment/log-exporter -c nginx -- sh -c "cd /metrics && tar -czf - vllm_metrics_*.json* 2>/dev/null || true" | tar -xzf - -C "$BACKUP_DIR" 2>/dev/null || true
            
            if [ -n "$(ls -A $BACKUP_DIR 2>/dev/null)" ]; then
                echo "   ✅ Backed up $(ls $BACKUP_DIR | wc -l) files to $BACKUP_DIR"
                echo "METRIC_BACKUP_DIR=\"$BACKUP_DIR\"" > /tmp/prometheus_backup_info
            else
                echo "   📝 No metric exports found to backup"
                rm -rf "$BACKUP_DIR"
            fi
        else
            echo "   📝 No log-exporter pod found, skipping backup"
        fi
    fi
}

# Restore metric exports after setup
restore_metric_exports() {
    if [ -f /tmp/prometheus_backup_info ]; then
        source /tmp/prometheus_backup_info
        if [ -d "$METRIC_BACKUP_DIR" ] && [ -n "$(ls -A $METRIC_BACKUP_DIR 2>/dev/null)" ]; then
            echo "🔄 Restoring metric exports..."
            echo "   Waiting for log-exporter to be ready..."
            kubectl wait --for=condition=available --timeout=120s -n kube-prometheus-stack deployment/log-exporter
            
            echo "   Copying backed up files..."
            for file in "$METRIC_BACKUP_DIR"/*; do
                if [ -f "$file" ]; then
                    filename=$(basename "$file")
                    kubectl exec -n kube-prometheus-stack deployment/log-exporter -c nginx -- sh -c "cat > /metrics/$filename" < "$file"
                fi
            done
            
            echo "   ✅ Restored $(ls $METRIC_BACKUP_DIR | wc -l) metric export files"
            echo "   🧹 Cleaning up temporary backup..."
            rm -rf "$METRIC_BACKUP_DIR"
            rm -f /tmp/prometheus_backup_info
        fi
    fi
}

# Smart cleanup: backup data first, then clean if needed
if [ "$FORCE_CLEAN" = true ]; then
    echo "🧹 Force clean requested - backing up data first..."
    backup_metric_exports
    echo "Cleaning up any existing installation..."
    kubectl delete namespace kube-prometheus-stack --force --grace-period=0 2>/dev/null || true
    pkill -f "kubectl port-forward" 2>/dev/null || true
    sleep 5
elif kubectl get namespace kube-prometheus-stack &> /dev/null; then
    echo "📋 Existing installation detected."
    echo "   Use --clean flag to force a clean installation"
    echo "   Updating existing installation instead..."
    pkill -f "kubectl port-forward" 2>/dev/null || true
    sleep 2
else
    echo "🚀 No existing installation found, proceeding with fresh setup..."
    pkill -f "kubectl port-forward" 2>/dev/null || true
    sleep 2
fi

# Install kube-prometheus-stack
echo "Installing kube-prometheus-stack"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Create namespace if it doesn't exist
if ! kubectl get namespace kube-prometheus-stack &> /dev/null; then
    echo "Creating kube-prometheus-stack namespace..."
    kubectl create namespace kube-prometheus-stack
else
    echo "Using existing kube-prometheus-stack namespace..."
fi

# Install or upgrade kube-prometheus-stack with custom configuration
if helm list -n kube-prometheus-stack | grep -q kube-prometheus-stack; then
    echo "Upgrading existing kube-prometheus-stack Helm release..."
    helm upgrade kube-prometheus-stack \
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
else
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
fi

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

# Set up metric data exporter and port-forward
echo "Setting up port-forward for metric data exporter..."
kubectl wait --for=condition=available --timeout=120s -n kube-prometheus-stack deployment/log-exporter
kubectl port-forward -n kube-prometheus-stack svc/log-exporter 18080:8080 &
# Wait for port-forward to be ready
sleep 5
if ! curl -s http://localhost:18080 > /dev/null; then
  echo "Warning: Metric exporter port-forward might not be working. Please check manually."
else
  echo "📊 Metric Data Exporter is accessible at:"
  echo "  • Dashboard: http://localhost:18080/dashboard"
  echo "  • File Browser: http://localhost:18080/"
  echo "  • API: http://localhost:18080/api/export"
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

# Create unified data source
create_unified_datasource() {
    echo "Creating unified vLLM data source in Grafana..."
    
    # Get Grafana admin password
    GRAFANA_PASSWORD=$(kubectl get secret -n kube-prometheus-stack kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 --decode)
    
    # Create unified data source configuration
    DATASOURCE_CONFIG='{
        "name": "Unified vLLM Metrics",
        "type": "prometheus",
        "url": "http://log-exporter:8080/unified",
        "access": "proxy",
        "isDefault": false,
        "jsonData": {
            "httpMethod": "GET",
            "manageAlerts": true,
            "prometheusType": "Prometheus",
            "prometheusVersion": "2.40.0",
            "cacheLevel": "High",
            "disableRecordingRules": false,
            "incrementalQueryOverlapWindow": "10m",
            "queryTimeout": "60s",
            "timeInterval": "30s"
        }
    }'
    
    echo "Adding unified data source via Grafana API..."
    
    RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -u "admin:$GRAFANA_PASSWORD" \
        -d "$DATASOURCE_CONFIG" \
        http://localhost:3000/api/datasources)
    
    if echo "$RESPONSE" | jq -e '.id' > /dev/null 2>&1; then
        DATASOURCE_ID=$(echo "$RESPONSE" | jq -r '.id')
        DATASOURCE_UID=$(echo "$RESPONSE" | jq -r '.uid')
        echo "✅ Unified data source created successfully!"
        echo "   ID: $DATASOURCE_ID"
        echo "   UID: $DATASOURCE_UID"
        echo "   Name: Unified vLLM Metrics"
        echo "   URL: http://log-exporter:8080/unified"
        echo ""
        echo "🎯 Usage in Grafana:"
        echo "   • Select 'Unified vLLM Metrics' as data source"
        echo "   • Query: vllm:generation_tokens_total"
        echo "   • Get: Historical + Live data automatically!"
    elif echo "$RESPONSE" | jq -e '.message' | grep -q "already exists" 2>/dev/null; then
        echo "📝 Unified data source already exists, skipping creation"
    else
        echo "❌ Failed to create unified data source. Response: $RESPONSE"
        echo "💡 You can manually add it in Grafana:"
        echo "   • Type: Prometheus"
        echo "   • Name: Unified vLLM Metrics"
        echo "   • URL: http://log-exporter:8080/unified"
        echo "   • Access: Server (default)"
    fi
}

# Create the unified data source
create_unified_datasource

# Restore backed up metric exports if any
restore_metric_exports

echo ""
echo "🎉 Prometheus setup completed!"
echo ""
echo "📊 Access URLs:"
echo "  • Prometheus: http://localhost:9090"
echo "  • Grafana: http://localhost:3000 (admin/prom-operator)"
echo "  • Metric Exporter Dashboard: http://localhost:18080/dashboard"
echo "  • Metric Files: http://localhost:18080/"
echo ""
echo "📈 Dashboard:"
echo "  • Unified vLLM Monitoring: http://localhost:3000/d/complete-unified-vllm-monitoring/complete-unified-vllm-monitoring-aibrix-and-ps"
echo ""
echo "🔄 Data Sources Available:"
echo "  • kube-prometheus-stack-prometheus: Live metrics"
echo "  • Unified vLLM Metrics: Historical + Live data combined"
echo ""
echo "🚀 Metric Export Features:"
echo "  • Export vLLM metrics to downloadable files"
echo "  • Auto-export every hour with historical data"
echo "  • JSON and compressed formats available"
echo "  • Perfect for analysis and Grafana import"
echo ""
echo "🎯 Unified Data Source Benefits:"
echo "  • Query historical and live data seamlessly"
echo "  • No need to switch between data sources"
echo "  • Automatic timestamp-based merging"
echo "  • Same metric names work for all time periods"
echo ""
echo "🔧 Next steps:"
echo "  • Deploy vLLM services with monitoring labels"
echo "  • Send test requests to generate metrics"
echo "  • View metrics in the dashboard"
echo "  • Export metric data via http://localhost:18080/dashboard"
echo "  • Use 'Unified vLLM Metrics' data source for comprehensive analysis" 