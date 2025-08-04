apiVersion: nifi.stackable.tech/v1alpha1
kind: NifiCluster
metadata:
  name: ${cluster_name}
  namespace: ${nifi_namespace}
spec:
  clusterConfig:
    authentication:
    - authenticationClass: oidc
      oidc:
        clientCredentialsSecret: nifi-oidc-client
        extraScopes: []
    createReportingTaskJob:
      enabled: true
      podOverrides: {}
    customComponentsGitSync: []
    extraVolumes:
    - name: storenew
      secret:
        secretName: nifi2-p12-secrets
    hostHeaderCheck:
      additionalAllowedHosts: []
      allowAll: true
    sensitiveProperties:
      autoGenerate: true
      keySecret: nifi-sensitive-property-key
    tls:
      serverSecretClass: tls
  clusterOperation:
    reconciliationPaused: false
    stopped: false
  image:
    productVersion: 2.4.0
    pullPolicy: Always
  nodes:
    cliOverrides: {}
    config:
      affinity:
        nodeAffinity: null
        nodeSelector: null
        podAffinity: null
        podAntiAffinity: null
      logging:
        containers: {}
        enableVectorAgent: null
      resources:
        cpu:
          max: null
          min: null
        memory:
          limit: null
          runtimeLimits: {}
        storage:
          contentRepo:
            capacity: null
          databaseRepo:
            capacity: null
          flowfileRepo:
            capacity: null
          provenanceRepo:
            capacity: null
          stateRepo:
            capacity: null
    configOverrides:
      nifi.properties:
        nifi.security.keystore: /stackable/userdata/storenew/keystore.p12
        nifi.security.keystorePasswd: secret
        nifi.security.keystoreType: PKCS12
        nifi.security.truststore: /stackable/userdata/storenew/truststore.p12
        nifi.security.truststorePasswd: secret
        nifi.security.truststoreType: PKCS12
        nifi.web.proxy.host: nifi2.orange-eks.com
    envOverrides: {}
    jvmArgumentOverrides:
      add: []
      remove: []
      removeRegex: []
    podOverrides: {}
    roleConfig:
      listenerClass: external-unstable
      podDisruptionBudget:
        enabled: true
        maxUnavailable: null
    roleGroups:
      default:
        cliOverrides: {}
        config:
          affinity:
            nodeAffinity: null
            nodeSelector: null
            podAffinity: null
            podAntiAffinity: null
          logging:
            containers: {}
            enableVectorAgent: null
          resources:
            cpu:
              max: null
              min: null
            memory:
              limit: null
              runtimeLimits: {}
            storage:
              contentRepo:
                capacity: null
              databaseRepo:
                capacity: null
              flowfileRepo:
                capacity: null
              provenanceRepo:
                capacity: null
              stateRepo:
                capacity: null
        configOverrides: {}
        envOverrides: {}
        jvmArgumentOverrides:
          add: []
          remove: []
          removeRegex: []
        podOverrides: {}
        replicas: ${replica}
