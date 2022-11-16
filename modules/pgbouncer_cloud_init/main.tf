locals {
  users    = [for u in var.users : ({ name = u.name, password = substr(u.password, 0, 3) == "md5" ? u.password : "md5${md5("${u.password}${u.name}")}" })]
  admins   = [for u in var.users : u.name if lookup(u, "admin", false) == true]
  userlist = templatefile("${path.module}/templates/userlist.txt.tmpl", { users = local.users })
  cloud_config = templatefile(
    "${path.module}/templates/pgbouncer.ini.tmpl",
    {
      db_host            = var.database_host
      db_port            = var.database_port
      listen_port        = var.listen_port
      auth_user          = var.auth_user
      auth_query         = var.auth_query
      default_pool_size  = var.default_pool_size
      max_db_connections = var.max_db_connections
      max_client_conn    = var.max_client_conn
      pool_mode          = var.pool_mode
      admin_users        = join(",", local.admins)
      custom_config      = var.custom_config
    }
  )
}
locals {
  region = join("-", slice(split("-", var.zone), 0, 2))
}
resource "random_id" "suffix" {
  byte_length = 5
}

data "google_compute_subnetwork" "subnet" {
  project = var.project
  name    = var.subnetwork_name
  region  = local.region
}

data "template_file" "cloud_config" {
  template = file("${path.module}/templates/cloud-init.yaml.tmpl")
  vars = {
    image       = "edoburu/pgbouncer:${var.pgbouncer_image_tag}"
    listen_port = var.listen_port
    config      = base64encode(local.cloud_config)
    userlist    = base64encode(local.userlist)
  }
}

data "cloudinit_config" "cloud_config" {
  gzip          = false
  base64_encode = false
  part {
    filename     = "cloud-init.yaml"
    content_type = "text/cloud-config"
    content      = data.template_file.cloud_config.rendered
  }
}

/* PgBouncer ---------------------------------------------------------------- */

resource "google_compute_address" "pgbouncer" {
  project      = var.project
  region       = local.region
  name         = "ip-pgbouncer-${random_id.suffix.hex}"
  network_tier = "PREMIUM"
}

module "pgbouncer" {
  source = "../.."

  project           = var.project
  name              = "vm-pgbouncer-${random_id.suffix.hex}"
  zone              = var.zone
  subnetwork        = var.subnetwork_name
  public_ip_address = google_compute_address.pgbouncer.address
  tags              = ["pgbouncer"]

  disable_service_account = true

  port          = 25128
  database_host = module.db.private_ip_address

  users = [
    { name = var.db_user, password = var.db_password },
  ]

  module_depends_on = [module.db]
}

/* Firewall ----------------------------------------------------------------- */

resource "google_compute_firewall" "pgbouncer" {
  name    = "${var.network_name}-ingress-pgbouncer-${random_id.suffix.hex}"
  project = var.project
  network = var.network_name

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["pgbouncer"]

  allow {
    protocol = "tcp"
    ports    = [module.pgbouncer.port]
  }
}
