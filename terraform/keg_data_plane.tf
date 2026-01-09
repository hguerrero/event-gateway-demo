# KEG Data Plane Certificate Management
# This file manages TLS certificate for the Kong Event Gateway data plane

# Generate private key for data plane certificate
# Equivalent to: openssl req -new -x509 -nodes -newkey rsa:2048
resource "tls_private_key" "keg_data_plane" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Generate self-signed certificate for data plane
# Equivalent to: -subj "/CN=event-gateway/C=US" -keyout "key.crt" -out "tls.crt"
resource "tls_self_signed_cert" "keg_data_plane" {
  private_key_pem = tls_private_key.keg_data_plane.private_key_pem

  subject {
    common_name = "event-gateway"
    country     = "US"
  }

  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}



# Local file outputs for easy access
# Saves certificates similar to: -out "tls.crt" -keyout "key.crt"
resource "local_file" "keg_data_plane_cert" {
  content         = tls_self_signed_cert.keg_data_plane.cert_pem
  filename        = "${path.module}/certs/tls.crt"
  file_permission = "0644"
}

resource "local_file" "keg_data_plane_key" {
  content         = tls_private_key.keg_data_plane.private_key_pem
  filename        = "${path.module}/certs/key.crt"
  file_permission = "0600"
}

# Create KEG data plane certificate in Konnect
resource "konnect_event_gateway_data_plane_certificate" "keg_data_plane_cert" {
  provider    = konnect-beta
  certificate = tls_self_signed_cert.keg_data_plane.cert_pem
  gateway_id  = konnect_event_gateway.event_gateway_terraform.id
  name        = "KEG Data Plane Certificate"
}


