output "cluster_name" {
  description = "Name of the created cluster"
  value       = "mini-cluster"
}

output "ingress_port" {
  description = "Port where ingress is bound"
  value       = var.bind_ingress_port
}

output "registry_port" {
  description = "Port where registry is bound"
  value       = var.bind_registry_port
}