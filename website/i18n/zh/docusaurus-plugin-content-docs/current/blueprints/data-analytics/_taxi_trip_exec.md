使用以下输入运行 *taxi-trip-execute.sh* 脚本。您将使用之前创建的 *S3_BUCKET* 变量。此外，您必须将 YOUR_REGION_HERE 更改为您选择的区域，例如 *us-west-2*。

此脚本将下载一些示例出租车行程数据并创建其副本以稍微增加大小。这将需要一些时间并需要相对较快的互联网连接。

```bash
cd ${DOEKS_HOME}/analytics/scripts/
chmod +x taxi-trip-execute.sh
./taxi-trip-execute.sh ${S3_BUCKET} YOUR_REGION_HERE
```

您可以返回蓝图目录并继续示例
```bash
cd ${DOEKS_HOME}/analytics/terraform/spark-k8s-operator
```
