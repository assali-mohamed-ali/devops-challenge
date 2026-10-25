locals {
  app_port = 8080
  app_name = "intern-task-app"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "intern-task-vpc"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  map_public_ip_on_launch = true

  tags = {
    Name = "intern-task-public-subnet"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "intern-task-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "intern-task-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "app" {
  name        = "intern-task-app-sg"
  description = "Allow SSH only from the configured CIDR and HTTP app traffic on port 8080."
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from the explicitly configured trusted CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_cidr]
  }

  ingress {
    description = "Intern task application"
    from_port   = local.app_port
    to_port     = local.app_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Outbound access for package installation and image build"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "intern-task-app-sg"
  }
}

resource "aws_instance" "app" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.app.id]
  associate_public_ip_address = true
  user_data_replace_on_change = false

  # Bootstrap downloads packages and therefore needs the public route to exist.
  depends_on = [aws_route_table_association.public]

  user_data = <<-USERDATA
    #!/bin/bash
    set -euxo pipefail
    exec > >(tee -a /var/log/intern-task-bootstrap.log | logger -t intern-task-bootstrap -s 2>/dev/console) 2>&1

    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y docker.io ufw

    # Create a non-root administrative user with passwordless sudo.
    if ! id appadmin >/dev/null 2>&1; then
      useradd --create-home --shell /bin/bash appadmin
    fi
    usermod -aG sudo,docker appadmin
    passwd -l appadmin
    printf '%s\n' 'appadmin ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/appadmin
    chmod 0440 /etc/sudoers.d/appadmin
    visudo -cf /etc/sudoers.d/appadmin

    systemctl enable --now docker

    # Install the actual app source and the same Dockerfile used by Task 1.
    install -d -m 0755 /opt/intern-task-app/app
    cat > /opt/intern-task-app/app/app.py <<'PYAPP'
    import http.server
    import os

    PORT = int(os.environ.get("PORT", "5000"))


    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == "/healthz":
                body = b"ok\n"
            else:
                body = b"hello from intern-task\n"
            self.send_response(200)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, fmt, *args):
            pass


    if __name__ == "__main__":
        print(f"listening on 0.0.0.0:{PORT}", flush=True)
        http.server.HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
    PYAPP

    cat > /opt/intern-task-app/Dockerfile <<'DOCKERFILE'
    FROM python:3.13-slim-bookworm

    ENV PORT=8080 \
        PYTHONDONTWRITEBYTECODE=1 \
        PYTHONUNBUFFERED=1

    WORKDIR /app

    RUN groupadd --system --gid 10001 app \
        && useradd --system --uid 10001 --gid app \
           --no-create-home --shell /usr/sbin/nologin app

    COPY --chown=10001:10001 app/app.py ./app.py

    USER 10001:10001

    EXPOSE 8080

    CMD ["python", "app.py"]
    DOCKERFILE

    docker build --pull -t intern-task-app:local /opt/intern-task-app

    # Host firewall: deny unsolicited inbound traffic except trusted SSH and app port.
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow from "${var.ssh_cidr}" to any port 22 proto tcp
    ufw allow 8080/tcp
    ufw --force enable

    # Host networking keeps the published app port subject to the host firewall.
    cat > /etc/systemd/system/intern-task-app.service <<'UNIT'
    [Unit]
    Description=Intern Task application container
    Requires=docker.service
    After=docker.service network-online.target
    Wants=network-online.target

    [Service]
    Type=simple
    ExecStartPre=-/usr/bin/docker rm -f intern-task-app
    ExecStart=/usr/bin/docker run --rm --name intern-task-app --network host --env PORT=8080 intern-task-app:local
    ExecStop=/usr/bin/docker stop --time 10 intern-task-app
    Restart=always
    RestartSec=5
    TimeoutStartSec=0
    TimeoutStopSec=20

    [Install]
    WantedBy=multi-user.target
    UNIT

    systemctl daemon-reload
    systemctl enable --now intern-task-app.service
  USERDATA

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 8
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = {
    Name = "intern-task-app"
  }
}
