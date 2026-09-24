# Networking.
#
# Public subnets only, and deliberately NO NAT gateway. A NAT gateway costs
# ~$32/month standing — roughly six times this entire stack — to provide
# outbound access the instance can get directly from a public subnet. The
# compensating control is a tight security group, so keep it tight.
#
# VPC and subnet are both optional. Supply your own, or let this create a
# dedicated one.

locals {
  create_vpc    = var.vpc_id == ""
  create_subnet = var.subnet_id == ""

  vpc_id    = local.create_vpc ? aws_vpc.this[0].id : var.vpc_id
  subnet_id = local.create_subnet ? aws_subnet.public[0].id : var.subnet_id

  # The data volume is pinned to one AZ and the instance must launch there.
  availability_zone = coalesce(
    var.availability_zone,
    local.create_subnet ? data.aws_availability_zones.available.names[0] : data.aws_subnet.selected[0].availability_zone,
  )
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Read back an existing subnet so we can pin the data volume to its AZ.
data "aws_subnet" "selected" {
  count = local.create_subnet ? 0 : 1
  id    = var.subnet_id
}

resource "aws_vpc" "this" {
  count = local.create_vpc ? 1 : 0

  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = var.name_prefix }
}

resource "aws_internet_gateway" "this" {
  count = local.create_vpc ? 1 : 0

  vpc_id = aws_vpc.this[0].id
  tags   = { Name = var.name_prefix }
}

resource "aws_subnet" "public" {
  count = local.create_subnet ? 1 : 0

  vpc_id            = local.vpc_id
  cidr_block        = var.subnet_cidr
  availability_zone = coalesce(var.availability_zone, data.aws_availability_zones.available.names[0])

  # Required. Without an auto-assigned public IP the instance has no outbound
  # path (no NAT) and no inbound address for players. We deliberately do not
  # use an Elastic IP — AWS bills all public IPv4 since Feb 2024, including
  # EIPs on stopped instances, which would be the largest line item here.
  map_public_ip_on_launch = true

  tags = { Name = "${var.name_prefix}-public" }
}

resource "aws_route_table" "public" {
  count = local.create_vpc ? 1 : 0

  vpc_id = aws_vpc.this[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this[0].id
  }

  tags = { Name = "${var.name_prefix}-public" }
}

resource "aws_route_table_association" "public" {
  count = local.create_vpc && local.create_subnet ? 1 : 0

  subnet_id      = aws_subnet.public[0].id
  route_table_id = aws_route_table.public[0].id
}

# ---------------------------------------------------------------------------
# Security group
# ---------------------------------------------------------------------------

resource "aws_security_group" "instance" {
  name_prefix = "${var.name_prefix}-"
  description = "Foundry VTT: HTTPS for play, HTTP for ACME and redirect"
  vpc_id      = local.vpc_id

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = var.name_prefix }
}

# No port 22. Shell access is via SSM Session Manager, which needs no inbound
# rule and no key management (REQUIREMENTS.md R8).

resource "aws_vpc_security_group_ingress_rule" "https" {
  for_each = toset(var.allowed_cidrs)

  security_group_id = aws_security_group.instance.id
  description       = "HTTPS - Foundry play traffic"
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  for_each = toset(var.allowed_cidrs)

  security_group_id = aws_security_group.instance.id
  description       = "HTTP - ACME challenge and HTTPS redirect only"
  cidr_ipv4         = each.value
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

# Outbound is unrestricted: the instance needs ECR, S3, Route 53, Let's
# Encrypt and the distro package mirrors, and there is no NAT to route through.
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.instance.id
  description       = "All outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
