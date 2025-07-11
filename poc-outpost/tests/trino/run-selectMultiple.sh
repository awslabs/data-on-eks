export dns=$(kubectl get ingress -n trino -o jsonpath="{range .items[*]}{.status.loadBalancer.ingress[0].hostname}{'\n'}{end}")

echo "Running Trino query select multiple tables in Iceberg"
trino --file 'trino_select_query_iceberg.sql' --server "http://${dns}" --user admin --ignore-errors