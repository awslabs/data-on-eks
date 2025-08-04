apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: nifi-gateway
  namespace: ${nifi_namespace}
spec:
  selector:
    istio: ingressgateway
  servers:
  - hosts:
    - ${external_dns_name}
    port:
      name: https
      number: 443
      protocol: HTTPS
    tls:
      credentialName: tls-nifi2
      mode: SIMPLE
