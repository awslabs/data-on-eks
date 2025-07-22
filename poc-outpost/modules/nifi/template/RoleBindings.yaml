kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: nifikoprolebinding
  namespace: nifi
subjects:
  - kind: ServiceAccount
    name: nifikop
    namespace: nifi
roleRef:
  kind: Role
  name: nifikoprole
  apiGroup: rbac.authorization.k8s.io