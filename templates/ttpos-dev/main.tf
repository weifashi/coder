terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 2.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "coder" {}
provider "docker" {}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# ========== 工作区参数 ==========

data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU (核心)"
  description  = "分配给工作区的 CPU 核心数"
  default      = "8"
  type         = "number"
  mutable      = true
  option {
    name  = "2 核"
    value = "2"
  }
  option {
    name  = "4 核"
    value = "4"
  }
  option {
    name  = "8 核"
    value = "8"
  }
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "内存 (MB)"
  description  = "分配给工作区的内存大小"
  default      = "16384"
  type         = "number"
  mutable      = true
  option {
    name  = "4 GB"
    value = "4096"
  }
  option {
    name  = "8 GB"
    value = "8192"
  }
  option {
    name  = "16 GB"
    value = "16384"
  }
}

# ========== Docker 镜像 ==========

resource "docker_image" "workspace" {
  name         = "ttpos-workspace:latest"
  force_remove = true
  build {
    context    = "./."
    dockerfile = "Dockerfile"
  }
  triggers = {
    dockerfile_hash  = filemd5("${path.module}/Dockerfile")
    entrypoint_hash  = filemd5("${path.module}/entrypoint.sh")
  }
}

# ========== Coder Agent ==========

resource "coder_agent" "main" {
  os   = "linux"
  arch = "amd64"
  dir  = "/home/coder/workspaces"

  display_apps {
    vscode                 = true
    web_terminal           = true
    ssh_helper             = true
    port_forwarding_helper = true
  }

  # ========== 工作区指标 ==========

  metadata {
    display_name = "CPU 使用率"
    key          = "cpu"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "内存使用率"
    key          = "mem"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Home 磁盘"
    key          = "disk"
    script       = "coder stat disk --path /home/coder"
    interval     = 60
    timeout      = 1
  }

  # ========== 宿主机指标 ==========

  metadata {
    display_name = "CPU 使用率（宿主机）"
    key          = "cpu_host"
    script       = "coder stat cpu --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "内存使用率（宿主机）"
    key          = "mem_host"
    script       = "coder stat mem --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "平均负载（宿主机）"
    key          = "load_host"
    script       = "cat /proc/loadavg | awk '{print $1}'"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "交换分区使用率（宿主机）"
    key          = "swap_host"
    script       = "free -b | grep Swap | awk '{if($2>0) printf \"%.1f/%.1f GiB (%d%%)\", $3/1073741824, $2/1073741824, $3/$2*100; else print \"N/A\"}'"
    interval     = 10
    timeout      = 1
  }
  startup_script = <<-EOT
    #!/bin/bash
    set -e

    # 等待 DinD dockerd 就绪
    for i in $(seq 1 30); do
      if docker info > /dev/null 2>&1; then
        break
      fi
      sleep 1
    done

    # 启动 code-server（VS Code 网页版）
    echo "🌐 启动 code-server..."
    code-server \
      --auth none \
      --port 13337 \
      --host :: \
      --disable-telemetry \
      /home/coder/workspaces > /tmp/code-server.log 2>&1 &

    echo "✅ 工作区就绪"
  EOT
}

# ========== VS Code 网页版（code-server）==========

resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "VS Code Web"
  icon         = "/icon/code.svg"
  url          = "http://localhost:13337/?folder=/home/coder/workspaces"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 5
    threshold = 6
  }
}

# ========== Cursor 按钮 ==========

resource "coder_app" "cursor" {
  agent_id     = coder_agent.main.id
  slug         = "cursor"
  display_name = "Cursor Desktop"
  icon         = "/icon/cursor.svg"
  external     = true
  url = join("", [
    "cursor://coder.coder-remote/open",
    "?owner=", data.coder_workspace_owner.me.name,
    "&workspace=", data.coder_workspace.me.name,
    "&url=", urlencode(data.coder_workspace.me.access_url),
    "&agent=main",
    "&folder=", urlencode("/home/coder/workspaces"),
  ])
}

# ========== Docker 容器 ==========

resource "docker_container" "workspace" {
  name     = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}"
  image    = docker_image.workspace.image_id
  must_run = true

  cpu_shares = tonumber(data.coder_parameter.cpu.value) * 1024
  memory     = tonumber(data.coder_parameter.memory.value) * 1024

  entrypoint = ["/usr/local/bin/entrypoint.sh"]
  command    = ["sh", "-c", coder_agent.main.init_script]

  privileged = true

  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
  ]

  volumes {
    volume_name    = docker_volume.home.name
    container_path = "/home/coder"
  }

  volumes {
    volume_name    = docker_volume.docker.name
    container_path = "/var/lib/docker"
  }

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  hostname = data.coder_workspace.me.name
  dns      = ["8.8.8.8", "8.8.4.4"]
}

# ========== 持久化存储 ==========

resource "docker_volume" "home" {
  name = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}-home"
  lifecycle {
    ignore_changes = all
  }
}

resource "docker_volume" "docker" {
  name = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}-docker"
  lifecycle {
    ignore_changes = all
  }
}