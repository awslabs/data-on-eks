apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: nifi-dr
  namespace: ${nifi_namespace}
spec:
  host: ${cluster_name}-node-default-headless.${nifi_namespace}.svc.cluster.local
  trafficPolicy:
    loadBalancer:
      consistentHash:
        httpCookie:
          name: __Secure-Request-Token
          path: /
          ttl: 0s
    tls:
      mode: SIMPLE
      insecureSkipVerify: true
      sni: ${external_dns_name}