# eks.tf

# Retrieves your current AWS CLI credentials to make you the cluster admin
data "aws_caller_identity" "current" {}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "eks-enterprise"
  cluster_version = "1.31"

  # Network integration: Connect EKS to the VPC created in main.tf
  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets
  
  # Add this block to tag the Node Security Group so Karpenter can discover it
  node_security_group_tags = {
    "karpenter.sh/discovery" = "eks-enterprise"
  }
  
  # Allow local kubectl access from your ThinkPad workstation
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # Enterprise Standard: Modern Access Entries (replaces aws-auth)
  enable_cluster_creator_admin_permissions = false
  access_entries = {
    admin = {
      principal_arn = data.aws_caller_identity.current.arn
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  # Add this block inside module "eks" to ensure networking starts correctly
  cluster_addons = {
    coredns                = { most_recent = true }
    kube-proxy             = { most_recent = true }
    eks-pod-identity-agent = { most_recent = true }
    vpc-cni = { 
      most_recent = true
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
  }

  # System Node Group: Updated for strict Free Tier compliance
  eks_managed_node_groups = {
    system = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["t3.micro"] # Explicit Free Tier instances (Nitro required for prefix delegation)
      min_size       = 2
      max_size       = 5
      desired_size   = 4 
      subnet_ids     = module.vpc.private_subnets
    }
  }
}

# Add this to the bottom of eks.tf
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.0"

  cluster_name = module.eks.cluster_name

  # Enterprise Standard: EKS Pod Identity for the Karpenter controller
  enable_pod_identity             = true
  create_pod_identity_association = true
  namespace                       = "karpenter" # Explicitly match the Helm deployment namespace

  # Role attached to the EC2 instances provisioned by Karpenter
  node_iam_role_name = "karpenter-node-role-${module.eks.cluster_name}"
  node_iam_role_use_name_prefix = false # Forces the exact role name match
  
  # Allow Karpenter to terminate nodes via SQS/EventBridge
  enable_irsa = false

  # Add this flag to grant the controller the required v1 IAM permissions
  enable_v1_permissions = true

  tags = {
    Environment = "production"
  }
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}
# Supplemental policy for newer Karpenter v1.15+ permissions missing from the v20.0 module
resource "aws_iam_role_policy" "karpenter_supplemental" {
  name = "karpenter-v1-15-supplemental"
  # Dynamically references the controller role created by the module
  role = module.karpenter.iam_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstanceStatus",
          "iam:ListInstanceProfiles"
        ]
        Resource = "*"
      }
    ]
  })
}
