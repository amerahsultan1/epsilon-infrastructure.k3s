output "controlplane" {
  value = aws_instance.controlplane.0.public_ip
}
