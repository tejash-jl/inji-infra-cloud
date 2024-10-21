variable "env" {
  type = string
  default = "dev"
}

variable "subscription_id" {
  type = string
}

variable "node_count" {
  type = number
  default = 1
}

variable "username" {
  type        = string
  description = "The admin username for the new cluster."
  default     = "injiadmin"
}

variable "region" {
  type = string
  default = "East US 2"
}

variable "bastion_admin_password" {
  description = "value of the admin password for the bastion host"
  type        = string
  sensitive   = true
}
variable "enable_aks" {
  description = "Feature flag to control the creation of the aks module resources"
  type        = bool
  default     = false
}

variable "ssh_public_key" {
  description = "The SSH public key file to use for authentication."
  type        = string
}