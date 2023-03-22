---
sidebar_position: 1
sidebar_label: Setup
---

import CollapsibleContent from '../../../src/components/CollapsibleContent';

:::info

Workshop content is in progress

:::

# At an AWS event
Steps for deploying the Setup using Amazon provided AWS accounts.


# In AWS Account

<CollapsibleContent header={<h2><span>Pre-requisites</span></h2>}>

**Pre-requisites for using your own AWS Account and your local machine.**

Ensure that you have installed the following tools on your machine.

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

**Pre-requisites for using your own AWS Account and your Cloud9 IDE.**

- Login to Cloud9 IDE using AWS Console
- execute the following commands from Cloud9 IDE home directory.

This script deploys all the necessary tools required for running Terraform, Kubectl and AWS CLI commands.

```sh
cd ~
git clone https://github.com/awslabs/data-on-eks.git
cd workshop/utilities
chmod +x pre-requisites-setup && ./pre-requisites-setup.sh
```

</CollapsibleContent>

<CollapsibleContent header={<h2><span>Deployment Steps</span></h2>}>


</CollapsibleContent>

<CollapsibleContent header={<h2><span>Clean up</span></h2>}>


</CollapsibleContent>
