module "loadtest" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints?ref=v4.11.0"

  # EKS Cluster VPC and Subnet mandatory config
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnets

  # EKS CLUSTER VERSION
  cluster_version = "1.23"

  cluster_name = var.cluster_name

  # EKS MANAGED NODE GROUPS
  managed_node_groups = {
    ondemand = {
      node_group_name = "${var.cluster_name}-managed-ondemand"
      min_size        = 1
      max_size        = 3
      desired_size    = 1
      subnet_ids      = module.vpc.private_subnets
      capacity_type   = "SPOT"
      instance_types  = ["m5.large", "m4.large", "m6a.large", "m5a.large", "m5d.large"] // Instances with same specs for memory and CPU so Cluster Autoscaler scales efficiently
      disk_size       = 100                                                             # disk_size will be ignored when using Launch Templates  
    }

    spot = {
      node_group_name = "${var.cluster_name}-managed-spot"
      min_size        = 1
      max_size        = 10
      desired_size    = 1
      subnet_ids      = module.vpc.private_subnets
      capacity_type   = "SPOT"
      instance_types  = ["m5.large", "m4.large", "m6a.large", "m5a.large", "m5d.large"]    // Instances with same specs for memory and CPU so Cluster Autoscaler scales efficiently
      disk_size       = 100                                                                # disk_size will be ignored when using Launch Templates  
      k8s_taints      = [{ key = "spotInstance", value = "true", effect = "NO_SCHEDULE" }] // Avoid scheduling stateful workloads in SPOT nodes
    }
  }
}


# Add-ons
module "kubernetes_addons" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/kubernetes-addons?ref=v4.11.0"

  eks_cluster_id = module.loadtest.eks_cluster_id

  # EKS Add-ons
  enable_amazon_eks_vpc_cni    = true
  enable_amazon_eks_coredns    = true
  enable_amazon_eks_kube_proxy = true
  enable_argocd                = true
  argocd_manage_add_ons        = true

  argocd_applications = {
    loadtest-apps = {
      path            = "."
      repo_url        = "https://github.com/18F/identity-loadtest.git"
      type            = "kustomize"
      target_revision = "main"
    }

    # Below are all magic add-ons that you can see how to configure here:
    # https://github.com/aws-ia/terraform-aws-eks-blueprints/tree/main/docs/add-ons
    addons = {
      path               = "chart"
      repo_url           = "https://github.com/aws-samples/eks-blueprints-add-ons.git"
      add_on_application = true # Indicates the root add-on application.
      values = {
        metricsServer = {
          enable = true
        }
      }
    }
  }
}

locals {
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)
  vpc_cidr = "10.0.0.0/16"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name = var.cluster_name
  cidr = local.vpc_cidr

  azs             = local.azs
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 10)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  # Manage so we can name
  manage_default_network_acl    = true
  default_network_acl_tags      = { Name = "${var.cluster_name}-default" }
  manage_default_route_table    = true
  default_route_table_tags      = { Name = "${var.cluster_name}-default" }
  manage_default_security_group = true
  default_security_group_tags   = { Name = "${var.cluster_name}-default" }

  public_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = 1
  }

  tags = {
    Name = "${var.cluster_name}-vpcstuff"
  }
}