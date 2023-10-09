######################################################################################################################
# Copyright 2020-2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.                                      #
#                                                                                                                   #
# Licensed under the Apache License, Version 2.0 (the "License"). You may not use this file except in compliance    #
# with the License. A copy of the License is located at                                                             #
#                                                                                                                   #
#     http://www.apache.org/licenses/LICENSE-2.0                                                                    #
#                                                                                                                   #
# or in the 'license' file accompanying this file. This file is distributed on an 'AS IS' BASIS, WITHOUT WARRANTIES #
# OR CONDITIONS OF ANY KIND, express o#implied. See the License for the specific language governing permissions     #
# and limitations under the License.  																				#                                                                              #
######################################################################################################################

from aws_cdk import (RemovalPolicy,NestedStack,aws_cloud9 as cloud9,aws_ec2 as ec2, aws_msk_alpha as msk)
from constructs import Construct
class MSKStack(NestedStack):

    @property
    def Cloud9URL(self):
        return self._c9env.ref

    @property
    def MSKBroker(self):
        return self._msk_cluster.bootstrap_brokers


    def __init__(self, scope: Construct, id: str, cluster_name:str, eksvpc: ec2.IVpc, **kwargs) -> None:
        super().__init__(scope, id, **kwargs)

        # launch Cloud9 as Kafka client
        self._c9env = cloud9.CfnEnvironmentEC2(self, "KafkaClientEnv",
            name= "kafka_client",
            instance_type="t3.small",
            subnet_id=eksvpc.public_subnets[0].subnet_id,
            automatic_stop_time_minutes=60
        )
        self._c9env.apply_removal_policy(RemovalPolicy.DESTROY)

        # create MSK Cluster
        self._msk_cluster = msk.Cluster(self, "EMR-EKS-stream",
            cluster_name=cluster_name,
            kafka_version=msk.KafkaVersion.V2_8_1,
            vpc=eksvpc,
            ebs_storage_info=msk.EbsStorageInfo(volume_size=500),
            encryption_in_transit=msk.EncryptionInTransitConfig(
                enable_in_cluster=True,
                client_broker=msk.ClientBrokerEncryption.TLS_PLAINTEXT
            ),
            instance_type=ec2.InstanceType.of(ec2.InstanceClass.BURSTABLE3, ec2.InstanceSize.SMALL),
            removal_policy=RemovalPolicy.DESTROY,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PUBLIC,one_per_az=True)
        )

        for subnet in eksvpc.public_subnets:
            self._msk_cluster.connections.allow_from(ec2.Peer.ipv4(subnet.ipv4_cidr_block), ec2.Port.tcp(2181), "Zookeeper Plaintext")
            self._msk_cluster.connections.allow_from(ec2.Peer.ipv4(subnet.ipv4_cidr_block), ec2.Port.tcp(2182), "Zookeeper TLS")
            self._msk_cluster.connections.allow_from(ec2.Peer.ipv4(subnet.ipv4_cidr_block), ec2.Port.tcp(9092), "Broker Plaintext")
            self._msk_cluster.connections.allow_from(ec2.Peer.ipv4(subnet.ipv4_cidr_block), ec2.Port.tcp(9094), "Zookeeper Plaintext")
        for subnet in eksvpc.private_subnets:
            self._msk_cluster.connections.allow_from(ec2.Peer.ipv4(subnet.ipv4_cidr_block), ec2.Port.all_traffic(), "All private traffic")
