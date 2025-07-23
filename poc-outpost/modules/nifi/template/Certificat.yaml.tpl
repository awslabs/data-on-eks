apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: tls-nifi
  namespace: istio-ingress
spec:
  secretName: tls-nifi
  duration: 2160h0m0s # 90d
  renewBefore: 360h0m0s # 15d
  subject:
    organizations:
      - orange
  commonName: ${nifi_instance_name}.orange-eks.com
  dnsNames:
    - ${nifi_instance_name}.orange-eks.com
  issuerRef:
    name: letsencrypt-http-private
    kind: ClusterIssuer
