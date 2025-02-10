# Local Kubernetes Development Playground

This project provides a Terraform template for setting up a local Kubernetes development playground using Minikube. It automates the process of creating a local Kubernetes environment with essential components for application deployment and management.

## Prerequisites

Before you begin, ensure you have the following installed on your local machine:

- [Terraform](https://www.terraform.io/downloads.html) (version >= 0.13.1)
- [Minikube](https://minikube.sigs.k8s.io/docs/start/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/)

## Components

This Terraform template sets up the following components in your local Minikube cluster:

1. ArgoCD: Continuous Delivery tool for Kubernetes
2. Ingress-NGINX: Ingress controller for Kubernetes
3. Cert-Manager: Certificate management for Kubernetes
4. Monitoring stack (Prometheus, Loki, and Grafana)
5. Database-Service (Postgres and MongoDB) 
6. Minio: High Performance Object Storage tools

## Getting Started

1. Clone this repository:
```bash
git clone https://github.com/sliterentz/dev_playground.git
cd dev_playground
```
2. Initialize Terraform:
```bash
terraform init
```
3. Review and modify the `variables.tf` and `kubernetes.tf` file to customize your setup if needed.
4. Apply the Terraform configuration:
```bash
terraform apply
```
5. Once the apply is complete, make sure you minikube already start 
```bash
minikube start
minikube status
```
6. Now you can access your local Kubernetes playground.

## Accessing Services

- ArgoCD: Access via `https://argocd.local` (default)
- Grafana: Access via `https://grafana.local` (default)

Note: You may need to add these domains to your `/etc/hosts` file pointing to your Minikube IP.

### Port Forwarding for GUI Access
To access services using GUI tools, you can use port forwarding. Here are the commands for key services:
1. ArgoCD Server:
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```
Access ArgoCD UI at http://localhost:8080
2. Grafana:
```bash
kubectl port-forward svc/grafana -n monitoring 3000:80
```
Access Grafana UI at http://localhost:3000
3. Database Services:
PostgreSQL:
```bash
kubectl port-forward svc/postgres -n database 5432:5432
```
Connect to PostgreSQL on localhost:5432
MongoDB:
```bash
kubectl port-forward svc/mongodb -n database 27017:27017
```
Connect to MongoDB on localhost:27017
4. Minio:
```bash
kubectl port-forward svc/minio -n storage 9000:9000 9001:9001
```
Access Minio Console at http://localhost:9001 and use port 9000 for S3 API

## Customization

You can customize various aspects of the playground by modifying the variables in `variables.tf`. Key customizable elements include:

- ArgoCD version and configuration
- Ingress settings
- Cert-manager configuration
- Monitoring stack settings
- Your application repo

## Cleaning Up

To tear down the playground and remove all resources:
```bash
terraform destroy
```

## Contributing

Contributions to improve this local development playground are welcome. Please feel free to submit issues or pull requests.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.