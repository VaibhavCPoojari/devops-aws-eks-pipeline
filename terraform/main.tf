# 1. Connect Terraform to your S3 Bucket
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

# 2. Dynamically generate an SSH key 
# (The "Why": GitHub Actions needs a way to securely log into the servers to run setup commands)
resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
resource "aws_key_pair" "k8s_key" {
  key_name   = "k8s-ec2-key"
  public_key = tls_private_key.ssh_key.public_key_openssh
}

# 3. Security Group (The Firewall)
resource "aws_security_group" "k8s_sg" {
  name = "k8s-security-group"
  
  # Allow SSH from anywhere
  ingress { from_port = 22, to_port = 22, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] }
  
  # Allow Kubernetes Control Plane API access
  ingress { from_port = 6443, to_port = 6443, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] }
  
  # Allow NodePort traffic (Crucial for seeing your NGINX app on port 30080!)
  ingress { from_port = 30000, to_port = 32767, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] }
  
  # Allow all internal traffic between the Master and Worker nodes
  ingress { from_port = 0, to_port = 0, protocol = "-1", self = true }
  
  # Allow servers to download things from the internet
  egress  { from_port = 0, to_port = 0, protocol = "-1", cidr_blocks = ["0.0.0.0/0"] }
}

# 4. Find the latest Ubuntu 24.04 Operating System Image
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # This is Canonical's official AWS account ID
  filter { name = "name", values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"] }
}

# 5. Create the Master Node
resource "aws_instance" "master" {
  ami             = data.aws_ami.ubuntu.id
  instance_type   = "t3.medium"
  key_name        = aws_key_pair.k8s_key.key_name
  security_groups = [aws_security_group.k8s_sg.name]
  user_data       = file("user_data.sh") # Attaches the startup script from Part 1
  tags            = { Name = "k8s-master" }
}

# 6. Create the Worker Nodes (Notice the count = 2)
resource "aws_instance" "workers" {
  count           = 2
  ami             = data.aws_ami.ubuntu.id
  instance_type   = "t3.medium"
  key_name        = aws_key_pair.k8s_key.key_name
  security_groups = [aws_security_group.k8s_sg.name]
  user_data       = file("user_data.sh")
  tags            = { Name = "k8s-worker-${count.index + 1}" }
}

# 7. Outputs
# (The "Why": Once AWS builds the servers, they are assigned random IP addresses. Terraform prints them out here so our GitHub Actions script knows exactly where to connect.)
output "private_key" { value = tls_private_key.ssh_key.private_key_pem, sensitive = true }
output "master_ip" { value = aws_instance.master.public_ip }
output "worker_ips" { value = aws_instance.workers[*].public_ip }