###################
# Required Variables
###################

variable "cluster_config" {
  description = "The object containing the configuration to be used for terraforming an EKS cluster and other associated resources."
  type = object({
    # AWS region, the logical grouping for resources and the environment for the Terraforming
    region                          = string
    # The namespace value MUST match the name of an entry in the VPC's shared_clusters list
    namespace                       = string
    # The environment this cluster will be terraformed in
    env                             = string
    # ID of the VPC the EKS cluster will be created in
    vpc_id                          = string
    # CIDR block of the VPC the EKS cluster will be created in
    vpc_cidr_block                  = string
    # List of private subnet IDs used for creating nodes in
    private_subnets                 = list(string)
    # The name of the EKS cluster
    cluster_name                    = string
    # Kubernetes Cluster Version
    cluster_version                 = string
    # Enable Private API Server Access
    cluster_endpoint_private_access = optional(bool, true)
    # Enable Public API Server Access
    cluster_endpoint_public_access  = optional(bool, true)
    # Declare a list of Control Plane logs to create
    cluster_enabled_log_types       = optional(list(string), ["api", "audit", "authenticator"])
    # Create, update, and delete timeout configurations for the cluster
    cluster_timeouts                = optional(map(string), {})
    # Default Tags for Cluster Resources
    tags                            = optional(map(string), {})
    # Tags to apply for Internet-Facing AWS Load Balancers to use the public subnets
    public_subnet_tags              = optional(map(string), {})
    # Tags to apply for Internal-Facing AWS Load Balancers to use the private subnets
    private_subnet_tags             = optional(map(string), {})
    # Tagging the VPC that multiple cluster could be deployed in the same VPC
    vpc_tags                        = optional(map(string), {})
    # An Initial Managed Node Group Configuration
    managed_node_group              = object({
      name                   = optional(string, null)
      min_size               = optional(number, 3)
      desired_size           = optional(number, 3)
      max_size               = optional(number, 3)
      ami_type               = optional(string, "AL2_x86_64")
      instance_types         = optional(list(string), ["m6a.4xlarge", "m5a.4xlarge", "m6i.4xlarge", "m5.4xlarge"])
      vpc_security_group_ids = optional(list(string), [])
      capacity_type          = optional(string, "ON_DEMAND")
      volume_size            = optional(number, 50)
      volume_type            = optional(string, "gp3")
      iops                   = optional(number, 3000)
      throughput             = optional(number, 125)
    })
  })
}

###################
# Locals
###################

locals {
  # We do the following to be sure that the VPC config has been updated to label the subnets with the cluster name.
  cluster_name = var.cluster_config.cluster_name
  tags         = var.cluster_config.tags
  cluster_tags = merge(local.tags, {
    managed-by  = "terraform"
    ClusterName = local.cluster_name
  })
  vpc_security_group_ids = var.cluster_config.managed_node_group.vpc_security_group_ids
  managed_node_group_name = var.cluster_config.managed_node_group.name == null ? "${local.cluster_name}-standard" : var.cluster_config.managed_node_group.name
}

###################
# Create IAM Managed Node Group Role
###################

module "managed_node_group_role" {
  source = "../eks-node-role"

  cluster_name = local.cluster_name
}

###################
# Create EKS Cluster without A Managed Node Group
###################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "19.5.1"

  cluster_name                    = local.cluster_name
  cluster_version                 = var.cluster_config.cluster_version
  cluster_endpoint_private_access = var.cluster_config.cluster_endpoint_private_access
  cluster_endpoint_public_access  = var.cluster_config.cluster_endpoint_public_access
  cluster_enabled_log_types       = var.cluster_config.cluster_enabled_log_types
  cluster_timeouts                = var.cluster_config.cluster_timeouts

  cluster_security_group_additional_rules = {
    # Additional ports required because EKS module version 18.0+ changes how SGs are configured.
    # See https://github.com/terraform-aws-modules/terraform-aws-eks/issues/1748 for details
    egress_nodes_ephemeral_ports_tcp = {
      description                = "To node 1025-65535"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "egress"
      source_node_security_group = true
    }
  }

  vpc_id     = var.cluster_config.vpc_id
  subnet_ids = var.cluster_config.private_subnets
  tags       = local.cluster_tags
}

###################
# Create Managed Node Group
###################

module "eks_managed_node_group" {
  source  = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"
  version = "19.5.1"

  name            = local.managed_node_group_name
  cluster_name    = local.cluster_name
  cluster_version = var.cluster_config.cluster_version
  create_iam_role = false
  iam_role_arn    = module.managed_node_group_role.arn

  // The following variables are necessary if you decide to use the module outside of the parent EKS module context.
  // Without it, the security groups of the nodes are empty and thus won't join the cluster.
  cluster_primary_security_group_id = module.eks.node_security_group_id

  subnet_ids             = var.cluster_config.private_subnets
  min_size               = var.cluster_config.managed_node_group.min_size
  desired_size           = var.cluster_config.managed_node_group.desired_size
  max_size               = var.cluster_config.managed_node_group.max_size
  ami_type               = var.cluster_config.managed_node_group.ami_type
  instance_types         = var.cluster_config.managed_node_group.instance_types
  vpc_security_group_ids = local.vpc_security_group_ids

  capacity_type         = var.cluster_config.managed_node_group.capacity_type
  block_device_mappings = {
    xvda = {
      device_name = "/dev/xvda"
      ebs = {
        volume_size           = var.cluster_config.managed_node_group.volume_size
        volume_type           = var.cluster_config.managed_node_group.volume_type
        iops                  = var.cluster_config.managed_node_group.iops
        throughput            = var.cluster_config.managed_node_group.throughput
        encrypted             = true
        delete_on_termination = true
      }
    }
  }

  depends_on = [
    module.managed_node_group_role,
  ]
}
