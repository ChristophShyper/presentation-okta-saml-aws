# AWS SAML SSO via Okta Terraform Module

This Terraform module sets up AWS SAML access with Okta, automating the creation of necessary AWS and Okta resources for secure and streamlined access management. 
It leverages SAML 2.0 for Single Sign-On (SSO) capabilities, allowing users to authenticate once with Okta to access AWS resources.
It sets up default IAM roles for admin and read-only access if needed, and configures an IAM user for accessing AWS through Okta SSO. 
The module is designed to work both in AWS Organizations' master and member accounts.


## Features

* Creates an AWS SAML SSO application in Okta.
* Configures Okta as a SAML Identity Provider (IdP) in all AWS accounts.
* Utilizes HTTP provider to dynamically fetch SAML metadata from Okta.
* Configures IAM roles for admin and read-only access, with trust relationships to the Okta SAML provider.
* In the master account, it creates an IAM user with policies allowing it to assume roles in member accounts for SSO access.
* Almost no manual setup required in Okta or AWS, making it easy to deploy and manage.


## Example usage

```terraform
variable "okta_api_token" {
  description = "The Okta API token for downloading the IdP metadata"
  type        = string
  sensitive   = true
}

locals {
  assignment = jsonencode({
    "first.user@example.com" = {
      "123456789012" = [
        "AdminAccess",
        "ReadOnlyAccess"
      ],
      "987654321098" = [
        "AdminAccess",
        "ReadOnlyAccess"
      ]
    },
    "second.user@example.com" = {
      "123456789012" = [
        "ReadOnlyAccess"
      ],
      "987654321098" = [
        "ReadOnlyAccess"
      ]
    }
  })
}

module "master_account" {
  source = "./module-okta-saml-aws"

  providers = {
    aws  = aws.master
    okta = okta
    http = http
  }

  assignment     = local.assignment
  okta_api_token = var.okta_api_token
}

module "child_account" {
  source = "./module-okta-saml-aws"

  providers = {
    aws  = aws.child
    okta = okta
    http = http
  }

  assignment = local.assignment
  okta_api_token = var.okta_api_token

  depends_on = [module.master_account]
}

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }

    okta = {
      source  = "okta/okta"
      version = "~> 4.0"
    }
  }
}

# https://registry.terraform.io/providers/okta/okta/latest/docs
provider "okta" {
  org_name = "dev-123456"
  base_url = "okta.com"
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs
provider "aws" {
  alias   = "master"
  profile = "okta-master" # used with IAM user
  #  profile = "my-org-master-AdminAccess" # used with IAM role
  region = "eu-west-1"
}

provider "aws" {
  alias   = "child"
  profile = "okta-child"
  #  profile = "my-org-child-AdminAccess"
  region = "eu-west-1"
}
```

Ensure you replace the placeholders with actual values suitable for your setup.


## Requirements

| Name      | Version  |
|-----------|----------|
| terraform | >= 1.7.0 |


## Providers

| Name | Version |
|------|---------|
| aws  | ~> 5.0  |
| http | ~> 3.0  |
| okta | ~> 4.0  |


## Inputs

| Variable               | Description                                                                    | Type   | Default            | Required |
|------------------------|--------------------------------------------------------------------------------|--------|--------------------|:--------:|
| `admin_role_name`      | The name of the IAM role to create for admin access via SAML SSO.              | string | `"AdminAccess"`    |    no    |
| `assignment`           | JSON string mapping Okta users to AWS accounts and roles.                      | string | `"{}"`             |   yes    |
| `max_session_duration` | The maximum session duration in seconds for the SAML session.                  | number | `28800` (8 hours)  |    no    |
| `okta_api_token`       | API token for authenticating requests to Okta.                                 | string | `""`               |   yes    |
| `okta_user_name`       | The name of the IAM user created in AWS for Okta integration.                  | string | `"OktaUserSSO"`    |    no    |
| `okta_user_path`       | Path under which the IAM user is created.                                      | string | `"/"`              |    no    |
| `read_only_role_name`  | The name of the read-only IAM role for SSO. If empty, the role is not created. | string | `"ReadOnlyAccess"` |    no    |


## Outputs

No outputs are defined in this module.


## Resources created

| Resource Type           | Description                                                                 |
|-------------------------|-----------------------------------------------------------------------------|
| `okta_app_saml`         | SAML application in Okta for AWS SSO.                                       |
| `aws_iam_role`          | Administrator and Read-only roles for SSO within AWS accounts.              |
| `aws_iam_user`          | IAM user in the master AWS account to facilitate Okta integration.          |
| `aws_iam_policy`        | Policies attached to the IAM roles and user to grant necessary permissions. |
| `aws_iam_saml_provider` | SAML identity provider in AWS that uses Okta's SAML metadata.               |


## Notes

* This module is designed for use with AWS Organizations. It differentiates between the master account and member accounts using the `is_master_account` local variable.
* The IAM user created in the master account is intended for administrative tasks related to SSO and should have its permissions tightly controlled.
* Be sure to review and adjust the IAM policies according to the principle of least privilege.
* The module is designed to be idempotent, safely applying changes without unintended resource creation or deletion.
* For detailed instructions on setting up the Okta application and linking it with AWS, consult Okta's official documentation.

## Support

This module is provided "as is", with no warranty or guarantee of support. <br>
It was created as a learning exercise, to be presented together with an article and meetup presentation, and is not intended for production use. <br>
However, issues and pull requests are welcome on the repository hosting this module.
