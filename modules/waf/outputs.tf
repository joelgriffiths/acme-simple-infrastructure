output "web_acl_arn" {
  description = "Web ACL ARN"
  value       = aws_wafv2_web_acl.this.arn
}

output "web_acl_id" {
  description = "Web ACL ID"
  value       = aws_wafv2_web_acl.this.id
}
