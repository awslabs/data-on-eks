---
sidebar_position: 7
sidebar_label: Ray Data on EKS
mermaid: true
---
import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import CollapsibleContent from '../../../../../../src/components/CollapsibleContent';

# 使用 Ray Data 进行分布式数据处理

## 什么是 Ray Data？

[Ray Data](https://docs.ray.io/en/latest/data/data.html) 是一个基于 Ray 构建的可扩展、框架无关的数据处理库，专为分布式数据分析和机器学习工作负载而设计。它提供：

- **分布式处理**：跨多个 Ray 工作节点的并行数据处理
- **惰性求值**：操作被优化并仅在需要结果时执行
- **丰富的数据连接器**：对各种数据源的原生支持，包括 S3、数据库和文件系统
- **内存管理**：高效处理不适合内存的大型数据集
- **与 ML 库集成**：与 pandas、NumPy 和 PyArrow 的无缝集成

## 为什么选择 Ray Data？这是 Spark 的替代工具吗？

Ray Data 是 **Spark 的补充**，而不是直接替代品。虽然两者都是分布式数据处理框架，但它们服务于不同的用例：

```mermaid
graph LR
    subgraph AS["<b>Apache Spark</b>"]
        A[大规模数据分析]
        B[分布式 SQL 分析]
        C[批处理/流处理]
    end

    subgraph RD["<b>Ray Data</b>"]
        D[ML 数据预处理]
        E[实时推理]
        F[迭代工作负载]
        G[Python 原生处理]
    end

    subgraph CU["<b>常见用例</b>"]
        H[数据转换]
        I[分布式计算]
    end

    style A fill:#37474f,color:#fff
    style B fill:#37474f,color:#fff
    style C fill:#37474f,color:#fff
    style D fill:#FF6B6B,stroke:#FF4444,stroke-width:3px,color:#fff
    style E fill:#4ECDC4,stroke:#45B7AA,stroke-width:3px,color:#fff
