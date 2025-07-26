terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

data "aws_availability_zones" "available" {}

resource "aws_ecr_repository" "app_repo" {
  name = var.ecr_repo_name

  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  force_delete = true
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.9.0"

  name = "eks-vpc"
  cidr = "10.0.0.0/16"
  azs  = slice(data.aws_availability_zones.available.names, 0, 3)

  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_flow_log      = true

  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.17.2"

  cluster_name    = var.cluster_name
  cluster_version = "1.30"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets

  cluster_endpoint_private_access        = true
  cluster_endpoint_public_access         = true
  cluster_endpoint_public_access_cidrs   = ["0.0.0.0/0"]
  cluster_enabled_log_types              = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  access_entries = {
    ClusterAdmin = {
      principal_arn = "arn:aws:iam::194644528937:user/Dev"
      policy_associations = {
        Admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  eks_managed_node_groups = {
    one = {
      min_size      = 1
      max_size      = 2
      desired_size  = 1
      instance_types = ["t3.medium"]
    }
  }
}

resource "null_resource" "argocd_install" {
  depends_on = [null_resource.wait_for_eks_ready]

  provisioner "local-exec" {
    command = <<EOT
      echo "Waiting 60 seconds before installing ArgoCD to allow cluster to stabilize..."
      sleep 60
      aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}
      for i in 1 2 3; do
        helm repo add argo https://argoproj.github.io/argo-helm && \
        helm repo update && \
        helm install argocd argo/argo-cd --namespace argocd --create-namespace --version 7.3.11 --wait && \
        break
        echo "Helm install failed. Retrying in 15 seconds..."
        sleep 15
      done
    EOT
    interpreter = ["bash", "-c"]
  }

  triggers = {
    always_run = timestamp() 
  }
}

resource "null_resource" "wait_for_eks_ready" {
  depends_on = [module.eks]

  provisioner "local-exec" {
    command = <<EOT
      echo "Waiting for EKS API endpoint DNS to be resolvable..."

      aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}
      for i in {1..20}; do
        if kubectl version --output=yaml; then
          echo "Kubernetes API is accessible."
          exit 0
        fi
        echo "Waiting for Kubernetes API... retrying in 15 seconds"
        sleep 15
      done


      echo "ERROR: EKS endpoint not resolvable after retries. Exiting."
      exit 1
    EOT
    interpreter = ["bash", "-c"]
  }

  triggers = {
    endpoint = module.eks.cluster_endpoint
  }
}


resource "null_resource" "argocd_app_deploy" {
  depends_on = [null_resource.wait_for_eks_ready, null_resource.argocd_install]

  provisioner "local-exec" {
    command = <<EOT
      echo "Checking kubeconfig for correctness..."
      if ! kubectl config view &>/dev/null; then
        echo "ERROR: Malformed kubeconfig. Run 'aws eks update-kubeconfig' and fix the file." >&2
        exit 1
      fi

      for i in 1 2 3; do
        kubectl apply -f ../argocd-app.yaml --validate=false && break
        echo "kubectl apply failed. Retrying in 15 seconds..."
        sleep 15
      done
    EOT
    interpreter = ["bash", "-c"]
  }

  triggers = {
    always_run = timestamp()
  }
}


resource "null_resource" "argocd_port_forward" {
  depends_on = [null_resource.argocd_install]

  provisioner "local-exec" {
    command = <<EOT
      aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}
      echo "Port-forwarding Argo CD server on localhost:8081..."
      nohup kubectl port-forward svc/argocd-server -n argocd 8081:443 >/dev/null 2>&1 &
    EOT
    interpreter = ["bash", "-c"]
  }

  triggers = {
    always_run = timestamp()
  }
}

resource "null_resource" "k8s_cleanup" {
  depends_on = [
    null_resource.argocd_app_deploy
  ]

  provisioner "local-exec" {
    when    = destroy
    command = <<EOT
      echo "--- Aggressive Cleanup Initiated ---"

      echo "Deleting Argo CD Application dynamically..."
      APP_NAME=$(kubectl get applications.argoproj.io -n argocd -o jsonpath='{.items[0].metadata.name}')
      if [ -n "$APP_NAME" ]; then
        kubectl delete application "$APP_NAME" -n argocd --ignore-not-found --validate=false
      fi

      echo "Uninstalling all Argo CD Helm releases dynamically..."
      helm ls -n argocd | awk 'NR>1 {print $1}' | xargs -r -n1 helm uninstall -n argocd || true
      kubectl delete namespace argocd --ignore-not-found

      echo "Deleting all Services and Deployments in default namespace..."
      kubectl delete service --all -n default --ignore-not-found
      kubectl delete deployment --all -n default --ignore-not-found

      echo "Deleting Classic Load Balancers..."
      for lb in $(aws elb describe-load-balancers --query 'LoadBalancerDescriptions[*].LoadBalancerName' --output text); do
        aws elb delete-load-balancer --load-balancer-name $lb || true
      done

      echo "Waiting for LoadBalancer deletion (2 minutes)..."
      sleep 120

      echo "Waiting 5 minutes for AWS to release Elastic IPs, ENIs, NAT Gateway..."
      sleep 300

      echo "Cleanup complete. Terraform can safely destroy resources."
    EOT
    interpreter = ["bash", "-c"]
  }
}
