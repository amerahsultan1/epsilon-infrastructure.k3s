provider "random" {}
module "tags_network" {
  source      = "git::https://github.com/cloudposse/terraform-null-label.git"
  namespace   = var.name
  environment = "dev"
  name        = "amerah-devops-bootcamp"
  delimiter   = "_"

  tags = {
    owner = var.name
    type  = "network"
  }
}

module "tags_bastion" {
  source      = "git::https://github.com/cloudposse/terraform-null-label.git"
  namespace   = var.name
  environment = "dev"
  name        = "amerah-basion-devops-bootcamp"
  delimiter   = "_"

  tags = {
    owner = var.name
    type  = "bastion"
  }
}

module "tags_worker" {
  source      = "git::https://github.com/cloudposse/terraform-null-label.git"
  namespace   = var.name
  environment = "dev"
  name        = "amerah-worker-devops-bootcamp"
  delimiter   = "_"

  tags = {
    owner = var.name
    type  = "worker"
    Name  = format("worker-%s", var.name)
  }
}

module "tags_controlplane" {
  source      = "git::https://github.com/cloudposse/terraform-null-label.git"
  namespace   = var.name
  environment = "dev"
  name        = "amerah-controlplane-devops-bootcamp"
  delimiter   = "_"

  tags = {
    owner = var.name
    type  = "controlplane"
  }
}

data "aws_ami" "latest_server" {
  most_recent = true
  owners      = ["772816346052"]

  filter {
    name   = "name"
    values = ["amerah-k3s-server*"]
  }
}

data "aws_ami" "latest_agent" {
  most_recent = true
  owners      = ["772816346052"]

  filter {
    name   = "name"
    values = ["amerah-k3s-agent*"]
  }
}

resource "aws_vpc" "lab" {
  cidr_block           = "10.0.0.0/16"
  tags                 = module.tags_network.tags
  enable_dns_hostnames = true
}

resource "aws_route53_zone" "amerah_dobc" {
  name = "amerah.dobc"
  tags = module.tags_network.tags

  vpc {
    vpc_id = aws_vpc.lab.id
  }
}

resource "aws_internet_gateway" "lab_gateway" {
  vpc_id = aws_vpc.lab.id
  tags   = module.tags_network.tags
}

resource "aws_route" "lab_internet_access" {
  route_table_id         = aws_vpc.lab.main_route_table_id
  gateway_id             = aws_internet_gateway.lab_gateway.id
  destination_cidr_block = "0.0.0.0/0"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "bastion" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]
  tags                    = module.tags_bastion.tags
}

resource "aws_subnet" "worker" {
  count                   = 2
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = format("10.0.%s.0/24", count.index + 10)
  map_public_ip_on_launch = false
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  tags                    = module.tags_worker.tags
}

resource "aws_subnet" "controlplane" {
  count                   = 1
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = format("10.0.%s.0/24", count.index + 20)
  map_public_ip_on_launch = false
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  tags                    = module.tags_controlplane.tags
}

resource "aws_security_group" "bastion" {
  vpc_id = aws_vpc.lab.id
  tags   = module.tags_bastion.tags

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "controlplane" {
  vpc_id = aws_vpc.lab.id
  tags   = module.tags_controlplane.tags

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port       = 6443
    to_port         = 6443
    protocol        = "tcp"
    security_groups = [aws_security_group.worker.id]
  }

  ingress {
    from_port       = 8763
    to_port         = 8763
    protocol        = "tcp"
    security_groups = [aws_security_group.worker.id]
  }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }
}

resource "aws_security_group" "worker" {
  vpc_id = aws_vpc.lab.id
  tags   = module.tags_worker.tags
}

resource "aws_security_group_rule" "egress_to_all" {
  type              = "egress"
  security_group_id = aws_security_group.worker.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "ssh_from_bastion" {
  type                     = "ingress"
  security_group_id        = aws_security_group.worker.id
  source_security_group_id = aws_security_group.bastion.id
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
}

resource "aws_security_group_rule" "all_from_control_plane" {
  type                     = "ingress"
  security_group_id        = aws_security_group.worker.id
  source_security_group_id = aws_security_group.controlplane.id
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
}

resource "random_id" "keypair" {
  keepers = {
    public_key = file(var.public_key_path)
  }

  byte_length = 8
}

resource "aws_key_pair" "lab_keypair" {
  key_name   = format("%s_keypair_%s", var.name, random_id.keypair.hex)
  public_key = random_id.keypair.keepers.public_key
}

resource "random_id" "worker_lc_name" {
  keepers = {
    image_id = data.aws_ami.latest_agent.id
  }

  byte_length = 8
}


resource "aws_launch_configuration" "worker" {
  name                        = format("%s-lc-%s", var.name, random_id.worker_lc_name.hex)
  image_id                    = random_id.worker_lc_name.keepers.image_id
  instance_type               = var.instance_type
  security_groups             = [aws_security_group.worker.id]
  key_name                    = aws_key_pair.lab_keypair.id
  associate_public_ip_address = true

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "workers" {
  name                      = format("%s-asg", var.name)
  max_size                  = 3
  min_size                  = 2
  launch_configuration      = aws_launch_configuration.worker.name
  health_check_grace_period = 300
  health_check_type         = "EC2"
  vpc_zone_identifier       = aws_subnet.worker.*.id
  target_group_arns         = [aws_lb_target_group.asg.arn]
  depends_on                = [aws_route53_record.controlplane]

  tag {
    key                 = "owner"
    value               = var.name
    propagate_at_launch = true
  }

  tag {
    key                 = "type"
    value               = "worker"
    propagate_at_launch = true
  }

  tag {
    key                 = "environment"
    value               = "dev"
    propagate_at_launch = true
  }

  tag {
    key                 = "name"
    value               = format("%s-devops-bootcamp-worker_node", var.name)
    propagate_at_launch = true
  }


  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb" "elb" {
  load_balancer_type = "application"
  subnets            = aws_subnet.worker.*.id
  security_groups    = [aws_security_group.worker.id]
  tags               = module.tags_worker.tags
}

resource "aws_lb_target_group" "asg" {
  name     = format("%s-tg", var.name)
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.lab.id
  tags     = module.tags_worker.tags
}

resource "aws_autoscaling_attachment" "asg" {
  autoscaling_group_name = aws_autoscaling_group.workers.id
  alb_target_group_arn   = aws_lb_target_group.asg.arn
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.elb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code  = 404
    }
  }
}

resource "aws_lb_listener_rule" "asg" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  action {
    target_group_arn = aws_lb_target_group.asg.arn
    type             = "forward"
  }

  condition {
    path_pattern {
      values = ["*"]
    }
  }
}

resource "aws_route53_record" "controlplane" {
  zone_id = aws_route53_zone.amerah_dobc.id
  name    = "controlplane"
  type    = "A"
  ttl     = 300
  records = [aws_instance.controlplane.0.private_ip]
}

resource "aws_instance" "controlplane" {
  count                       = 1
  ami                         = data.aws_ami.latest_server.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.controlplane[count.index].id
  vpc_security_group_ids      = [aws_security_group.controlplane.id]
  key_name                    = aws_key_pair.lab_keypair.id
  associate_public_ip_address = true
  tags                        = module.tags_controlplane.tags
}

resource "aws_instance" "bastion" {
  ami                    = "ami-02c7c728a7874ae7a"
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.bastion.id
  vpc_security_group_ids = [aws_security_group.bastion.id]
  key_name               = aws_key_pair.lab_keypair.id
  tags                   = module.tags_bastion.tags
}

