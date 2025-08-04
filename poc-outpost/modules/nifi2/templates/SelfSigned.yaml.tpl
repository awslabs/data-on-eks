apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: selfsigned
  namespace: ${nifi_namespace}
spec:
  selfSigned: {}