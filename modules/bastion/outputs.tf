output "public_ip" {
  description = "Elastic IP for SSH"
  value       = aws_eip.bastion.public_ip
}

output "instance_id" {
  description = "Instance ID, for: aws ssm start-session --target <id>"
  value       = aws_instance.bastion.id
}

output "security_group_id" {
  description = "Bastion security group ID"
  value       = aws_security_group.bastion.id
}

output "ssh_proxy_hint" {
  description = "How to tunnel through the bastion"
  value       = "ssh -L 5432:<rds-endpoint>:5432 ec2-user@${aws_eip.bastion.public_ip}"
}
