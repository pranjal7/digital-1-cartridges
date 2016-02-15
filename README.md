The repository contains the CloudFormation template to create Mule EC2 instances supplemented with the required Docker containers.

The instances are created on a private subnet and then routed to the public NAT instance.

Instances are created for:
- Mule runtime
- Mule Framework
- SoapUI Stub Server