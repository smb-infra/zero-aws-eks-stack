terraform {
  backend "s3" {
    bucket         = "<% .Name %>-prod-terraform-state"
    key            = "infrastructure/terraform/environments/prod/kubernetes"
    encrypt        = true
    region         = "<% index .Params `region` %>"
    dynamodb_table = "<% .Name %>-prod-terraform-state-locks"
  }

  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 3.7"
    }
  }
}

locals {
  project      = "<% .Name %>"
  region       = "<% index .Params `region` %>"
  account_id   = "<% index .Params `accountId` %>"
  domain_name  = "<% index .Params `productionHostRoot` %>"
  file_uploads = <% if eq (index .Params `fileUploads`) "yes" %>true<% else %>false<% end %>
}

provider "aws" {
  region              = local.region
  allowed_account_ids = [local.account_id]
}


# Provision kubernetes resources required to run services/applications
module "kubernetes" {
  source = "../../modules/kubernetes"
  environment         = "prod"

  project             = local.project
  region              = local.region
  allowed_account_ids = [local.account_id]
  random_seed         = "<% index .Params `randomSeed` %>"
  cf_signing_enabled  = local.file_uploads

  # Authenticate with the EKS cluster via the cluster id
  cluster_name = "${local.project}-prod-${local.region}"

  external_dns_zones    = [local.domain_name]
  external_dns_owner_id = "${local.project}-prod-${local.region}"

  # Registration email for LetsEncrypt
  cert_manager_acme_registration_email = "devops@${local.domain_name}"

  # Logging and Metrics configuration
  logging_type = "<% index .Params `loggingType` %>"
  metrics_type = "<% index .Params `metricsType` %>"
  internal_domain = "" # TODO: Add internal domain support

  # Application policy list - This allows applications running in kubernetes to have access to AWS resources.
  # Specify the service account name, the namespace, and the policy that should be applied.
  # This makes use of IRSA: https://aws.amazon.com/blogs/opensource/introducing-fine-grained-iam-roles-service-accounts/
  application_policy_list = [
    {
      service_account = "backend-service"
      namespace       = local.project
      policy          = data.aws_iam_policy_document.resource_access_backendservice
    },
    # Add additional mappings here
  ]


  # Wireguard configuration
  vpn_server_address = "10.10.99.0/24"
  vpn_client_publickeys = [
    # ["Test User 1", "10.10.99.201/32", "/B3Q/Hlf+ILInjpehTLk9DZGgybdGdbm0SsG87OnWV0="],
    # ["Test User 2", "10.10.99.202/32", "h2jMuaXNIlx7Z0a3owWFjPsAA8B+ZpQH3FbZK393+08="],
  ]

  domain_name                 = local.domain_name
  auth_enabled                = <% if eq (index .Params `userAuth`) "yes" %>true<% else %>false<% end %>
  auth_domain                 = "auth.${local.domain_name}"
  backend_service_domain      = "<% index .Params `productionBackendSubdomain` %>${local.domain_name}"
  frontend_service_domain     = "<% index .Params `productionFrontendSubdomain` %>${local.domain_name}"
  # This domain or address must be verified by the mail provider (Sendgrid, SES, etc.)
  user_auth_mail_from_address = "noreply@${local.domain_name}"

  notification_service_enabled          = <%if eq (index .Params `notificationServiceEnabled`) "yes" %>true<% else %>false<% end %>
  notification_service_highly_available = true

  cache_store =  "<% index .Params `cacheStore` %>"
}
