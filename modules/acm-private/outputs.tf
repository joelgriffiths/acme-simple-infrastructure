output "certificate_arn" {
  description = "Leaf certificate ARN for the internal HTTPS listener"
  value       = aws_acm_certificate.internal.arn
}

output "certificate_authority_arn" {
  description = "Private CA ARN"
  value       = aws_acmpca_certificate_authority.root.arn
}

output "ca_certificate_pem" {
  description = "Root CA certificate, PEM encoded. Import this into the directory so clients trust the internal hostnames."
  value       = aws_acmpca_certificate.root.certificate
}
