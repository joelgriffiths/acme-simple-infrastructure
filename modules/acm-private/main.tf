# A private certificate authority, and one certificate issued from it for the internal
# load balancer.
#
# The internal hostnames live under a domain that does not exist on the public internet, so
# a public ACM certificate is impossible: DNS validation needs a name a CA can resolve.
# That leaves running our own CA, which is what this is.
#
# COST WARNING, read before applying. AWS Private CA is billed per CA per month whether or
# not it issues anything: roughly $400/month in general-purpose mode, or roughly $50/month
# in short-lived certificate mode, plus a per-certificate charge. Two environments means two
# CAs. That is the single most expensive resource in this repo by a wide margin, and it is
# worth being sure the private domain is a requirement and not a preference. ARCHITECTURE.md
# records the cheaper alternative.
#
# The root CA certificate is exported for distribution: import it into the directory so
# clients trust the internal names.

resource "aws_acmpca_certificate_authority" "root" {
  type                            = "ROOT"
  usage_mode                      = var.usage_mode
  permanent_deletion_time_in_days = var.deletion_window_in_days

  certificate_authority_configuration {
    key_algorithm     = var.key_algorithm
    signing_algorithm = var.signing_algorithm

    subject {
      common_name         = var.ca_common_name
      organization        = var.organization
      organizational_unit = var.organizational_unit
      country             = var.country
    }
  }

  revocation_configuration {
    # No CRL and no OCSP responder. Both cost money and need a public endpoint, and the
    # only consumers of these certificates are our own load balancer and our own clients.
    # Revocation here means issuing a new CA, which at this size is the honest answer.
    ocsp_configuration {
      enabled = false
    }
  }

  tags = { Name = var.name }
}

# A root CA has to sign its own certificate before it can issue anything.
resource "aws_acmpca_certificate" "root" {
  certificate_authority_arn   = aws_acmpca_certificate_authority.root.arn
  certificate_signing_request = aws_acmpca_certificate_authority.root.certificate_signing_request
  signing_algorithm           = var.signing_algorithm

  template_arn = "arn:aws:acm-pca:::template/RootCACertificate/V1"

  validity {
    type  = "YEARS"
    value = var.ca_validity_years
  }
}

resource "aws_acmpca_certificate_authority_certificate" "root" {
  certificate_authority_arn = aws_acmpca_certificate_authority.root.arn
  certificate               = aws_acmpca_certificate.root.certificate
  certificate_chain         = aws_acmpca_certificate.root.certificate_chain
}

# The leaf certificate for the internal load balancer. Requested through ACM rather than
# ACM PCA directly, so ACM handles renewal instead of us remembering to.
resource "aws_acm_certificate" "internal" {
  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  certificate_authority_arn = aws_acmpca_certificate_authority.root.arn

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = var.domain_name }

  depends_on = [aws_acmpca_certificate_authority_certificate.root]
}
