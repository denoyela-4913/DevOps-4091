terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      #version = "3.0.2"
      version = "~>4.2.0"
    }
  }
}

provider "docker" {}


resource "docker_image" "qemu" {
  #name = "qemux/qemu-docker:5.16"
  name = "qemux/qemu:latest"
}

resource "docker_volume" "qemu_storage" {
  name = "openclassrooms-p5-edo-qemu-storage"
}

resource "docker_container" "my_vm" {
  image = docker_image.qemu.image_id
  name  = "openclassrooms-p5-edo"
  capabilities {
    add = ["NET_ADMIN"]
  }

  env = [
    "BOOT=https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.vmdk",
    "ARGUMENTS=-drive if=virtio,format=raw,file=/share/cloud-init/cloud-init.img",
  ]
  ports {
    external = 8006
    internal = 8006
  }
  ports {
    external = 80
    internal = 80
  }
  ports {
    external = 2222
    internal = 22
  }
  devices {
    host_path = "/dev/kvm"
  }

  volumes {
    host_path      = "${path.cwd}/share"
    container_path = "/share"
  }
  volumes {
    volume_name    = docker_volume.qemu_storage.id
    container_path = "/storage"
  }
}
