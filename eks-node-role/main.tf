###################
# Required Variables
###################

variable "cluster_name" {
  description = "The name of the EKS Cluster"
  type        = string
}

###################
# Optional Variables
###################

variable "node_role_name" {
  description = "The name of the EKS Cluster Node role"
  default     = null
  type        = string
}

variable "additional_node_policies" {
  description = "A map of keys to ARNs of additional polices to attach to the node role.  Matching keys in this list will override the value in the default_node_policies variable."
  default     = {}
  type        = map(string)
}

variable "default_node_policies" {
  description = "A map of keys to ARNs of default polices to attach to the node role"
  default = {
    "AmazonEKS_CNI_Policy" : "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
    "AmazonEC2ContainerRegistryReadOnly" : "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
    "AmazonEKSWorkerNodePolicy" : "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
    "AmazonSSMManagedInstanceCore" : "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
  type = map(string)
}

variable "tags" {
  description = "A map of tags to add to resources"
  default     = null
  type        = map(string)
}

###################
# Locals
###################

locals {
  iam_role_name = var.node_role_name != null ? var.node_role_name : "${var.cluster_name}-eks-node-group"
  node_policies = merge(var.default_node_policies, var.additional_node_policies)
}

###################
# Create IAM Role for Nodes
###################

data "aws_partition" "current" {}

# Create IAM Node Role Trust Policy
data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    sid     = "EKSNodeAssumeRole"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.${data.aws_partition.current.dns_suffix}"]
    }
  }
}

# Create IAM Node Role
resource "aws_iam_role" "nodes" {

  name                  = local.iam_role_name
  description           = "IAM Role for EKS Nodes in the ${var.cluster_name} cluster"
  assume_role_policy    = data.aws_iam_policy_document.assume_role_policy.json
  force_detach_policies = true
  tags                  = var.tags
}

#  Attach all the node policies to the role
resource "aws_iam_role_policy_attachment" "this" {
  for_each = local.node_policies

  policy_arn = each.value
  role       = aws_iam_role.nodes.name
}

###################
# Output Variables
###################

output "arn" {
  description = "The ARN of the Node role"
  value       = aws_iam_role.nodes.arn
}

output "name" {
  description = "The name of the Node role"
  value       = aws_iam_role.nodes.name
}
