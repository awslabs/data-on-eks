apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: nifi-virtualservice
  namespace: nifi
spec:
  hosts:
    - "${nifi_instance_name}.orange-eks.com"
  gateways:
    - nifi-gateway
  http:
    # Let’s Encrypt
    - match:
        - uri:
            prefix: "/.well-known/acme-challenge/"
      route:
        - destination:
            host: cert-manager-webhook.cert-manager.svc.cluster.local
            port:
              number: 8080

    # Trafic vers NiFi
    - match:
        - uri:
            prefix: /
      route:
        - destination:
            host: eksnifi-headless
            port:
              number: 8080
      headers:
        request:
          set:
            X-Forwarded-Proto: https
            X-Forwarded-Port: "443"
            X-Forwarded-Host: "${nifi_instance_name}.orange-eks.com"