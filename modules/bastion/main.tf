# A small SSH bastion.
#
# PRIMARY PURPOSE: an SSH proxy into the private subnets, so engineers can reach Postgres
# and the internal side of the API from a laptop:
#
#   # Tunnel Postgres to localhost
#   ssh -L 5432:<rds-endpoint>:5432 ec2-user@<bastion-ip>
#
#   # Proxy anything else (curl, Postman, psql) through it
#   ssh -J ec2-user@<bastion-ip> ...
#   ssh -D 1080 ec2-user@<bastion-ip>          # SOCKS proxy
#
# Interactive login is also allowed. Forced commands and a proxy-only shell would be more
# defensible, and are not used here: engineers get a real shell with psql on it. That is a
# conscious trade, and it is why ingress is restricted by CIDR and every key is listed in
# a file that gets reviewed.
#
# Passwords are disabled outright. Keys only, and each key belongs to one person, so
# removing someone is deleting a line in envs/<env>/env.hcl and applying.
#
# SSM Session Manager also works (the instance profile allows it) and opens no port at all.
# Prefer it when you do not need port forwarding.
#
# This is the cheapest thing that works, not the best one. Tailscale or a VPN is the better
# long-term shape; EVOLUTION.md tracks that.

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-arm64"]
  }
}

resource "aws_security_group" "bastion" {
  name        = "${var.name}-bastion"
  description = "SSH bastion: inbound 22 from approved ranges only"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-bastion" }
}

resource "aws_security_group_rule" "ssh_in" {
  count             = length(var.ingress_cidrs) > 0 ? 1 : 0
  type              = "ingress"
  security_group_id = aws_security_group.bastion.id
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = var.ingress_cidrs
  description       = "SSH from approved ranges"
}

# Outbound is deliberately narrow. A bastion is a stepping stone into the private network,
# so it gets exactly what it needs: HTTPS for SSM and package updates, Postgres into the VPC.
resource "aws_security_group_rule" "https_out" {
  type              = "egress"
  security_group_id = aws_security_group.bastion.id
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "HTTPS for SSM agent and package updates"
}

resource "aws_security_group_rule" "postgres_out" {
  type              = "egress"
  security_group_id = aws_security_group.bastion.id
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  description       = "Postgres into the VPC"
}

# --- IAM: Session Manager only. The bastion has no reason to call any other AWS API. ---
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "bastion" {
  name               = "${var.name}-bastion"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = { Name = "${var.name}-bastion" }
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${var.name}-bastion"
  role = aws_iam_role.bastion.name
}

locals {
  # Keys come from env.hcl, so the authorized list is reviewed in a PR and revoking someone
  # is a one-line change. No shared key, no key handed around out of band.
  user_data = <<-EOT
    #!/bin/bash
    set -euo pipefail

    install -d -m 700 -o ec2-user -g ec2-user /home/ec2-user/.ssh
    cat > /home/ec2-user/.ssh/authorized_keys <<'KEYS'
    ${join("\n", var.ssh_public_keys)}
    KEYS
    chown ec2-user:ec2-user /home/ec2-user/.ssh/authorized_keys
    chmod 600 /home/ec2-user/.ssh/authorized_keys

    # Hardening goes in a drop-in, NOT in sshd_config. Amazon Linux 2023 ships
    # /etc/ssh/sshd_config.d/50-cloud-init.conf, and OpenSSH takes the FIRST value it sees
    # for a keyword, so a drop-in sorting before 50- is the only way to be sure password
    # auth is actually off. Editing sshd_config directly looks right and does nothing.
    cat > /etc/ssh/sshd_config.d/00-acme-hardening.conf <<'SSHD'
    # Keys only. A password on an internet-facing SSH port is not defensible.
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    ChallengeResponseAuthentication no
    PermitEmptyPasswords no
    PermitRootLogin no
    PubkeyAuthentication yes

    # Port forwarding is the whole point of this host: tunnels to Postgres and the API.
    AllowTcpForwarding yes
    AllowAgentForwarding no
    GatewayPorts no
    X11Forwarding no

    # Drop idle sessions rather than leaving an open tunnel on an unattended laptop.
    ClientAliveInterval 300
    ClientAliveCountMax 2
    SSHD
    chmod 644 /etc/ssh/sshd_config.d/00-acme-hardening.conf

    sshd -t
    systemctl restart sshd

    # psql, so the bastion is useful directly and not only as a tunnel.
    dnf install -y postgresql15 || dnf install -y postgresql
  EOT
}

resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.bastion.id]
  iam_instance_profile   = aws_iam_instance_profile.bastion.name
  user_data              = local.user_data

  # IMDSv2 required: the single most common way an SSRF becomes stolen AWS credentials.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = { Name = "${var.name}-bastion" }

  lifecycle {
    # Changing the key list should update the instance, so user_data is not ignored.
    ignore_changes = [ami]
  }
}

resource "aws_eip" "bastion" {
  instance = aws_instance.bastion.id
  domain   = "vpc"
  tags     = { Name = "${var.name}-bastion" }
}
