output "admin_vm_id" {
  description = "The ID of the admin VM instance"
  value       = aws_instance.admin_vm.id
}

output "admin_vm_public_ip" {
  description = "The public IP address of the admin VM (via Elastic IP)"
  value       = aws_eip.admin_vm_eip.public_ip
}

output "admin_vm_private_ip" {
  description = "The private IP address of the admin VM"
  value       = aws_instance.admin_vm.private_ip
}

output "admin_vm_public_dns" {
  description = "The public DNS name of the admin VM (via Elastic IP)"
  value       = aws_eip.admin_vm_eip.public_dns
}

output "ssh_private_key" {
  description = "The private SSH key to connect to the admin VM"
  value       = nonsensitive(local.ssh_private_key)
}

output "ssh_connection_command" {
  description = "SSH command to connect to the admin VM"
  value       = "ssh -i admin_vm_key.pem ec2-user@${aws_eip.admin_vm_eip.public_ip}"
}
