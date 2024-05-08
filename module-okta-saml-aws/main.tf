# LOCAL VARIABLES MAPPED IN ONE PLACE

locals {
  admin_role_name      = var.admin_role_name
  assignment           = jsondecode(var.assignment)
  aws_region           = data.aws_region.this.name
  current_account_id   = data.aws_caller_identity.this.account_id
  is_master_account    = local.current_account_id == local.master_account_id
  master_account_id    = data.aws_organizations_organization.this.master_account_id
  max_session_duration = var.max_session_duration
  okta_api_token       = var.okta_api_token
  okta_user_name       = var.okta_user_name
  okta_user_path       = var.okta_user_path
  read_only_role_name  = var.read_only_role_name
}

# RESOURCES

####################
# Created with master account

# AWS SSO SAML application in Okta
# https://registry.terraform.io/providers/okta/okta/latest/docs/resources/app_saml
resource "okta_app_saml" "amazon_aws" {
  count = local.is_master_account ? 1 : 0

  label             = "Amazon Web Services"
  preconfigured_app = "amazon_aws"
  app_settings_json = jsonencode(
    {
      appFilter           = "okta"
      groupFilter         = "aws_(?{{accountid}}\\d+)_(?{{role}}[a-zA-Z0-9+=,.@\\-_]+)"
      useGroupMapping     = true
      joinAllRoles        = true
      identityProviderArn = "arn:aws:iam::${local.master_account_id}:saml-provider/Okta" # Must match aws_iam_saml_provider.okta
      sessionDuration     = local.max_session_duration
      roleValuePattern    = "arn:aws:iam::$${accountid}:saml-provider/Okta,arn:aws:iam::$${accountid}:role/$${role}"
      awsEnvironmentType  = "aws.amazon"
      loginURL            = "https://${local.aws_region}.console.aws.amazon.com/console/home?region=${local.aws_region}#"
    }
  )

  lifecycle {
    ignore_changes = [
      key_years_valid
    ]
  }
}

data "http" "metadata" {
  count = local.is_master_account ? 1 : 0

  url = okta_app_saml.amazon_aws[0].metadata_url
  request_headers = {
    Authorization : "SSWS ${local.okta_api_token}"
  }

  depends_on = [
    okta_app_saml.amazon_aws
  ]
}

# Okta's IAM user's policy in master account for reading data from master account and assuming roles in non-master accounts
# https://www.terraform.io/docs/providers/aws/d/iam_policy_document.html
data "aws_iam_policy_document" "okta_user" {
  count = local.is_master_account ? 1 : 0

  policy_id = "okta-saml-user"

  statement {
    # Assume Okta roles in non-master accounts
    sid       = "AssumeRoleNonMaster"
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = ["arn:aws:iam::*:role/Okta-Idp-cross-account-role"] # This is fixed named used by Okta
  }

  statement {
    # Get all roles in master account
    sid       = "GetSSORoles"
    effect    = "Allow"
    actions   = ["iam:ListRoles"]
    resources = ["*"]
  }

  statement {
    # Get all account aliases in organization
    sid       = "GetAccountAlias"
    effect    = "Allow"
    actions   = ["iam:ListAccountAliases"]
    resources = ["*"]
  }

  statement {
    # Get Okta user's data
    sid       = "GetOktaUser"
    effect    = "Allow"
    actions   = ["iam:GetUser"]
    resources = ["arn:aws:iam::${local.master_account_id}:user/${local.okta_user_name}"]
  }
}

# IAM user for Okta SAML on master account
# https://www.terraform.io/docs/providers/aws/r/iam_user.html
resource "aws_iam_user" "okta_user" {
  count = local.is_master_account ? 1 : 0

  name = local.okta_user_name
  path = local.okta_user_path
}

# Policy for Okta IAM user on master account
# https://www.terraform.io/docs/providers/aws/r/iam_user_policy.html
resource "aws_iam_user_policy" "okta_user" {
  count = local.is_master_account ? 1 : 0

  policy = data.aws_iam_policy_document.okta_user[0].json
  name   = local.okta_user_name
  user   = aws_iam_user.okta_user[0].name
}


#########################
# Created with all non-master accounts

# To read metadata from Okta's AWS SSO SAML application
data "okta_app_saml" "amazon_aws" {
  count = !local.is_master_account ? 1 : 0

  label = "Amazon Web Services"
}

data "okta_app_metadata_saml" "amazon_aws" {
  count = !local.is_master_account ? 1 : 0

  app_id = data.okta_app_saml.amazon_aws[0].id
}

# Assume role policy content for Okta's cross-account roles
# https://www.terraform.io/docs/providers/aws/d/iam_policy_document.html
data "aws_iam_policy_document" "assume_okta_user" {
  count = !local.is_master_account ? 1 : 0

  policy_id = "assume-okta-user"

  statement {
    sid     = "OktaAssumeUser"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      identifiers = [
        "arn:aws:iam::${local.master_account_id}:user/${local.okta_user_name}",
      ]
      type = "AWS"
    }
  }
}

# Okta-Idp-cross-account-role role policy in non-master accounts for reading data from current account
# https://www.terraform.io/docs/providers/aws/d/iam_policy_document.html
data "aws_iam_policy_document" "cross_account_role" {
  count = !local.is_master_account ? 1 : 0

  policy_id = "cross-account-role"

  statement {
    # Get all roles in current account
    sid       = "GetSSORoles"
    effect    = "Allow"
    actions   = ["iam:ListRoles"]
    resources = ["*"]
  }

  statement {
    # Get current account alias
    sid       = "GetAccountAlias"
    effect    = "Allow"
    actions   = ["iam:ListAccountAliases"]
    resources = ["*"]
  }
}

# IAM role to read all other roles and account alias on non-master-accounts
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
resource "aws_iam_role" "cross_account_role" {
  count = !local.is_master_account ? 1 : 0

  name                 = "Okta-Idp-cross-account-role" # Reserved name
  assume_role_policy   = data.aws_iam_policy_document.assume_okta_user[0].json
  path                 = "/"
  description          = "Okta role for reading account information"
  max_session_duration = local.max_session_duration

  # Okta-Idp-cross-account-role role policy in non-master accounts for reading data from current account
  inline_policy {
    name   = "Okta-Idp-cross-account-role"
    policy = data.aws_iam_policy_document.cross_account_role[0].json
  }
}


##################
# Created with all accounts

# For getting Okta users Ids
data "okta_user" "users" {
  for_each = toset(keys(local.assignment))

  search {
    name  = "profile.login"
    value = each.key
  }

  skip_roles = true
}

# For getting current account id
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity
data "aws_caller_identity" "this" {}

# For getting current region
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region
data "aws_region" "this" {}

# For getting master account id
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/organizations_organization
data "aws_organizations_organization" "this" {}

# Okta Identity Provider for SSO for every account
# https://www.terraform.io/docs/providers/aws/r/iam_saml_provider.html
resource "aws_iam_saml_provider" "okta" {
  name                   = "Okta"
  saml_metadata_document = local.is_master_account ? data.http.metadata[0].response_body : data.okta_app_metadata_saml.amazon_aws[0].metadata

  depends_on = [
    okta_app_saml.amazon_aws
  ]
}

# Assume role policy content for SAML SSO roles
# https://www.terraform.io/docs/providers/aws/d/iam_policy_document.html
data "aws_iam_policy_document" "assume_okta" {
  policy_id = "assume-provider"

  statement {
    sid    = "AssumeRoleWithSAML"
    effect = "Allow"
    actions = [
      "sts:AssumeRoleWithSAML",
      "sts:TagSession",
    ]

    principals {
      identifiers = [aws_iam_saml_provider.okta.arn]
      type        = "Federated"
    }

    condition {
      test     = "StringEquals"
      values   = ["https://signin.aws.amazon.com/saml"]
      variable = "SAML:aud"
    }
  }
}

# Admin role in every account
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
resource "aws_iam_role" "admin" {
  count = local.admin_role_name != "" ? 1 : 0

  name = local.admin_role_name
  #  assume_role_policy = data.aws_iam_policy_document.assume_okta[0].json
  assume_role_policy = data.aws_iam_policy_document.assume_okta.json
  path               = "/"
  description        = "Admin role for the account"
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AdministratorAccess", # AWS managed admin policy
  ]
  max_session_duration = local.max_session_duration
}

# For assigning admin role in each account
resource "okta_group" "admin" {
  count = local.admin_role_name != "" ? 1 : 0

  name        = "aws_${local.current_account_id}_${local.admin_role_name}"
  description = "Access to ${local.admin_role_name} role in ${local.current_account_id} AWS account"
}

resource "okta_app_group_assignment" "admin" {
  count = local.admin_role_name != "" ? 1 : 0

  app_id   = local.is_master_account ? okta_app_saml.amazon_aws[0].id : data.okta_app_saml.amazon_aws[0].id
  group_id = okta_group.admin[0].id
}

resource "okta_group_memberships" "admin" {
  count = local.admin_role_name != "" ? 1 : 0

  group_id = okta_group.admin[0].id
  users = toset(flatten(
    [for user, accounts in local.assignment :
      [for account, roles in accounts :
        [for role in roles : data.okta_user.users[user].id if role == local.admin_role_name && account == local.current_account_id]
      ]
    ]
  ))
  track_all_users = true
}

# Read only role in every account
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
resource "aws_iam_role" "readonly" {
  count = local.read_only_role_name != "" ? 1 : 0

  name               = local.read_only_role_name
  assume_role_policy = data.aws_iam_policy_document.assume_okta.json
  path               = "/"
  description        = "Read-only role for the account"
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AWSSupportAccess", # Allows users to access the AWS Support Center.
    "arn:aws:iam::aws:policy/ReadOnlyAccess",   # Provides read-only access to AWS services and resources.
  ]
  max_session_duration = local.max_session_duration
}

# For assigning read-only role in each account
resource "okta_group" "readonly" {
  count = local.read_only_role_name != "" ? 1 : 0

  name        = "aws_${local.current_account_id}_${local.read_only_role_name}"
  description = "Access to ${local.read_only_role_name} role in ${local.current_account_id} AWS account"
}

resource "okta_app_group_assignment" "readonly" {
  count = local.read_only_role_name != "" ? 1 : 0

  app_id   = local.is_master_account ? okta_app_saml.amazon_aws[0].id : data.okta_app_saml.amazon_aws[0].id
  group_id = okta_group.readonly[0].id
}

resource "okta_group_memberships" "readonly" {
  count = local.read_only_role_name != "" ? 1 : 0

  group_id = okta_group.readonly[0].id
  users = toset(flatten(
    [for user, accounts in local.assignment :
      [for account, roles in accounts :
        [for role in roles : data.okta_user.users[user].id if role == local.read_only_role_name && account == local.current_account_id]
      ]
    ]
  ))
  track_all_users = true
}
