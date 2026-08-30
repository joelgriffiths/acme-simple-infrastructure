# Private CA identity. Component-level: the same subject in every environment, with the
# environment distinguished by the CA name prefix the unit passes in.
locals {
  ca_common_name      = "Acme Internal Root CA"
  organization        = "Acme Corp"
  organizational_unit = "Infrastructure"
  country             = "US"

  # Root lifetime is long because rotating it means redistributing trust to every client
  # that has imported it.
  ca_validity_years = 10
}
