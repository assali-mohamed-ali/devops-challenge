output "instance_public_ip" {
  description = "Public IPv4 address of the EC2 instance."
  value       = aws_instance.app.public_ip
}

output "app_port" {
  description = "TCP port served by intern-task-app."
  value       = 8080
}
