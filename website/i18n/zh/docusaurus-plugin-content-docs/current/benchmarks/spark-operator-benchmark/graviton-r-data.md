---
sidebar_position: 6
sidebar_label: Graviton R 系列结果
---
import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import CollapsibleContent from '../../../../../../src/components/CollapsibleContent';
import CodeBlock from '@theme/CodeBlock';

import RSeriesNodeGroup from '../../../../../../docs/benchmarks/spark-operator-benchmark/_r_series_nodegroup.md'
import RSeriesSparkApp from '../../../../../../docs/benchmarks/spark-operator-benchmark/_r_series_spark_app.md'
import RSeriesDockerfile from '../../../../../../docs/benchmarks/spark-operator-benchmark/_r_series_dockerfile.md'

# Graviton R6g、R7g 和 R8g 的 TPCDS Spark 基准测试结果
此页面包含我们在 R 系列 Graviton 实例上的基准测试结果，显示新一代实例的运行时间最多快 1.6 倍。

这些基准测试使用[运行基准测试](./running-the-benchmark.md)部分中定义的步骤在 1TB 数据上执行。我们对所有这些测试使用了相同的 EKS 集群、相同的数据集、相同数量的节点以及相同的附加组件和配置。我们只是更改了每次运行使用的实例类型。
完整的配置详细信息如下：

<details>
<summary> 要查看托管节点组配置，点击切换内容！</summary>

<RSeriesNodeGroup />

</details>

<details>
<summary> 要查看 Spark 应用程序配置，点击切换内容！</summary>

<RSeriesSparkApp />

</details>
