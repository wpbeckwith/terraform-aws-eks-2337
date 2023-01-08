###################
# Required Providers
###################

terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      version = ">= 4.34.0"
      source  = "hashicorp/aws"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.16.1"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.0.4"
    }
    kustomization = {
      source  = "kbst/kustomization"
      version = "0.9.0"
    }
  }
}

###################
# Locals
###################

locals {
  cluster_name = "karpenter-demo"

  # Used to determine correct partition (i.e. - `aws`, `aws-gov`, `aws-cn`, etc.)
  partition = data.aws_partition.current.partition

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)
}

data "aws_partition" "current" {}
data "aws_availability_zones" "available" {}

###################
# Create VPC
###################

module "vpc" {
  # https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.18.1"

  name = local.cluster_name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    # Tags subnets for Karpenter auto-discovery
    "karpenter.sh/discovery" = "true"
  }
}

module "eks" {
  source = "./eks-cluster2"

  cluster_config = {
    region          = "us-east-1"
    namespace       = "karpenter-demo"
    env             = "dev"
    vpc_id          = module.vpc.vpc_id
    vpc_cidr_block  = module.vpc.vpc_cidr_block
    private_subnets = module.vpc.private_subnets

    cluster_name               = local.cluster_name
    cluster_version            = "1.24"
    create_karpenter_node_role = true
    managed_node_group = {
    }
  }
}
