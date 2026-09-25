terraform {
  required_version = ">= 1.9"

  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = ">= 0.8.1, < 0.9"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}
