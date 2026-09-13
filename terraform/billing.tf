# Cost guardrails.
#
# Per org policy these exist before anything meaningful bills. The failure
# mode this tool actually has is forgetting to stop the instance, not
# overspending — leaving it running costs roughly 60x the intended bill.

resource "aws_sns_topic" "alerts" {
  name_prefix = "${var.name_prefix}-"
}

resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email

  # Confirm the subscription from your inbox. Until you do, these alarms are
  # decoration. Terraform cannot confirm it for you.
}

resource "aws_budgets_budget" "monthly" {
  name         = "${var.name_prefix}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Warn on the way up, not once it is already spent.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}

# Billing metrics are only published in us-east-1, whatever region the stack
# runs in — hence the provider alias.
resource "aws_cloudwatch_metric_alarm" "billing" {
  provider = aws.billing

  alarm_name          = "${var.name_prefix}-estimated-charges"
  alarm_description   = "Estimated monthly charges exceeded the budget threshold"
  namespace           = "AWS/Billing"
  metric_name         = "EstimatedCharges"
  dimensions          = { Currency = "USD" }
  statistic           = "Maximum"
  period              = 21600 # 6h — the metric only updates a few times a day
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.budget_limit_usd
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
}
