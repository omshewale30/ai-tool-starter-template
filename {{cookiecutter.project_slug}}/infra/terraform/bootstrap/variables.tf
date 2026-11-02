variable "prefix" {
  description = "Resource name prefix (2-12 lowercase letters/digits)."
  type        = string
}

variable "location" {
  description = "Azure region for the state storage account."
  type        = string
}

variable "state_contributor_principal_ids" {
  description = "Everyone who runs Terraform (label => object id; an Entra group is best). Must include you. Empty: the caller."
  type        = map(string)
  default     = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}
