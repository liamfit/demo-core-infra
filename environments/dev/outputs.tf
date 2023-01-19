# Generated API GW endpoint URL that can be used to access the application running on a private ECS Fargate cluster.
output "apigw_endpoint" {
  value       = aws_apigatewayv2_api.apigw_http_endpoint.api_endpoint
  description = "API Gateway Endpoint"
}
