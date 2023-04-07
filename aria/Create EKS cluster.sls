META:
  name: AWS EKS - Cluster and Node Group
  provider: AWS
  category: CONFIG
  subcategory: Reference
  template_id: 6b.aws_eks.1
  version: v1
  description: Create a new EKS Cluster and attach Node Group to this Cluster and create all the pre-requisites required for creation cluster and node group.

{% set cluster_name = params.get('cluster_name', 'cluster-1') %}
{% set node_group = params.get('node_group','node-group-1') %}

{% set instance_types = params.get('instance_types', 't3.medium') %}
{% set ami_type = params.get('ami_type','AL2_x86_64') %}
{% set desired_size = params.get('desired_size','2') %}
{% set max_size = params.get('max_size','2') %}
{% set min_size = params.get('min_size','2') %}
{% set disk_size = params.get('disk_size','20') %}

{% set vpc_name = params.get('vpc_name','vpc-1') %}
{% set public_subnet_1 = params.get('public_subnet_1','public-subnet-1') %}
{% set public_subnet_2 = params.get('public_subnet_2','public-subnet-2') %}
{% set private_subnet_1 = params.get('private_subnet_1','private-subnet-1') %}
{% set private_subnet_2 = params.get('private_subnet_2','private-subnet-2') %}
{% set public_availability_zone_1 = params.get('public_availability_zone_1','us-east-1a') %}
{% set public_availability_zone_2 = params.get('public_availability_zone_2','us-east-1b') %}
{% set private_availability_zone_1 = params.get('private_availability_zone_1','us-east-1c') %}
{% set private_availability_zone_2 = params.get('private_availability_zone_2','us-east-1d') %}

{% set internet_gateway = params.get('internet_gateway','internet-gateway-1') %}
{% set public_route_table = params.get('public_route_table','public-routetable-1') %}

{% set cluster_role = params.get('cluster_role','cluster-role-1') %}
{% set worker_role = params.get('worker_role','worker-role-1') %}


{{cluster_role}}:
  META:
      name: Create a Cluster Role
      parameters:
        cluster_role:
          name: Cluster Role
          description: Name of the Cluster Role
          uiElement: text
  aws.iam.role.present:
  - path: /
  - assume_role_policy_document: '{"Version": "2012-10-17","Statement": {"Effect": "Allow","Principal": {"Service": "eks.amazonaws.com"},"Action": "sts:AssumeRole"}}'
  - description: Allows access to other AWS service resources that are required to
      operate clusters managed by EKS.
  - max_session_duration: 3600

{{worker_role}}:
  META:
      name: Create a Worker Role
      parameters:
        worker_role:
          name: Worker Role
          description: Name of the Worker Role
          uiElement: text
  aws.iam.role.present:
  - path: /
  - assume_role_policy_document: '{"Version": "2012-10-17","Statement": {"Effect": "Allow","Principal": {"Service": "ec2.amazonaws.com"},"Action": "sts:AssumeRole"}}'
  - description: Allows access to other AWS service resources that are required to
      operate clusters managed by EKS.
  - max_session_duration: 3600

{{worker_role}}/AmazonEC2ContainerRegistryReadOnly:
  aws.iam.role_policy_attachment.present:
  - role_name: "${aws.iam.role:{{worker_role}}:name}"
  - policy_arn: arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
{{worker_role}}//AmazonEKSWorkerNodePolicy:
  aws.iam.role_policy_attachment.present:
  - role_name: "${aws.iam.role:{{worker_role}}:name}"
  - policy_arn: arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
{{worker_role}}//AmazonEKS_CNI_Policy:
  aws.iam.role_policy_attachment.present:
  - role_name: "${aws.iam.role:{{worker_role}}:name}"
  - policy_arn: arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy

{{cluster_role}}/AmazonEKSClusterPolicy:
  aws.iam.role_policy_attachment.present:
  - role_name: "${aws.iam.role:{{cluster_role}}:name}"
  - policy_arn: arn:aws:iam::aws:policy/AmazonEKSClusterPolicy


{{vpc_name}}:
  META:
      name: Create VPC for EKS Cluster
      parameters:
        vpc_name:
          name: VPC
          description: Name of the VPC
          uiElement: text
  aws.ec2.vpc.present:
  - instance_tenancy: default
  - tags:
    - Key: Name
      Value: {{vpc_name}}
  - cidr_block_association_set:
    - CidrBlock: 192.168.0.0/16
  - enable_dns_hostnames: true
  - enable_dns_support: true

{{public_subnet_1}}:
  META:
      name: Create a Public Subnet 1
      parameters:
        public_subnet_1:
          name: Public Subnet 1
          description: Name of the Public Subnet
          uiElement: text
        public_availability_zone_1:
          name: Public Availability Zone 1
          description: Public Availability Zone
          uiElement: text
  aws.ec2.subnet.present:
  - vpc_id: "${aws.ec2.vpc:{{vpc_name}}:resource_id}"
  - cidr_block: 192.168.0.0/18
  - availability_zone: {{public_availability_zone_1}}
  - map_public_ip_on_launch: true
  - tags:
    - Key: Name
      Value: {{vpc_name}}-PublicSubnet01
    - Key: kubernetes.io/role/elb
      Value: '1'

{{public_subnet_2}}:
  META:
      name: Create a Public Subnet 2
      parameters:
        public_subnet_2:
          name: Public Subnet 2
          description: Name of the Public Subnet
          uiElement: text
        public_availability_zone_2:
          name: Public Availability Zone 2
          description: Public Availability Zone
          uiElement: text
  aws.ec2.subnet.present:
  - vpc_id: "${aws.ec2.vpc:{{vpc_name}}:resource_id}"
  - cidr_block: 192.168.64.0/18
  - availability_zone: {{public_availability_zone_2}}
  - map_public_ip_on_launch: true
  - tags:
    - Key: Name
      Value: {{vpc_name}}-PublicSubnet02
    - Key: kubernetes.io/role/elb
      Value: '1'

{{private_subnet_1}}:
  META:
      name: Create a Private Subnet 1
      parameters:
        private_subnet_1:
          name: Private Subnet 1
          description: Name of the Private Subnet
          uiElement: text
        private_availability_zone_1:
          name: Private Availability Zone 1
          description: Private Availability Zone
          uiElement: text
  aws.ec2.subnet.present:
  - vpc_id: "${aws.ec2.vpc:{{vpc_name}}:resource_id}"
  - cidr_block: 192.168.128.0/18
  - availability_zone: {{private_availability_zone_1}}
  - map_public_ip_on_launch: false
  - tags:
    - Key: kubernetes.io/role/internal-elb
      Value: '1'
    - Key: Name
      Value: {{vpc_name}}-PrivateSubnet01

{{private_subnet_2}}:
  META:
      name: Create a Private Subnet 2
      parameters:
        private_subnet_2:
          name: Private Subnet 2
          description: Name of the Private Subnet
          uiElement: text
        private_availability_zone_2:
          name: Private Availability Zone 2
          description: Private Availability Zone
          uiElement: text
  aws.ec2.subnet.present:
  - vpc_id: "${aws.ec2.vpc:{{vpc_name}}:resource_id}"
  - cidr_block: 192.168.192.0/18
  - availability_zone: {{private_availability_zone_2}}
  - map_public_ip_on_launch: false
  - tags:
    - Key: Name
      Value: {{vpc_name}}-PrivateSubnet02
    - Key: kubernetes.io/role/internal-elb
      Value: '1'

{{internet_gateway}}:
  META:
      name: Create a Internet Gateway
      parameters:
        internet_gateway:
          name: Internet Gateway
          description: Name of the Internet Gateway
          uiElement: text
  aws.ec2.internet_gateway.present:
    - vpc_id:
      - "${aws.ec2.vpc:{{vpc_name}}:resource_id}"

{{public_route_table}}:
  META:
      name: Create a Public Route Table
      parameters:
        public_route_table:
          name: Public Route Table
          description: Name of the Public Route Table
          uiElement: text
  aws.ec2.route_table.present:
  - require:
    - aws.ec2.internet_gateway: {{internet_gateway}}
  - routes:
    - DestinationCidrBlock: 0.0.0.0/0
      GatewayId: "${aws.ec2.internet_gateway:{{internet_gateway}}:resource_id}"
  - tags:
    - Key: Name
      Value: Public Subnets
    - Key: Network
      Value: Public
  - vpc_id: "${aws.ec2.vpc:{{vpc_name}}:resource_id}"

"RoutetableAssociation-{{public_subnet_1}}":
  META:
      name: Associates route table with {{public_subnet_1}}
  aws.ec2.route_table_association.present:
  - require:
    - aws.ec2.route_table: {{public_route_table}}
  - route_table_id: "${aws.ec2.route_table:{{public_route_table}}:resource_id}"
  - subnet_id: "${aws.ec2.subnet:{{public_subnet_1}}:resource_id}"

"RoutetableAssociation-{{public_subnet_2}}":
  META:
      name: Associates route table with {{public_subnet_2}}
  aws.ec2.route_table_association.present:
  - require:
    - aws.ec2.route_table: {{public_route_table}}
  - route_table_id: "${aws.ec2.route_table:{{public_route_table}}:resource_id}"
  - subnet_id: "${aws.ec2.subnet:{{public_subnet_2}}:resource_id}"


{{cluster_name}}:
  META:
      name: Create EKS Cluster
  aws.eks.cluster.present:
  - require:
    - aws.ec2.subnet: {{public_subnet_1}}
    - aws.ec2.subnet: {{public_subnet_2}}
    - aws.ec2.subnet: {{private_subnet_1}}
    - aws.ec2.subnet: {{private_subnet_2}}
  - role_arn: "${aws.iam.role:{{cluster_role}}:arn}"
  - version: '1.21'
  - resources_vpc_config:
      endpointPrivateAccess: false
      endpointPublicAccess: true
      publicAccessCidrs:
      - 0.0.0.0/0
      securityGroupIds: []
      subnetIds:
      - "${aws.ec2.subnet:{{public_subnet_1}}:resource_id}"
      - "${aws.ec2.subnet:{{public_subnet_2}}:resource_id}"
      - "${aws.ec2.subnet:{{private_subnet_1}}:resource_id}"
      - "${aws.ec2.subnet:{{private_subnet_2}}:resource_id}"
  - kubernetes_network_config:
      ipFamily: ipv4
      serviceIpv4Cidr: 10.100.0.0/16
  - logging:
      clusterLogging:
      - enabled: false
        types:
        - api
        - audit
        - authenticator
        - controllerManager
        - scheduler
  - tags: {}

{{node_group}}:
  META:
      name: Create EKS Node Group
      parameters:
        cluster_name:
          name: Cluster Name
          description: Name of the cluster
          uiElement: text
        desired_size:
          name: Desired Size
          description: The current number of nodes that the managed node group should maintain.
          uiElement: int
        max_size:
          name: Max Size
          description: The maximum number of nodes that the managed node group can scale out to.
          uiElement: int
        min_size:
          name: Min Size
          description: The minimum number of nodes that the managed node group can scale in to.
          uiElement: int
        instance_types:
          name: Instance Types
          description: Specify the instance types for a node group.
          uiElement: text
        ami_type:
          name: AMI Type
          description: The AMI type for your node group.
          uiElement: text
        disk_size:
          name: Disk Size
          description: The root device disk size (in GiB) for your node group instances.
          uiElement: int
  aws.eks.nodegroup.present:
  - require:
    - aws.eks.cluster: {{cluster_name}}
  - cluster_name: {{cluster_name}}
  - version: '1.21'
  - release_version: 1.21.5-20220406
  - capacity_type: ON_DEMAND
  - scaling_config:
      desiredSize: {{desired_size}}
      maxSize: {{max_size}}
      minSize: {{min_size}}
  - instance_types:
    - {{instance_types}}
  - subnets:
    - "${aws.ec2.subnet:{{public_subnet_1}}:resource_id}"
    - "${aws.ec2.subnet:{{public_subnet_2}}:resource_id}"
  - ami_type: {{ami_type}}
  - node_role: "${aws.iam.role:{{worker_role}}:arn}"
  - labels: {}
  - disk_size: {{disk_size}}
  - update_config:
      maxUnavailable: 1
  - tags: {}