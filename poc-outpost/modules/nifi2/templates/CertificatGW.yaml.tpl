apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: tls-nifi2
  namespace: istio-ingress
spec:
  commonName: ${external_dns_name}
  dnsNames:
  - ${external_dns_name}
  duration: 2160h0m0s
  issuerRef:
    kind: ClusterIssuer
    name: letsencrypt-http-private
  renewBefore: 360h0m0s
  secretName: tls-nifi2
  subject:
    organizations:
    - orange