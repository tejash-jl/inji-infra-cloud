provider "google" {
  project = var.project_id
  region  = var.projectInfo.region
  version = "5.44.0"
}

terraform {
  required_providers {
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~>4"
    }
  }
}

provider "google-beta" {
  project = var.project_id
  region  = var.projectInfo.region
}

data "google_service_account" "sa" {
  account_id = var.service_account
}

resource "google_compute_network" "vpc" {
  name                    = var.networkInfo.name
  project                 = var.project_id
  auto_create_subnetworks = var.networkInfo.auto_create_subnetworks
  mtu                     = var.networkInfo.mtu
}

resource "google_project_service" "servicenetworking" {
  project            = var.project_id
  service            = "servicenetworking.googleapis.com"
  disable_on_destroy = false
}

resource "google_compute_network" "private_pool_vpc" {
  name                    = "${var.projectInfo.name}-private-build-pool-vpc"
  project                 = var.project_id
  auto_create_subnetworks = false
  depends_on              = [google_project_service.servicenetworking]
}

resource "google_compute_subnetwork" "gke_subnet" {
  name          = var.networkInfo.gke_subnet.name
  project       = var.project_id
  region        = var.projectInfo.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.networkInfo.gke_subnet.ip_cidr_range
  secondary_ip_range = [
    {
      range_name    = var.networkInfo.gke_subnet.pods_ip_range.range_name
      ip_cidr_range = var.networkInfo.gke_subnet.pods_ip_range.ip_cidr_range
    },
    {
      range_name    = var.networkInfo.gke_subnet.services_ip_range.range_name
      ip_cidr_range = var.networkInfo.gke_subnet.services_ip_range.ip_cidr_range
    }
  ]
  depends_on = [
    google_compute_network.vpc
  ]
}

resource "google_compute_subnetwork" "operations_subnet" {
  name          = var.networkInfo.operations_subnet.name
  project       = var.project_id
  region        = var.projectInfo.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.networkInfo.operations_subnet.ip_cidr_range
  depends_on = [
    google_compute_network.vpc
  ]
}

resource "google_compute_network_firewall_policy" "fw_policy" {
  name        = var.firewallPolicyInfo.name
  project     = var.project_id
  description = var.firewallPolicyInfo.description
}

resource "google_compute_network_firewall_policy_association" "fw_policy_assoc" {
  name              = var.firewallPolicyAssocInfo.name
  project           = var.project_id
  attachment_target = google_compute_network.vpc.id
  firewall_policy   = google_compute_network_firewall_policy.fw_policy.name
}

resource "google_compute_network_firewall_policy_rule" "fw_rules" {
  count           = length(var.firewallRuleInfo)
  action          = var.firewallRuleInfo[count.index].action
  description     = var.firewallRuleInfo[count.index].description
  direction       = var.firewallRuleInfo[count.index].direction
  disabled        = var.firewallRuleInfo[count.index].disabled
  enable_logging  = var.firewallRuleInfo[count.index].enable_logging
  firewall_policy = google_compute_network_firewall_policy.fw_policy.name
  priority        = var.firewallRuleInfo[count.index].priority
  rule_name       = var.firewallRuleInfo[count.index].name

  match {
    src_ip_ranges  = var.firewallRuleInfo[count.index].match.src_ip_ranges
    dest_ip_ranges = var.firewallRuleInfo[count.index].match.dest_ip_ranges
    layer4_configs {
      ip_protocol = var.firewallRuleInfo[count.index].match.layer4_configs.ip_protocol
      ports       = var.firewallRuleInfo[count.index].match.layer4_configs.ports
    }
  }
}

resource "google_compute_address" "reserved_lb_public_ip" {
   for_each = { for lb in var.lbipInfo : lb.name => lb }
   name = each.key  
}

resource "google_compute_global_address" "private_ip_block" {
  provider      = google-beta
  name          = var.sql_ip_name
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
  project       = var.project_id
  depends_on = [google_compute_subnetwork.gke_subnet]
}

resource "google_service_networking_connection" "service_nw" {
  provider                = google-beta
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  depends_on              = [google_compute_global_address.private_ip_block]
  reserved_peering_ranges = [google_compute_global_address.private_ip_block.name]
}

resource "google_compute_address" "reserved_ngw_public_ip" {
  name = var.natipInfo.name
}

resource "google_compute_router" "router" {
  name       = var.routerInfo.name
  region     = var.projectInfo.region
  network    = var.networkInfo.name
  depends_on = [google_compute_network.vpc]
}

resource "google_compute_router_nat" "nat_router" {
  name   = var.routerInfo.routerNAT.name
  router = google_compute_router.router.name
  region = var.projectInfo.region

  nat_ip_allocate_option = "MANUAL_ONLY"
  nat_ips                = [google_compute_address.reserved_ngw_public_ip.self_link]

  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  subnetwork {
    name                    = google_compute_subnetwork.gke_subnet.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
  subnetwork {
    name                    = google_compute_subnetwork.operations_subnet.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
  depends_on = [google_compute_router.router]
}

resource "google_redis_instance" "cache" {
  name           = var.redisInfo.instanceName
  tier           = "BASIC"
  memory_size_gb = var.redisInfo.memorySize
  region         = var.projectInfo.region

  authorized_network = google_compute_network.vpc.id
  connect_mode       = "PRIVATE_SERVICE_ACCESS"

  redis_version = var.redisInfo.version
  display_name  = "Redis service"

  depends_on = [google_service_networking_connection.service_nw]

}

resource "google_sql_database_instance" "db_instance" {
  name             = var.sqlInfo.instanceName
  region           = var.projectInfo.region
  database_version = var.sqlInfo.version
  depends_on       = [google_service_networking_connection.service_nw]
  settings {
    tier = var.sqlInfo.settings.tier
    ip_configuration {
      ipv4_enabled                                  = var.sqlInfo.settings.ipv4_enabled
      private_network                               = google_compute_network.vpc.id
      enable_private_path_for_google_cloud_services = true
      ssl_mode                                      = "ENCRYPTED_ONLY"
    }
  }
  deletion_protection = var.sqlInfo.protection
  root_password       = random_password.password.result
}

resource "google_sql_database" "db" {
  count      = length(var.dbInfo)
  name       = var.dbInfo[count.index].name
  instance   = var.dbInfo[count.index].instanceName
  depends_on = [google_sql_database_instance.db_instance]
}

resource "google_compute_instance" "operations_vm" {
  name         = var.opsVMInfo.name
  machine_type = var.opsVMInfo.machine_type
  zone         = var.opsVMInfo.zone
  tags         = var.opsVMInfo.tags
  boot_disk {
    initialize_params {
      image = var.opsVMInfo.boot_disk.image
    }
  }
  network_interface {
    network    = google_compute_network.vpc.id
    subnetwork = google_compute_subnetwork.operations_subnet.id
    stack_type = "IPV4_ONLY"

  }
  service_account {
    email  = data.google_service_account.sa.email
    scopes = ["cloud-platform"]
  }
  metadata_startup_script = file("../../deployments/scripts/instance-startup.sh")
}

resource "google_secret_manager_secret" "secret_basic" {
  secret_id = var.secretInfo.name
  replication {
    auto {

    }

  }
}

resource "random_password" "password" {
  length           = 16
  special          = true
  override_special = "_%@"
}

resource "google_secret_manager_secret_version" "secret" {
  secret      = google_secret_manager_secret.secret_basic.id
  secret_data = random_password.password.result
}

resource "google_secret_manager_secret_iam_binding" "secret_iam_binding" {
  project   = google_secret_manager_secret.secret_basic.project
  secret_id = google_secret_manager_secret.secret_basic.secret_id
  role      = "roles/secretmanager.secretAccessor"
  members = [
    "serviceAccount:${data.google_service_account.sa.email}",
  ]
}

resource "google_sql_user" "users" {
  name            = "registry"
  instance        = google_sql_database_instance.db_instance.name
  password        = random_password.password.result
  deletion_policy = "ABANDON"
  depends_on      = [google_sql_database_instance.db_instance]
}

resource "google_container_cluster" "gke_cluster" {
  name     = var.clusterInfo.name
  project  = var.project_id
  location = var.projectInfo.region
  release_channel {
    channel = var.clusterInfo.release_channel
  }
  initial_node_count = var.clusterInfo.initial_node
  #     deletion_protection = false
  remove_default_node_pool = var.clusterInfo.remove_default_pool
  networking_mode          = var.clusterInfo.networking_mode
  network                  = google_compute_network.vpc.name
  subnetwork               = google_compute_subnetwork.gke_subnet.name

  dynamic "private_cluster_config" {
    for_each = (var.clusterInfo.private_cluster_config == null) ? [] : [1]
    content {
      enable_private_nodes    = var.clusterInfo.private_cluster_config.enable_private_nodes
      enable_private_endpoint = var.clusterInfo.private_cluster_config.enable_private_endpoint
      master_ipv4_cidr_block  = var.clusterInfo.private_cluster_config.master_ipv4_cidr_block
      master_global_access_config {
        enabled = var.clusterInfo.private_cluster_config.master_global_access_config
      }
    }
  }
  dynamic "master_authorized_networks_config" {
    for_each = (var.clusterInfo.master_authorized_networks_config == null) ? [] : [1]
    content {
      gcp_public_cidrs_access_enabled = var.clusterInfo.master_authorized_networks_config.gcp_public_cidrs_access_enabled
      cidr_blocks {
        cidr_block = "${google_compute_address.reserved_ngw_public_ip.address}/32"
      }
      cidr_blocks {
        cidr_block = module.cloudbuild_private_pool.workerpool_range
      }
    }
  }
  ip_allocation_policy {
    cluster_secondary_range_name  = google_compute_subnetwork.gke_subnet.secondary_ip_range[0].range_name
    services_secondary_range_name = google_compute_subnetwork.gke_subnet.secondary_ip_range[1].range_name
  }
  network_policy {
    enabled = var.clusterInfo.network_policy
  }
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
  addons_config {
    horizontal_pod_autoscaling {
      disabled = !var.clusterInfo.pod_autoscale
    }

    gcs_fuse_csi_driver_config {
      enabled = var.clusterInfo.gcsfuse_csi
    }
  }
  depends_on          = [google_sql_database.db]
  deletion_protection = false
  node_config {
    linux_node_config {
      sysctls = {

        "vm.max_map_count" = 262144
      }
    }
  }
}

resource "google_container_node_pool" "worker_pool" {
  name               = var.clusterInfo.nodepool_config[0].name
  project            = var.project_id
  cluster            = google_container_cluster.gke_cluster.id
  initial_node_count = var.clusterInfo.nodepool_config[0].initial_node
  node_config {
    service_account = data.google_service_account.sa.email
    machine_type    = var.clusterInfo.nodepool_config[0].machine_type
    linux_node_config {
      sysctls = {
        "vm.max_map_count" = 262144
      }
    }
  }
  autoscaling {
    min_node_count = var.clusterInfo.nodepool_config[0].min_node
    max_node_count = var.clusterInfo.nodepool_config[0].max_node
  }
  max_pods_per_node = var.clusterInfo.nodepool_config[0].max_pods_per_node
  management {
    auto_repair  = false
    auto_upgrade = false
  }

}

module "cloudbuild_private_pool" {
  source                    = "GoogleCloudPlatform/secure-cicd/google//modules/cloudbuild-private-pool"
  version                   = "1.2.1"
  project_id                = var.project_id
  network_project_id        = var.project_id
  location                  = var.projectInfo.region
  create_cloudbuild_network = false
  private_pool_vpc_name     = google_compute_network.private_pool_vpc.name
  worker_pool_name          = "${var.projectInfo.name}-cloudbuild-private-worker-pool"
  worker_address            = var.vpnInfo.workerpool_range
  worker_range_name         = "${var.projectInfo.name}-private-pool-worker-range"
  depends_on                = [google_compute_network.private_pool_vpc]
}

module "vpn_ha_1" {
  source     = "terraform-google-modules/vpn/google//modules/vpn_ha"
  version    = "3.1.1"
  project_id = var.project_id
  region     = var.projectInfo.region
  network    = google_compute_network.private_pool_vpc.name
  name       = "${var.projectInfo.name}-cloudbuild-to-${google_compute_network.vpc.name}"
  router_asn = var.vpnInfo.gateway_1_asn
  router_advertise_config = {
    ip_ranges = {
      (module.cloudbuild_private_pool.workerpool_range) = "Cloud Build Private Pool"
    }
    mode   = "CUSTOM"
    groups = ["ALL_SUBNETS"]
  }
  peer_gcp_gateway = module.vpn_ha_2.self_link
  tunnels = {
    remote-0 = {
      bgp_peer = {
        address = cidrhost(var.vpnInfo.bgp_range_1, 2) # 169.254.1.2
        asn     = var.vpnInfo.gateway_2_asn
      }
      bgp_peer_options                = null
      bgp_session_range               = "${cidrhost(var.vpnInfo.bgp_range_1, 1)}/30" # 169.254.1.1/30
      ike_version                     = 2
      vpn_gateway_interface           = 0
      peer_external_gateway_interface = null
      shared_secret                   = ""
    }
    remote-1 = {
      bgp_peer = {
        address = cidrhost(var.vpnInfo.bgp_range_2, 2) #"169.254.2.2"
        asn     = var.vpnInfo.gateway_2_asn
      }
      bgp_peer_options                = null
      bgp_session_range               = "${cidrhost(var.vpnInfo.bgp_range_2, 1)}/30" # 169.254.2.1/30
      ike_version                     = 2
      vpn_gateway_interface           = 1
      peer_external_gateway_interface = null
      shared_secret                   = ""
    }
  }
}

module "vpn_ha_2" {
  source     = "terraform-google-modules/vpn/google//modules/vpn_ha"
  version    = "3.1.1"
  project_id = var.project_id
  region     = var.projectInfo.region
  network    = google_compute_network.vpc.name
  name       = "${var.projectInfo.name}-${google_compute_network.vpc.name}-to-cloudbuild"
  router_asn = var.vpnInfo.gateway_2_asn
  router_advertise_config = {
    ip_ranges = {
      (var.clusterInfo.private_cluster_config.master_ipv4_cidr_block) = "GKE Cluster CIDR"
    }
    mode   = "CUSTOM"
    groups = ["ALL_SUBNETS"]
  }
  peer_gcp_gateway = module.vpn_ha_1.self_link
  tunnels = {
    remote-0 = {
      bgp_peer = {
        address = cidrhost(var.vpnInfo.bgp_range_1, 1) # 169.254.1.1
        asn     = var.vpnInfo.gateway_1_asn
      }
      bgp_peer_options                = null
      bgp_session_range               = "${cidrhost(var.vpnInfo.bgp_range_1, 2)}/30" # 169.254.1.2/30
      ike_version                     = 2
      vpn_gateway_interface           = 0
      peer_external_gateway_interface = null
      shared_secret                   = module.vpn_ha_1.random_secret
    }
    remote-1 = {
      bgp_peer = {
        address = cidrhost(var.vpnInfo.bgp_range_2, 1) # 169.254.2.1
        asn     = var.vpnInfo.gateway_1_asn
      }
      bgp_peer_options                = null
      bgp_session_range               = "${cidrhost(var.vpnInfo.bgp_range_2, 2)}/30" # 169.254.2.2/30
      ike_version                     = 2
      vpn_gateway_interface           = 1
      peer_external_gateway_interface = null
      shared_secret                   = module.vpn_ha_1.random_secret
    }
  }
}

output "lb_public_ip" {
  value = { for name, addr in google_compute_address.reserved_lb_public_ip : name => addr.address }
  #value = google_compute_address.reserved_lb_public_ip.address.0.ip_address
}

output "sql_private_ip" {
  value = google_sql_database_instance.db_instance.ip_address.0.ip_address
}

