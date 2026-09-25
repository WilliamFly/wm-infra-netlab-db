variable "base_image_path" {
  description = "Path to the Ubuntu 24.04 cloud image (qcow2) on the host"
  type        = string
}

variable "storage_pool" {
  description = "libvirt storage pool to create VM disks in"
  type        = string
  default     = "default"
}

variable "ssh_public_key" {
  description = "SSH public key installed on the DB VM's admin user"
  type        = string
}

variable "db_vcpu" {
  description = "vCPUs for the Postgres VM"
  type        = number
  default     = 1
}

variable "db_memory_mb" {
  description = "Memory (MB) for the Postgres VM"
  type        = number
  default     = 1024
}

variable "db_name" {
  description = "Name of the application database Postgres creates on boot"
  type        = string
  default     = "netlab_app"
}

variable "db_app_user" {
  description = "Postgres role apps connect as (not the postgres superuser)"
  type        = string
  default     = "app_user"
}

variable "db_app_password" {
  description = "Password for db_app_user — required, no default, never commit the real value"
  type        = string
  sensitive   = true
}
