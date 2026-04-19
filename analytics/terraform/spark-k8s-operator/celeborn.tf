#---------------------------------------------------------------
# Apache Celeborn - Remote Shuffle Service for Spark
#---------------------------------------------------------------
# Celeborn offloads shuffle data from Spark executors to a dedicated
# shuffle service, improving stability and performance for shuffle-heavy workloads.
# Reference: https://celeborn.apache.org/

resource "helm_release" "celeborn" {
  count = var.enable_celeborn ? 1 : 0

  name             = "celeborn"
  namespace        = "celeborn"
  create_namespace = true
  chart            = "${path.module}/helm-charts/celeborn"
  timeout          = 600

  values = [templatefile("${path.module}/helm-values/celeborn-values.yaml", {})]

  depends_on = [module.eks, kubectl_manifest.auto_mode_nodepools]
}
