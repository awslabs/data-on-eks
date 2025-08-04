apiVersion: authentication.stackable.tech/v1alpha1
kind: AuthenticationClass
metadata:
  name: oidc
  namespace: ${nifi_namespace}
spec:
  provider:
    oidc:
      hostname: ${keycloak_url}
      rootPath: /realms/orange-eks/
      principalClaim: preferred_username
      scopes:
        - openid
        - email
        - profile
      port: 443
      tls:
       verification:
         server:
          caCert:
            webPki: {} 