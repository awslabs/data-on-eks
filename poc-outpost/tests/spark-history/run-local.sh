set -e
echo "Running port-forward to spark-history-server service"
echo "spark history is now accessible at http://localhost:8080"

kubectl port-forward service/spark-history-server 8080:80 -n spark-history-server
