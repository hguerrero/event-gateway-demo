# Encryption Key Output
output "operations_gps_encryption_key" {
  value       = random_bytes.operations_gps_encryption_key.base64
  description = "Auto-generated 32-byte base64 encoded encryption key for operations GPS topic"
  sensitive   = true
}

# KEG Data Plane Certificate Outputs
output "keg_data_plane_cert" {
  value       = tls_self_signed_cert.keg_data_plane.cert_pem
  description = "TLS certificate for KEG data plane"
  sensitive   = true
}

output "keg_data_plane_key" {
  value       = tls_private_key.keg_data_plane.private_key_pem
  description = "TLS private key for KEG data plane"
  sensitive   = true
}

# Konnect Configuration Outputs for kubectl secret
output "konnect_gateway_cluster_id" {
  value       = konnect_event_gateway.event_gateway_terraform.id
  description = "KEG Control Plane ID for KONNECT_GATEWAY_CLUSTER_ID"
}

output "konnect_region" {
  value       = regex("https://([^.]+)", var.konnect_server_url)[0]
  description = "Konnect region extracted from server URL"
}

output "konnect_client_cert" {
  value       = replace(tls_self_signed_cert.keg_data_plane.cert_pem, "\n", "\\n")
  description = "Client certificate with escaped newlines for kubectl"
  sensitive   = true
}

output "konnect_client_key" {
  value       = replace(tls_private_key.keg_data_plane.private_key_pem, "\n", "\\n")
  description = "Client key with escaped newlines for kubectl"
  sensitive   = true
}

