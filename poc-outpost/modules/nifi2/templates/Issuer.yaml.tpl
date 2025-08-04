apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: nifi-ca-issuer
  namespace: ${nifi_namespace}
spec:
  ca:
    secretName: nifi-ca-keypair