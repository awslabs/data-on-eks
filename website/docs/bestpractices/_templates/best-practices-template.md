---
sidebar_label: This is a Template
---

<!---
This is a template for use when writing a new best practices guide.
-->

# \<Top Level Header\>

Replace `<Top Level Header>` with your clear and concise description for the overall topic of this document.

Examples:
- "VPC Configurations"
- "Pod Security"
- "Control Plane"

## \<Second Level Header\>

Replace `<Second Level Header>` with a clear and concise description about this topic.

Examples:
- "IP Considerations"
- "Policy-as-code (PAC)"
- "Monitor Control Plane Metrics"

Add background information here if required. For example:
"Kubernetes supports CNI specifications and plugins to implement Kubernetes network model..."

### \<Third Level Header\>

Replace `<Third Level Header>` with a clear and concise description of best practice or a problem.

Examples:
- "Consider using a secondary CIDR"
- "Employ least privileged access to AWS Resources"
- "Replace long running instances"

Write background information like what the problem is, why that happens, and symptoms of the problem.

Example: "If you are working with a network that spans multiple connected VPCs or sites the routable address space may be limited. For example, your VPC may be limited to small subnets like below. In this VPC we wouldn’t be able to run more than one m5.16xlarge node without adjusting the CNI configuration."

When adding images, put them under a directory called `img`.
For example, if you want to insert an image called "image1.png", put it under the `img` directory, then refer to that image like this: `![image1](./img/image1.png)`.
