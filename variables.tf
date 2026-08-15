variable "folder_id" {
  type        = string
  description = "ID каталога Yandex Cloud"
}

variable "ssh_public_key_path" {
  type        = string
  description = "Путь к публичному SSH-ключу для доступа к нодам"
}
