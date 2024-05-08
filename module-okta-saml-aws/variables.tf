# VARIABLES

variable "admin_role_name" {
  description = "The name of the IAM role to create for admin access via SAML SSO. Role is not created if set to empty string."
  type        = string
  default     = "AdminAccess"
}

variable "assignment" {
  description = "Map of Okta users and their assignments to AWS accounts and roles, provided as a JSON string"
  type        = string
  default     = "{}"
}

variable "max_session_duration" {
  description = "The maximum session duration in seconds"
  type        = number
  default     = 28800 # 8h
}

variable "okta_api_token" {
  description = "The Okta API token for downloading the IdP metadata"
  type        = string
  sensitive   = true
}

variable "okta_user_name" {
  description = "The name of the IAM user to create for Okta read access"
  type        = string
  default     = "OktaUserSSO"
}

variable "okta_user_path" {
  description = "The path to create the IAM user for Okta read access"
  type        = string
  default     = "/"
}

variable "read_only_role_name" {
  description = "The name of the IAM role to create for read-only access via SAML SSO. Role is not created if set to empty string."
  type        = string
  default     = "ReadOnlyAccess"
}
