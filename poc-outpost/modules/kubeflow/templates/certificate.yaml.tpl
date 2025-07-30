apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: tls-kubeflow
  namespace: istio-ingress
spec:
  commonName: ${kubeflow_domain}
  dnsNames:
  - ${kubeflow_domain}
  duration: 2160h0m0s
  issuerRef:
    kind: ClusterIssuer
    name: letsencrypt-http-private
  renewBefore: 360h0m0s
  secretName: tls-kubeflow
  subject:
    organizations:
    - orange