# Auto-stop backstop.
#
# The entire cost model depends on the instance being stopped between
# sessions. t4g.medium at ~12h/month is about $0.40; left running it is ~$24.
# Documentation alone is not a sufficient control for a 60x error, so this
# stops it on a schedule regardless.
#
# Worst case a late session gets cut short and you start it again. Best case
# it saves an adopter from a bill they did not agree to.

resource "aws_scheduler_schedule" "auto_stop" {
  count = var.enable_auto_stop ? 1 : 0

  name       = "${var.name_prefix}-auto-stop"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = var.auto_stop_cron
  schedule_expression_timezone = "UTC"

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:stopInstances"
    role_arn = aws_iam_role.scheduler[0].arn

    input = jsonencode({
      InstanceIds = [aws_instance.foundry.id]
    })
  }
}

resource "aws_iam_role" "scheduler" {
  count = var.enable_auto_stop ? 1 : 0

  name_prefix = "${var.name_prefix}-sched-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "scheduler.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "scheduler" {
  count = var.enable_auto_stop ? 1 : 0

  name_prefix = "${var.name_prefix}-sched-"
  role        = aws_iam_role.scheduler[0].id

  # Stop only. This role cannot start, terminate, or touch any other instance.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "ec2:StopInstances"
      Resource = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/${aws_instance.foundry.id}"
    }]
  })
}
