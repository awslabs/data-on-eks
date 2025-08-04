apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: nifi-server-cert
  namespace: ${nifi_namespace}
spec:
  secretName: nifi2-server-tls
  duration: 8760h # 1 an
  renewBefore: 360h
  subject:
    organizations:
      - Orange
  commonName: ${external_dns_name}
  dnsNames:
%{ for dns in dns_names ~}
    - ${dns}
%{ endfor ~}
  privateKey:
    algorithm: RSA
    size: 2048
  issuerRef:
    name: nifi-ca-issuer
    kind: Issuer