resource "konnect_event_gateway" "event_gateway_terraform" {
  provider = konnect-beta
  name     = "event_gateway_tf_test"
}

resource "konnect_event_gateway_backend_cluster" "backend_cluster" {
  provider    = konnect-beta
  name        = "backend_cluster"
  description = "terraform cluster"
  gateway_id  = konnect_event_gateway.event_gateway_terraform.id

  insecure_allow_anonymous_virtual_cluster_auth = true

  authentication = {
    anonymous = {}
  }

  bootstrap_servers = [
    "kafka1:9092",
    "kafka2:9092",
    "kafka3:9092"
  ]

  tls = {
    enabled = false
  }

}

resource "konnect_event_gateway_virtual_cluster" "operations_team_vc" {
  name     = "Operations-Team"
  provider = konnect-beta
  acl_mode = "passthrough"
  authentication = [
    {
      anonymous = {}
    }
  ]
  destination = {
    id = konnect_event_gateway_backend_cluster.backend_cluster.id
  }
  dns_label = "operations"
  labels = {
  }
  namespace = {
    additional = {
      topics = [
        {
          exact_list = {
            exact_list = [
              {
                backend = "delivery-updates"
              }
            ]
          }
        }
      ]
    }
    mode   = "hide_prefix"
    prefix = "operations-"
  }
  gateway_id = konnect_event_gateway.event_gateway_terraform.id
}

resource "konnect_event_gateway_virtual_cluster" "analytics_team_vc" {
  name     = "Analytics-Team"
  provider = konnect-beta
  acl_mode = "passthrough"
  authentication = [
    {
      anonymous = {}
    }
  ]
  destination = {
    id = konnect_event_gateway_backend_cluster.backend_cluster.id
  }
  dns_label = "analytics"
  labels = {
  }
  namespace = {
    additional = {
    }
    mode   = "hide_prefix"
    prefix = "analytics-"
  }
  gateway_id = konnect_event_gateway.event_gateway_terraform.id
}

resource "konnect_event_gateway_virtual_cluster" "external_partners_vc" {
  name     = "External-Partners"
  provider = konnect-beta
  acl_mode = "passthrough"
  authentication = [
    {
      anonymous = {}
    }
  ]
  destination = {
    id = konnect_event_gateway_backend_cluster.backend_cluster.id
  }
  dns_label = "partners"
  labels = {
  }
  namespace = {
    additional = {
      topics = [
        {
          exact_list = {
            exact_list = [
              {
                backend = "delivery-updates"
              }
            ]
          }
        }
      ]
    }
    mode   = "hide_prefix"
    prefix = "partners-"
  }
  gateway_id = konnect_event_gateway.event_gateway_terraform.id
}

// Internal listener with policies set up for SNI
resource "konnect_event_gateway_listener" "internal_listener" {
  provider = konnect-beta
  addresses = [
    "0.0.0.0"
  ]
  description = "listener for internal clients"
  labels = {
  }
  name = "Internal"
  ports = [
    "9092"
  ]
  gateway_id = konnect_event_gateway.event_gateway_terraform.id
}
resource "konnect_event_gateway_listener_policy_tls_server" "my_eventgatewaylistenerpolicytlsserver" {
  provider = konnect-beta
  config = {
    allow_plaintext = false
    certificates = [
      {
        certificate = "$${env[\"KEG_TLS_INTERNAL_CERT\"]}"
        key         = "$${env[\"KEG_TLS_INTERNAL_KEY\"]}"
      }
    ]
    versions = {
      max = "TLSv1.3"
      min = "TLSv1.2"
    }
  }
  enabled = true
  labels = {
  }
  name                      = "Internal TLS Server"
  gateway_id                = konnect_event_gateway.event_gateway_terraform.id
  event_gateway_listener_id = konnect_event_gateway_listener.internal_listener.id
}
resource "konnect_event_gateway_listener_policy_forward_to_virtual_cluster" "internal_listener_policy_forward_to_virtual_cluster" {
  provider = konnect-beta
  name     = "Internal Listener Policy Forward to Virtual Cluster"
  config = {
    sni = {
      sni_suffix = ".svc.cluster.local"
    }
  }
  enabled = true
  labels = {
  }
  gateway_id                = konnect_event_gateway.event_gateway_terraform.id
  event_gateway_listener_id = konnect_event_gateway_listener.internal_listener.id
}




// External listener with policies set up for SNI
resource "konnect_event_gateway_listener" "external_listener" {
  provider = konnect-beta
  addresses = [
    "0.0.0.0"
  ]
  description = "listener for external clients"
  labels = {
  }
  name = "External"
  ports = [
    "9094"
  ]
  gateway_id = konnect_event_gateway.event_gateway_terraform.id
}
resource "konnect_event_gateway_listener_policy_tls_server" "external_listener_policy_tls_server" {
  provider = konnect-beta
  config = {
    allow_plaintext = false
    certificates = [
      {
        certificate = "$${env[\"KEG_TLS_EXTERNAL_CERT\"]}"
        key         = "$${env[\"KEG_TLS_EXTERNAL_KEY\"]}"
      }
    ]
    versions = {
      max = "TLSv1.3"
      min = "TLSv1.2"
    }
  }
  enabled = true
  labels = {
  }
  name                      = "External TLS Server"
  gateway_id                = konnect_event_gateway.event_gateway_terraform.id
  event_gateway_listener_id = konnect_event_gateway_listener.external_listener.id
}
resource "konnect_event_gateway_listener_policy_forward_to_virtual_cluster" "external_listener_policy_forward_to_virtual_cluster" {
  provider = konnect-beta
  name     = "External Listener Policy Forward to Virtual Cluster"
  config = {
    sni = {
      sni_suffix = ".127-0-0-1.sslip.io"
    }
  }
  enabled = true
  labels = {
  }
  gateway_id                = konnect_event_gateway.event_gateway_terraform.id
  event_gateway_listener_id = konnect_event_gateway_listener.external_listener.id
}

# Resources for use in policies
resource "konnect_event_gateway_static_key" "operations_gps_encryption_key" {
  provider   = konnect-beta
  name       = "operations-gps-key-${formatdate("YYYYMMDDhhmmss", timestamp())}"
  gateway_id = konnect_event_gateway.event_gateway_terraform.id
  value      = var.operations_gps_encryption_key

  lifecycle {
    create_before_destroy = true
    # TODO: Remove this and the timestamp in the name once we can update the key resource without a naming conflict
    ignore_changes = [name]
  }
}

# Operations VC Policies
resource "konnect_event_gateway_produce_policy_encrypt" "operations_gps_encrypt" {
  provider           = konnect-beta
  name               = "operations-gps-encrypt"
  description        = "Policy to encrypt operations GPS topic"
  gateway_id         = konnect_event_gateway.event_gateway_terraform.id
  virtual_cluster_id = konnect_event_gateway_virtual_cluster.operations_team_vc.id

  enabled   = true
  condition = "context.topic.name == 'vehicle-gps'"
  config = {
    failure_mode   = "passthrough"
    part_of_record = ["value"]
    encryption_key = {
      static = {
        key = {
          reference_by_id = {
            id = konnect_event_gateway_static_key.operations_gps_encryption_key.id
          }
        }
      }
    }
  }
}

resource "konnect_event_gateway_consume_policy_decrypt" "operations_gps_decrypt" {
  provider           = konnect-beta
  name               = "operations-gps-decrypt"
  description        = "Policy to decrypt operations GPS topic"
  gateway_id         = konnect_event_gateway.event_gateway_terraform.id
  virtual_cluster_id = konnect_event_gateway_virtual_cluster.operations_team_vc.id

  enabled   = true
  condition = "context.topic.name == 'vehicle-gps'"
  config = {
    failure_mode   = "passthrough"
    part_of_record = ["value"]
    key_sources = [{
      static = {}
      }
    ]
  }
}




# resource "konnect_event_gateway_schema_registry" "schema_reg" {
#   provider   = konnect-beta
#   gateway_id = konnect_event_gateway.event_gateway_terraform.id
#   confluent = {
#     name        = "schema_registry"
#     description = "confluent schema registry"
#     config = {
#       endpoint    = "http://schema-registry:8081"
#       schema_type = "json"
#       authentication = {
#         basic = {
#           username = "alice"
#           password = "alice_secret"
#         }
#       }
#     }
#   }
# }

# resource "konnect_event_gateway_static_key" "transactions_encryption_key" {
#   provider    = konnect-beta
#   name        = "transactions_encryption_key"
#   description = "Encryption key for transactions topic"
#   gateway_id  = konnect_event_gateway.event_gateway_terraform.id

#   value = "$${vault.env['KONNECT_TRANSACTION_ENCRYPTION_KEY']}"
# }

# // Policies

# resource "konnect_event_gateway_cluster_policy_acls" "acl_topic_policy_analytics" {
#   provider           = konnect-beta
#   name               = "analytics_acl_topic_policy"
#   description        = "ACL policy for ensuring access to topics"
#   gateway_id         = konnect_event_gateway.event_gateway_terraform.id
#   virtual_cluster_id = konnect_event_gateway_virtual_cluster.analytics_virtual_cluster.id

#   condition = "context.auth.principal.name == \"analytics_username\""
#   config = {
#     rules = [
#       {
#         action = "allow"
#         operations = [
#           { name = "describe" },
#           { name = "describe_configs" },
#           { name = "read" },
#           { name = "write" }
#         ]
#         resource_type = "topic"
#         resource_names = [{
#           match = "*"
#         }]
#       }
#     ]
#   }
# }

# resource "konnect_event_gateway_cluster_policy_acls" "acl_topic_policy_payments" {
#   provider           = konnect-beta
#   name               = "payments_acl_topic_policy"
#   description        = "ACL policy for ensuring access to topics"
#   gateway_id         = konnect_event_gateway.event_gateway_terraform.id
#   virtual_cluster_id = konnect_event_gateway_virtual_cluster.payments_virtual_cluster.id

#   config = {
#     rules = [
#       {
#         action = "allow"
#         operations = [
#           { name = "describe" },
#           { name = "describe_configs" },
#           { name = "read" },
#           { name = "write" }
#         ]
#         resource_type = "topic"
#         resource_names = [{
#           match = "*"
#         }]
#       },
#       {
#         action = "deny"
#         operations = [
#           { name = "write" }
#         ]
#         resource_type = "topic"
#         resource_names = [{
#           match = "user_actions"
#         }]
#       }
#     ]
#   }
# }

# resource "konnect_event_gateway_produce_policy_encrypt" "payments_encrypt_transactions" {
#   provider           = konnect-beta
#   name               = "payments_encrypt_transactions"
#   description        = "Policy to encrypt transaction data on payments produced"
#   gateway_id         = konnect_event_gateway.event_gateway_terraform.id
#   virtual_cluster_id = konnect_event_gateway_virtual_cluster.payments_virtual_cluster.id

#   condition = "context.topic.name == \"transactions\""
#   config = {
#     failure_mode   = "error"
#     part_of_record = ["value"]
#     encryption_key = {
#       static = {
#         key = {
#           reference_by_id = {
#             id = konnect_event_gateway_static_key.transactions_encryption_key.id
#           }
#         }
#       }
#     }
#   }
# }

# resource "konnect_event_gateway_consume_policy_decrypt" "payments_decrypt_transactions" {
#   provider           = konnect-beta
#   name               = "payments_decrypt_transactions"
#   description        = "Policy to decrypt transaction data on payments produced"
#   gateway_id         = konnect_event_gateway.event_gateway_terraform.id
#   virtual_cluster_id = konnect_event_gateway_virtual_cluster.payments_virtual_cluster.id

#   condition = "context.topic.name == \"transactions\""
#   config = {
#     failure_mode   = "error"
#     part_of_record = ["value"]
#     key_sources = [{
#       static = {}
#     }]
#   }
# }

# resource "konnect_event_gateway_consume_policy_skip_record" "payments_skip_records" {
#   provider           = konnect-beta
#   name               = "payments_skip_records"
#   description        = "Policy to skip records based on header"
#   gateway_id         = konnect_event_gateway.event_gateway_terraform.id
#   virtual_cluster_id = konnect_event_gateway_virtual_cluster.payments_virtual_cluster.id

#   condition = "record.headers['sensitive'] == '1'"
# }

# /*
# resource "konnect_event_gateway_produce_policy_schema_validation" "schema_val" {
#     provider = konnect-beta
#     name = "schema_val"
#     description = "schema validation"
#     gateway_id = konnect_event_gateway.event_gateway_terraform.id
#     virtual_cluster_id = konnect_event_gateway_virtual_cluster.analytics_virtual_cluster.id

#     config = {
#       confluent_schema_registry = {
#         schema_registry = {
#           schema_registry_reference_by_name = {
#             name = "schema_registry"
#           }
#         }
#         value_validation_action = "reject"
#       }
#     }

# }
# */

# output "KONNECT_CONTROL_PLANE_ID" {
#   value = konnect_event_gateway.event_gateway_terraform.id
# }

# output "KONNECT_TRANSACTION_ENCRYPTION_KEY" {
#   value = file("./enc.key")
# }
