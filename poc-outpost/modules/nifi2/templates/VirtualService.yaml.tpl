apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: nifi-vs
  namespace: ${nifi_namespace}
spec:
  gateways:
  - nifi-gateway
  hosts:
  - ${external_dns_name}
  http:
  - headers:
      request:
        set:
          X-Forwarded-Host: ${external_dns_name}
          X-Forwarded-Port: "443"
          X-Forwarded-Proto: https
    match:
    - uri:
        prefix: /
    route:
    - destination:
        host: ${cluster_name}-node-default-headless.${nifi_namespace}.svc.cluster.local
        port:
          number: 8443