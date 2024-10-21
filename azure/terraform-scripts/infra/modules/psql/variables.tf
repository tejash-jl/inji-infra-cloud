variable "subnet_id" {
  type        = string
  description = "The ID of the subnet to place the psql."
}

variable "resource_group" {
  type = object({
    name     = string
    location = string
  })
  description = "Resource group to place the psql."
}

variable "vpc_id" {
  type        = string
  description = "The ID of the vpc"
}

variable "db_info" {
  type = list(string)

  default = ["registry", "keycloak", "credentials", "credential-schema", "identity", "esignet-keycloak", "mosip_esignet", "mosip_mockidentitysystem", "inji_certify"]
}

variable "env" {
  type = string
}