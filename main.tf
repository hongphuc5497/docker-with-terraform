terraform {
	required_providers {
		docker = {
			source	= "kreuzwerker/docker"
			version = "2.23.0"
		}
	}
}

# provider "docker" {}
provider "docker" {
	host = "unix:///var/run/docker.sock"
}

variable "external_port" {
	default			= 8080
	type				= number
	description = "The external port that our load balancer will listen on. Must be between 8000 and 12000."
	validation {
		condition			= 8000 < var.external_port && var.external_port < 12000
		error_message = "Port must be between 8000 and 12000"
	}
}

variable "num_server_apps" {
  default     = 5
  type        = number
  description = "The number of nginx apps to spin up. Must be between 1 and 10 (exclusive)."
  validation {
    condition     = 0 < var.num_server_apps && var.num_server_apps < 10
    error_message = "Number of apps must be a number between 1 and 10."
  }
}

locals {
	nginx_base_path	 = "${path.module}/../docker"
	server_block_arr = [for d in docker_container.nginx_apps : "server ${d.name}"]
}

resource "docker_image" "nginx_app" {
	name = "nginxapp"

  triggers = {
    dir_sha1 = sha1(
      join(
        "",
        [for f in fileset(local.nginx_base_path, "*") : filesha1("${local.nginx_base_path}/${f}")]
      )
    )
  }

  build {
    path = local.nginx_base_path
    tag  = ["nginxapp:latest"]
    build_arg = {
      TEMPLATE_FILE : "nginx.app.conf.template"
    }
  }
}

resource "docker_image" "nginx_lb" {
  name = "nginxlb"

  triggers = {
    dir_sha1 = sha1(
      join(
        "",
        [for f in fileset(local.nginx_base_path, "*") : filesha1("${local.nginx_base_path}/${f}")]
      )
    )
  }

  build {
    path = local.nginx_base_path
    tag  = ["nginxlb:latest"]
    build_arg = {
      TEMPLATE_FILE : "nginx.loadbalancer.conf.template"
    }
  }
}

resource "docker_network" "nginx_network" {
  name = "nginx"
}

resource "docker_container" "nginx_apps" {
  count = var.num_server_apps
  name  = "nginx-${count.index}"
  image = docker_image.nginx_app.image_id
  env   = ["MESSAGE=HELLO WORLD FROM ${count.index}"]

  networks_advanced {
    name = docker_network.nginx_network.id
  }
}

resource "docker_container" "nginx_lb" {
  name  = "nginx-lb"
  image = docker_image.nginx_lb.image_id

  env = [
    "SERVERS=${join(";", local.server_block_arr)}",
  ]

  ports {
    external = var.external_port
    internal = "80"
  }

  networks_advanced {
    name = docker_network.nginx_network.id
  }
}
