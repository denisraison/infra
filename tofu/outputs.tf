output "server_ip" {
  value = hcloud_server.postador.ipv4_address
}

output "server_ipv6" {
  value = hcloud_server.postador.ipv6_address
}

output "server_status" {
  value = hcloud_server.postador.status
}
