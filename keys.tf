resource "random_string" "rke2_token" {
  length = 64
}

resource "openstack_compute_keypair_v2" "key" {
  name       = "${var.name}-key"
  public_key = file(var.ssh_public_key_file)
}

resource "null_resource" "write_kubeconfig" {
  count = var.ff_write_kubeconfig ? 1 : 0

  triggers = {
    servers = join(",", flatten([for server in module.servers : server.id]))
  }

  depends_on = [
    module.servers[0].id
  ]

  connection {
    host  = module.servers[0].floating_ips[0]
    user  = var.servers[0].system_user
    agent = true
  }

  provisioner "local-exec" {
    command = <<EOF
      ssh-keygen -R ${module.servers[0].floating_ips[0]} >/dev/null 2>&1
      until ssh -o StrictHostKeyChecking=accept-new ${var.servers[0].system_user}@${module.servers[0].floating_ips[0]} true > /dev/null 2>&1; do echo Wait for SSH availability && sleep 10; done
      until ssh ${var.servers[0].system_user}@${module.servers[0].floating_ips[0]} ls /etc/rancher/rke2/rke2.yaml > /dev/null 2>&1; do echo Wait rke2.yaml generation && sleep 10; done
      rsync --rsync-path="sudo rsync" ${var.servers[0].system_user}@${module.servers[0].floating_ips[0]}:/etc/rancher/rke2/rke2.yaml rke2.yaml \
      && chmod go-r rke2.yaml \
      && yq eval --inplace '.clusters[0].name = "${var.name}-cluster"' rke2.yaml \
      && yq eval --inplace '.clusters[0].cluster.server = "https://${module.servers[0].floating_ips[0]}:6443"' rke2.yaml \
      && yq eval --inplace '.users[0].name = "${var.name}-user"' rke2.yaml \
      && yq eval --inplace '.contexts[0].context.cluster = "${var.name}-cluster"' rke2.yaml \
      && yq eval --inplace '.contexts[0].context.user = "${var.name}-user"' rke2.yaml \
      && yq eval --inplace '.contexts[0].name = "${var.name}"' rke2.yaml \
      && yq eval --inplace '.current-context = "${var.name}"' rke2.yaml
    EOF
  }
}
