module "label" {
  source    = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.16.0"
  namespace = var.namespace
  stage     = var.stage
  name      = var.name
  tags      = var.tags

  additional_tag_map = {
    propagate_at_launch = "true"
  }
}

module "role_label" {
  source     = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.16.0"
  namespace  = var.namespace
  stage      = var.stage
  name       = var.name
  attributes = ["role"]
}

#####################
## SSM AGENT ROLE ##
###################

data "aws_iam_policy_document" "default" {

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "default" {
  name                 = module.role_label.id
  assume_role_policy   = data.aws_iam_policy_document.default.json
  permissions_boundary = var.permissions_boundary
  tags                 = module.role_label.tags
}

resource "aws_iam_role_policy_attachment" "default" {
  role       = aws_iam_role.default.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "default" {
  name = module.role_label.id
  role = aws_iam_role.default.name
}

#####################
## SECURITY GROUP ##
###################

resource "aws_security_group" "default" {
  vpc_id      = var.vpc_id
  name        = module.label.id
  description = "Allow ALL egress from SSM Agent."
  tags        = module.label.tags
}

resource "aws_security_group_rule" "allow_all_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.default.id
}

############################
## LAUNCH TEMPLATE + ASG ##
##########################

resource "aws_launch_template" "default" {
  name_prefix   = module.label.id
  image_id      = var.ami != "" ? var.ami : data.aws_ami.amazon_linux_2.id
  instance_type = var.instance_type

  monitoring {
    enabled = true
  }

  network_interfaces {
    associate_public_ip_address = false
    delete_on_termination       = true
    security_groups             = [aws_security_group.default.id]
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.default.name
  }

  user_data = base64encode(var.user_data)

  tag_specifications {
    resource_type = "instance"
    tags          = module.label.tags
  }

  tag_specifications {
    resource_type = "volume"
    tags          = module.label.tags
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "default" {
  name_prefix = "${module.label.id}-asg"
  tags        = module.label.tags_as_list_of_maps

  launch_template {
    id      = aws_launch_template.default.id
    version = "$Latest"
  }

  max_size         = var.instance_count
  min_size         = var.instance_count
  desired_capacity = var.instance_count

  vpc_zone_identifier = var.subnet_ids

  default_cooldown          = 180
  health_check_grace_period = 180
  health_check_type         = "EC2"

  termination_policies = [
    "OldestLaunchConfiguration",
  ]

  lifecycle {
    create_before_destroy = true
  }
}
