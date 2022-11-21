import { Construct } from 'constructs';
import { SubnetType, Vpc } from 'aws-cdk-lib/aws-ec2';


export default class VpcDefinintion extends Construct {

    constructor(scope: Construct, id: string) {
        super(scope, id);

        const eksVpc: Vpc = new Vpc(this, 'eksVpc', {
            cidr: '10.0.0.0/16',
            natGateways: 3,
            maxAzs: 3
        });

    }

}
