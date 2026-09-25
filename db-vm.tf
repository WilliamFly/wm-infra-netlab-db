# This repo owns the shared Postgres VM — the single source of truth for
# every app that needs it (Rust now, Node later). Apps connect to it by
# IP; they never provision or own it themselves, which is exactly what
# stops two repos from fighting over one shared, stateful resource (see
# ADR 0004). Imports its own copy of the base image and attaches to
# data-net by NAME (network_name), not network_id — same decoupling
# pattern as network-foundation's router and the earlier test VM.

locals {
  mac_db          = "52:54:00:ab:02:01"
  private_subnet  = "10.0.2.0/24" # app tier — allowed to reach this DB
}

resource "libvirt_volume" "ubuntu_base" {
  name   = "wm-netlab-db-ubuntu-24.04-base"
  pool   = var.storage_pool
  source = var.base_image_path
  format = "qcow2"
}

resource "libvirt_volume" "db_disk" {
  name           = "wm-netlab-db.qcow2"
  pool           = var.storage_pool
  base_volume_id = libvirt_volume.ubuntu_base.id
  format         = "qcow2"
}

resource "libvirt_cloudinit_disk" "db" {
  name = "wm-netlab-db-cloudinit.iso"
  pool = var.storage_pool

  user_data = templatefile("${path.module}/cloud-init/db-user-data.yaml.tftpl", {
    ssh_public_key  = var.ssh_public_key
    private_subnet  = local.private_subnet
    db_name         = var.db_name
    db_app_user     = var.db_app_user
    db_app_password = var.db_app_password
  })

  network_config = templatefile("${path.module}/cloud-init/db-network-config.yaml.tftpl", {
    mac_data = local.mac_db
  })
}

resource "libvirt_domain" "db" {
  name   = "wm-netlab-db"
  vcpu   = var.db_vcpu
  memory = var.db_memory_mb

  cloudinit = libvirt_cloudinit_disk.db.id

  disk {
    volume_id = libvirt_volume.db_disk.id
  }

  network_interface {
    network_name   = "wm-netlab-data" # by name — not managed by this state
    mac            = local.mac_db
    wait_for_lease = false
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }

  autostart = true
}

output "db_ip" {
  value = "10.0.3.20 (only reachable via the router, e.g. `ssh -J netlab-admin@10.0.1.10 netlab-admin@10.0.3.20`)"
}
