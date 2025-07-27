# DevSecOps CI/CD Pipeline for Vite App on AWS EKS

This repository sets up a fully automated, end-to-end DevSecOps pipeline. It's designed to take your containerized Vite web application from code to a live, secure state on AWS EKS, with security built into every step.

## 🚀 Project Goal

Our main goal was to create a smooth, fast, and secure way to deploy web applications. We built an automated pipeline that packages our app and launches it onto a robust cloud platform. Security is woven into every stage, ensuring reliable and safe deployments.

## ✨ Key Features

* **Automated Cloud Setup**: Uses **Terraform** to automatically provision and manage all necessary AWS infrastructure.
* **Continuous Delivery**: A **GitHub Actions** workflow that automates building, testing, and deploying the app.
* **Integrated Security**:
    * **`tfsec`** scans Terraform code for security misconfigurations.
    * **`Trivy`** performs vulnerability scans on Docker images.
* **Secure Secrets Management**: Implements **Sealed Secrets** to encrypt sensitive Kubernetes secrets directly into Git, keeping them safe.
* **GitOps Principle**: **ArgoCD** continuously monitors the Git repository, automatically synchronizing changes to the Kubernetes cluster.
* **Containerized App**: Your Vite application is packaged into a **Docker** image and served by **Nginx**.
* **Public Access**: The final application is made accessible via an an **AWS Elastic Load Balancer (ELB)**.

## 🏗️ How It Works (Solution Architecture)

Our system runs on a **GitOps model**, meaning our Git repository is the single source of truth for everything – your application and its entire cloud setup.

1.  **Code Commit**: You push your application code, Dockerfile, and Kubernetes configurations to GitHub.
2.  **GitHub Actions (Our Automation Engine)**: This pipeline automatically triggers:
    * It runs **security scans** (`tfsec` on infrastructure code, `Trivy` on Docker images).
    * It **builds your Vite app into a Docker image** and pushes it to **AWS ECR**.
    * It **encrypts your application secrets** (from GitHub Secrets) into `SealedSecret` manifests using `kubeseal` and pushes them back to Git.
    * It **updates your Kubernetes deployment file** in Git with the new image tag and the encrypted secret.
3.  **Terraform (Our Cloud Builder)**: Manages your AWS infrastructure. It sets up your **VPC**, **EKS cluster** (`vite-app-cluster-v2`), and **ECR**. It also deploys **ArgoCD** and the **Sealed Secrets controller** into your EKS cluster.
4.  **ArgoCD (Our GitOps Orchestrator)**: Living inside EKS, ArgoCD constantly watches your Git repository. When it sees updates (like a new image or sealed secret), it automatically pulls those changes and applies them to the live application in Kubernetes. The Sealed Secrets controller then decrypts your secrets for the running app.
5.  **Public Access**: Your application is then made accessible to users globally via an **AWS Load Balancer**.

## 🛠️ Technologies Used

* **Cloud Provider**: AWS
* **Infrastructure as Code**: Terraform
* **Container Orchestration**: Kubernetes (AWS EKS)
* **Container Registry**: AWS ECR
* **CI/CD**: GitHub Actions
* **GitOps**: ArgoCD
* **Secret Management**: Bitnami Sealed Secrets (`kubeseal` CLI, `sealed-secrets-controller`)
* **Security Scanning**: `tfsec`, `Trivy`
* **Web App**: Vite
* **Web Server**: Nginx
* **CLI Tools**: AWS CLI, `kubectl`, `helm`, `curl`

## 🚀 Getting Started

### 📋 Prerequisites

Make sure you have these installed locally:

* [**AWS CLI**](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) (configured)
* [**Terraform**](https://developer.hashicorp.com/terraform/downloads) (v1.0+)
* [**kubectl**](https://kubernetes.io/docs/tasks/tools/install-kubectl/) (compatible with EKS 1.27)
* [**Helm**](https://helm.sh/docs/intro/install/) (v3.0+)
* [**Docker Desktop**](https://www.docker.com/products/docker-desktop/)
* [**Git Bash**](https://git-scm.com/downloads) (recommended for Windows)

### ☁️ AWS Setup

1.  **Configure AWS CLI**:
    ```bash
    aws configure
    # Enter your Access Key ID, Secret Access Key, and region (e.g., us-east-1)
    ```
    Verify your identity:
    ```bash
    aws sts get-caller-identity
    ```

2.  **Create GitHub Repository Secrets**:
    Go to your GitHub repository: `Settings` > `Secrets and variables` > `Actions` > `New repository secret`. Add:
    * `AWS_ACCESS_KEY_ID`
    * `AWS_SECRET_ACCESS_KEY`
    * `AWS_ACCOUNT_ID` (your 12-digit account ID)
    * `VITE_APP_API_KEY_VALUE` (the **plain, unencoded** secret value for your app)
    * `GH_PAT` (GitHub Personal Access Token with `repo` scope)

### ⚙️ Local Repository Setup

1.  **Clone this Repository**:
    ```bash
    git clone https://github.com/DPEDITS/DEVOPS.git
    cd DEVOPS
    ```
2.  **Create Your Vite Application**:
    Ensure your Vite app code is in the `app/` directory. If not, create a basic one:
    ```bash
    mkdir app && cd app
    npm create vite@latest . -- --template react # Follow prompts
    npm install
    cd .. # Go back to repo root
    ```
3.  **Verify `k8s/argocd-app.yaml`**:
    Open it and ensure `repoURL` points to `https://github.com/DPEDITS/DEVOPS.git` (your actual repo).

### 🚀 Deployment Steps

1.  **Deploy AWS Infrastructure with Terraform**:
    Navigate to the `infra/` directory:
    ```bash
    cd infra
    terraform init
    terraform plan
    terraform apply --auto-approve
    ```
    *(This takes 20-40 minutes for EKS cluster setup. Wait for completion.)*

2.  **Trigger CI/CD Pipeline via Git Push**:
    Once Terraform finishes, navigate back to the **root** of your `DEVOPS` repository:
    ```bash
    cd .. # If you are in infra/
    git add .
    git commit -m "Initial infrastructure and CI/CD pipeline deployed, triggering app deployment"
    git push origin main
    ```
    * If push fails due to remote changes:
        ```bash
        git pull origin main --rebase
        git push origin main
        ```

### 📈 Monitoring & Access

1.  **Monitor GitHub Actions**: Go to your GitHub repo's "Actions" tab to watch the pipeline run.
2.  **Access ArgoCD UI**:
    * Get admin password:
        ```bash
        kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
        ```
    * Port-forward UI (run in a separate terminal and keep it open):
        ```bash
        nohup kubectl port-forward svc/argocd-server -n argocd 8081:443 >/dev/null 2>&1 &
        ```
    * Open `https://localhost:8081` in your browser. Login with `admin` and the password.
    * Your `vite-app` application should eventually show `Synced` and `Healthy`.

3.  **Verify Kubernetes Resources**:
    In your Git Bash terminal:
    ```bash
    kubectl get deployment vite-app-deployment -n default
    kubectl get service vite-app-service -n default
    kubectl get sealedsecret vite-app-api-secret -n default # Should exist
    kubectl get secret vite-app-api-secret -n default # Should exist (decrypted by controller)
    # Verify the decrypted secret content
    kubectl get secret vite-app-api-secret -n default -o jsonpath="{.data.API_KEY}" | base64 -d
    # Check application pods
    kubectl get pods -l app=vite-app -n default
    ```
4.  **Access Your Application**:
    * Get ELB URL:
        ```bash
        kubectl get service vite-app-service -n default -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
        ```
    * Open this URL in your web browser. Your Vite application should be live!

## 🧹 Cleanup

To destroy all provisioned AWS resources and Kubernetes components:

1.  **Navigate to the `infra/` directory**:
    ```bash
    cd infra
    ```
2.  **Run Terraform Destroy**:
    ```bash
    terraform destroy --auto-approve
    ```
    *(This also takes 20-40 minutes for EKS teardown.)*

## ⚠️ Troubleshooting

* **`ERR_EMPTY_RESPONSE` or `0/2 READY` Pods**: This indicates your application pods are not running or healthy.
    * Check `kubectl get pods -l app=vite-app -n default` for pod status (e.g., `CrashLoopBackOff`, `ImagePullBackOff`).
    * Use `kubectl describe pod <pod-name> -n default` to see events and detailed errors.
    * Check `kubectl logs <pod-name> -n default` for application logs.
    * Verify `kubectl get secret vite-app-api-secret -n default` and `kubectl get sealedsecret vite-app-api-secret -n default` to ensure the secret is present and decrypted.
    * Check ArgoCD UI for sync errors or health issues.
* **GitHub Actions Workflow Failures**:
    * Always check the detailed logs of the failing step in the GitHub Actions UI.
    * Look for specific error messages from `tfsec`, `Trivy`, `aws cli`, `kubectl`, `helm`, or `kubeseal`.
    * Pay close attention to `--- kubeseal debug output ---` if `kubeseal` fails.
* **`kubeseal: command not found` (locally)**: Ensure you've followed the local `kubeseal` installation steps correctly, especially moving `kubeseal.exe` to `~/bin` and adding `~/bin` to your `PATH`.
* **`Exec format error` (locally for `kubeseal`)**: You downloaded the wrong binary. Ensure you download `kubeseal-windows-amd64.exe` (not `linux-amd64.tar.gz`) for local use on Windows.
* **`Invalid workflow file: .github/workflows/main.yml#LXXX`**: This is a YAML syntax error. Carefully check the indentation and syntax around the specified line number. Copying the provided `main.yml` exactly should prevent this.
* **`i/o timeout` connecting to EKS API**: Ensure your EKS cluster endpoint is publicly accessible (`cluster_endpoint_public_access = true` and `public_access_cidrs = ["0.0.0.0/0"]` in `infra/main.tf`). Also, check any local firewalls or VPNs.
