apiVersion: v1
kind: Secret
metadata:
  name: nifi-oidc-client
  namespace: ${nifi_namespace}
stringData:
  clientId: ${client_keycloak}
  clientSecret: ${secret_keycloak}