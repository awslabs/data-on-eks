import { IpAddresses, Vpc } from 'aws-cdk-lib/aws-ec2';
import { App, Stack, StackProps } from 'aws-cdk-lib';


export default class VpcDefinintion extends Stack {

    public readonly vpc: Vpc;

    constructor(scope: App, id: string, props: StackProps) {
        super(scope, id, props);

        this.vpc = new Vpc(this, 'eksVpc', {
            ipAddresses: IpAddresses.cidr('10.0.0.0/16'),
            natGateways: 3,
            maxAzs: 3
        });

    }

}
