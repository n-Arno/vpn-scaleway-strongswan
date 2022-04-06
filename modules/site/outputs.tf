output "ip" {
  value = scaleway_instance_ip.public_ip.address
}

output "ssh" {
  value = format("ssh root@%s", scaleway_instance_ip.public_ip.address)
}

output "name" {
  value = scaleway_instance_server.vpn_gw.name
}

output "subnet" {
  value = format("%s.0/24", var.net_prefix)
}
