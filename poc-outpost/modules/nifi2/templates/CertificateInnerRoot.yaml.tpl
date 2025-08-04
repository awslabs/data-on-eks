apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: nifi-ca
  namespace: ${nifi_namespace}
spec:
  isCA: true
  commonName: nifi-ca
  secretName: nifi-ca-keypair
  duration: 87600h # 10 ans
  privateKey:
    algorithm: RSA
    size: 2048
  issuerRef:
    name: selfsigned
    kind: Issuer