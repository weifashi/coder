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

# ========== 开发环境选择 ==========

data "coder_parameter" "install_go" {
  name         = "install_go"
  display_name = "Go 1.23"
  description  = "安装 Go 1.23 开发环境"
  type         = "bool"
  default      = "true"
  mutable      = false
  icon         = "/emojis/1f439.png"
}

data "coder_parameter" "install_nodejs" {
  name         = "install_nodejs"
  display_name = "Node.js 20"
  description  = "安装 Node.js 20 + pnpm"
  type         = "bool"
  default      = "true"
  mutable      = false
  icon         = "/emojis/1f7e2.png"
}

data "coder_parameter" "install_php" {
  name         = "install_php"
  display_name = "PHP 8.3"
  description  = "安装 PHP 8.3 + Composer"
  type         = "bool"
  default      = "false"
  mutable      = false
  icon         = "/emojis/1f418.png"
}

data "coder_parameter" "install_python" {
  name         = "install_python"
  display_name = "Python 3.11"
  description  = "安装 Python 3.11 + pip"
  type         = "bool"
  default      = "false"
  mutable      = false
  icon         = "/emojis/1f40d.png"
}

data "coder_parameter" "start_port" {
  name         = "start_port"
  display_name = "宿主机起始端口"
  description  = "映射到宿主机的起始端口号（会映射 10 个端口：起始端口+0 到 +9 对应容器内 8000-8009）。不同工作区请使用不同的起始端口避免冲突。"
  type         = "number"
  default      = "10000"
  mutable      = false
  icon         = "/emojis/1f310.png"
}

# ========== Docker 镜像 ==========

locals {
  cpu    = 8
  memory = 16384

  lang_tag = join("-", compact([
    data.coder_parameter.install_go.value == "true" ? "go" : "",
    data.coder_parameter.install_nodejs.value == "true" ? "node" : "",
    data.coder_parameter.install_php.value == "true" ? "php" : "",
    data.coder_parameter.install_python.value == "true" ? "py" : "",
  ]))
}

resource "docker_image" "workspace" {
  name         = "ttpos-workspace:${local.lang_tag != "" ? local.lang_tag : "base"}"
  force_remove = true
  build {
    context    = "./."
    dockerfile = "Dockerfile"
    build_args = {
      INSTALL_GO      = data.coder_parameter.install_go.value
      INSTALL_NODEJS  = data.coder_parameter.install_nodejs.value
      INSTALL_PHP     = data.coder_parameter.install_php.value
      INSTALL_PYTHON  = data.coder_parameter.install_python.value
    }
  }
  triggers = {
    dockerfile_hash = filemd5("${path.module}/Dockerfile")
    entrypoint_hash = filemd5("${path.module}/entrypoint.sh")
    install_go      = data.coder_parameter.install_go.value
    install_nodejs  = data.coder_parameter.install_nodejs.value
    install_php     = data.coder_parameter.install_php.value
    install_python  = data.coder_parameter.install_python.value
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

  cpu_shares = local.cpu * 1024
  memory     = local.memory * 1024

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

  # 端口映射：宿主机 start_port+0~+9 -> 容器 8000~8009
  dynamic "ports" {
    for_each = range(10)
    content {
      internal = 8000 + ports.value
      external = tonumber(data.coder_parameter.start_port.value) + ports.value
      protocol = "tcp"
    }
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