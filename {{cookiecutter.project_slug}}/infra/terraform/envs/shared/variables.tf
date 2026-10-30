variable "prefix" {
  description = "Resource name prefix (2-12 lowercase letters/digits)."
  type        = string
}

variable "location" {
  type = string
}

variable "registry_sku" {
  type    = string
  default = "Basic"
}

variable "deploy_principal_id" {
  description = "Object id of the CI/CD service principal (AcrPush + Contributor on the registry). Null to skip."
  type        = string
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
