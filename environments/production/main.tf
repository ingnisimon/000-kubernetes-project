# main.tf
data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "eks-enterprise-vpc"
  cidr = "10.0.0.0/16"

  # Enterprise Standard: Deploy across 3 Availability Zones
  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = ["10.0.0.0/20", "10.0.16.0/20", "10.0.32.0/20"]
  public_subnets  = ["10.0.253.0/24", "10.0.254.0/24", "10.0.255.0/24"]

  # High Availability NAT Configuration: 1 NAT Gateway per AZ
  enable_nat_gateway     = true
  single_nat_gateway     = false
  one_nat_gateway_per_az = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  # CRITICAL: Tags required for EKS and Kubernetes Load Balancers
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery"          = "eks-enterprise" # Allows Karpenter to discover subnets for dynamic scaling
  }
}

output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "List of IDs of private subnets"
  value       = module.vpc.private_subnets
}
