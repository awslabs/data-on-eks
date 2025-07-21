set -e

echo "Get admin secret name from terraform output"
cd ../.. && admin_secret_name=$(terraform output -raw grafana_local_secret_name)
echo "log to grafana with admin and with the folowing password:"
aws secretsmanager get-secret-value --secret-id ${admin_secret_name} --region us-west-2 --query "SecretString" --output text

echo "Running port-forward to Grafana service"
echo "Grafana is now accessible at http://localhost:8080"
kubectl port-forward svc/kube-prometheus-stack-grafana 8080:80 -n kube-prometheus-stack
