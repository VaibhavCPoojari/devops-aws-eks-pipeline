terraform {
  backend "s3" {
    bucket = "devops-k8s-state-vaibhav" 
    key    = "k8s-cluster/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" { 
  region = "us-east-1" 
}

resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "k8s_key" {
  key_name   = "k8s-ec2-key"
  public_key = tls_private_key.ssh_key.public_key_openssh
}

resource "aws_security_group" "k8s_sg" {
  name = "k8s-security-group"
  
  ingress { 
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }
  
  ingress { 
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }
  
  ingress { 
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }
  
  ingress { 
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true 
  }
  
  egress { 
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] 
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] 
  
  filter { 
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"] 
  }
}

resource "aws_instance" "master" {
  ami             = data.aws_ami.ubuntu.id
  instance_type   = "t3.medium"
  key_name        = aws_key_pair.k8s_key.key_name
  security_groups = [aws_security_group.k8s_sg.name]
  user_data       = file("user_data.sh") 
  tags            = { Name = "k8s-master" }
}

resource "aws_instance" "workers" {
  count           = 2
  ami             = data.aws_ami.ubuntu.id
  instance_type   = "t3.medium"
  key_name        = aws_key_pair.k8s_key.key_name
  security_groups = [aws_security_group.k8s_sg.name]
  user_data       = file("user_data.sh")
  tags            = { Name = "k8s-worker-${count.index + 1}" }
}

output "private_key" { 
  value     = tls_private_key.ssh_key.private_key_pem
  sensitive = true 
}

output "master_ip" { 
  value = aws_instance.master.public_ip 
}

output "worker_ips" { 
  value = aws_instance.workers[*].public_ip 
}