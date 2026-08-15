locals {
  # Префикс для ресурсов
  prefix = "k8s"

  # ID каталога
  folder_id = var.folder_id

  # IAM management
  resource_member = "serviceAccount:${yandex_iam_service_account.k8s-resources-sa.id}"
  nodes_member    = "serviceAccount:${yandex_iam_service_account.k8s-nodes-sa.id}"
  resource_roles  = toset(["editor", "k8s.clusters.agent", "vpc.publicAdmin", "kms.keys.encrypterDecrypter"])
  nodes_roles     = toset(["container-registry.images.puller", "container-registry.images.pusher"])
}

resource "yandex_kubernetes_cluster" "k8s-cluster" {
  name       = "${local.prefix}-cluster"
  network_id = yandex_vpc_network.k8s-network.id

  # Прямая зависимость от SA, чтобы исключить ошибки при создании кластера
  depends_on = [
    yandex_resourcemanager_folder_iam_member.k8s-resources-sa,
    yandex_resourcemanager_folder_iam_member.k8s-nodes-sa,
  ]

  # Сетевые политики CALICO/CILIUM
  network_policy_provider = "CALICO"

  master {
    public_ip = true
    master_location {
      zone      = yandex_vpc_subnet.k8s-subnet.zone
      subnet_id = yandex_vpc_subnet.k8s-subnet.id
    }
  }

  service_account_id      = yandex_iam_service_account.k8s-resources-sa.id
  node_service_account_id = yandex_iam_service_account.k8s-nodes-sa.id

  kms_provider {
    key_id = yandex_kms_symmetric_key.kms-key.id
  }
}

resource "yandex_kubernetes_node_group" "k8s-workload" {
  name       = "${local.prefix}-workload"
  cluster_id = yandex_kubernetes_cluster.k8s-cluster.id

  allocation_policy {
    location {
      zone = yandex_vpc_subnet.k8s-subnet.zone
    }
  }

  instance_template {
    platform_id = "standard-v3"
    resources {
      memory        = 2
      cores         = 2
      core_fraction = 20
    }
    boot_disk {
      size = 64
      type = "network-hdd"
    }
    network_interface {
      subnet_ids = [
        yandex_vpc_subnet.k8s-subnet.id
      ]
      nat  = true
      ipv4 = true
    }
    metadata = {
      ssh-keys = "k8s_user:${file(var.ssh_public_key_path)}"
    }
  }

  maintenance_policy {
    auto_upgrade = true
    auto_repair  = true
    maintenance_window {
      duration   = "2h"
      start_time = "02:00"
    }
  }

  scale_policy {
    fixed_scale {
      size = 1
    }
  }
}

resource "yandex_vpc_network" "k8s-network" {
  description = "VPC для моего кластера k8s"
  name        = "${local.prefix}-network"
}

resource "yandex_vpc_subnet" "k8s-subnet" {
  description    = "Subnet для моего кластера k8s"
  name           = "${local.prefix}-subnet"
  v4_cidr_blocks = ["10.1.0.0/16"]
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.k8s-network.id
}

resource "yandex_iam_service_account" "k8s-resources-sa" {
  name        = "${local.prefix}-resources-sa"
  description = "Service account for the single Kubernetes cluster (resource provisioning)"
}

resource "yandex_iam_service_account" "k8s-nodes-sa" {
  name        = "${local.prefix}-nodes-sa"
  description = "Service account for the single Kubernetes cluster (docker images puller/pusher)"
}

resource "yandex_resourcemanager_folder_iam_member" "k8s-resources-sa" {
  for_each  = local.resource_roles
  folder_id = local.folder_id
  role      = each.key
  member    = local.resource_member
}

resource "yandex_resourcemanager_folder_iam_member" "k8s-nodes-sa" {
  for_each  = local.nodes_roles
  folder_id = local.folder_id
  role      = each.key
  member    = local.nodes_member
}

resource "yandex_kms_symmetric_key" "kms-key" {
  # Ключ Yandex Key Management Service для шифрования важной информации, такой как пароли и SSH-ключи.
  name              = "${local.prefix}-kms-key"
  default_algorithm = "AES_128"
  rotation_period   = "8760h" # 1 год.
}
