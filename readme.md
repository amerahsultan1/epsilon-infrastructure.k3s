# KH Labs - Infrastructure as Code
## Hashicorp Terraform used to provision AWS infrastructure

This lab uses terraform to provision a 2-layered architecture, with 2 worker nodes and 1 or more controlplane nodes. It also provisions a bastion node for ssh access to the other nodes. This is an HA configuration, so we use 2 availability zones for the workers and controlplanes. This results in 5 subnets and 3 security groups. The workers are in an autoscaling group with an elb distributing work to them.

The aim of this is to create a fairly standard 2-tier architecture with a bastion for security. The machines cannot be accessed by ssh except from the bastion.

The control plane is allowed to communicate in any way it wants with the workers. All egress is allowed.

The control plane is configured with a dns name via a route53 zone and an alias ('A') record.
