import { Construct } from 'constructs';
import { GatewayVpcEndpointAwsService, Vpc, VpcProps } from 'aws-cdk-lib/aws-ec2';

export class VpcDefinintion extends Construct {
    public clusterVpc: Vpc;

    constructor (scope: Construct, id : string, props: VpcProps) {
        super(scope, id);
        
        this.clusterVpc = new Vpc(this, 'clusterVpc', {
            gatewayEndpoints: {
                S3: {
                  service: GatewayVpcEndpointAwsService.S3,
                },
              },
            vpcName: props.vpcName ? props.vpcName : 'emrEksBlueprintVpc'
        });

      }

}