variable "aws_region" {
  description = "AWS region used for provider configuration and the default AMI."
  type        = string
  default     = "us-east-1"
}

variable "ami_id" {
  description = "Plausible Ubuntu 22.04 LTS AMI ID for us-east-1; override for another region."
  type        = string
  default     = "ami-0fc5d935ebf8bc3bc"
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet."
  type        = string
  default     = "10.20.1.0/24"
}

variable "ssh_cidr" {
  description = "Single trusted IPv4 CIDR allowed to connect to SSH (port 22). Set this explicitly; do not use 0.0.0.0/0."
  type        = string
  nullable    = false

  validation {
    condition = (
      can(cidrhost(var.ssh_cidr, 0)) &&
      can(regex("^[0-9.]+/[0-9]+$", var.ssh_cidr)) &&
      try(
        tonumber(split("/", var.ssh_cidr)[1]) > 0 &&
        tonumber(split("/", var.ssh_cidr)[1]) <= 32,
        false
      )
    )
    error_message = "ssh_cidr must be a valid IPv4 CIDR with a prefix between /1 and /32. Do not expose SSH to the world."
  }
}
