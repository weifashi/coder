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
  default      = "4"
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
  default      = "8192"
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
  name = "erpnext-workspace:latest"
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
    vscode       = true
    web_terminal = true
    ssh_helper   = true
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

    # 修复 Docker socket 权限
    if [ -S /var/run/docker.sock ]; then
      sudo chmod 666 /var/run/docker.sock
    fi

    # 初始化 frappe-bench（首次启动时）
    if [ ! -d /home/coder/workspaces/frappe-bench ]; then
      echo "🔧 初始化 frappe-bench..."
      cd /home/coder/workspaces
      bench init frappe-bench --frappe-branch version-15
      cd frappe-bench
      bench get-app erpnext --branch version-15
      bench new-site dev.localhost \
        --mariadb-root-password '' \
        --admin-password admin \
        --install-app erpnext
      bench use dev.localhost
      bench set-config developer_mode 1
      echo "✅ ERPNext 初始化完成"
    fi

    # 启动 code-server（VS Code 网页版）
    echo "🌐 启动 code-server..."
    code-server \
      --auth none \
      --port 13337 \
      --host :: \
      --disable-telemetry \
      /home/coder/workspaces/frappe-bench > /tmp/code-server.log 2>&1 &

    # 启动 bench（ERPNext 开发服务器）
    echo "🚀 启动 ERPNext 开发服务器..."
    cd /home/coder/workspaces/frappe-bench
    bench start > /tmp/bench.log 2>&1 &

    echo "✅ 工作区就绪"
  EOT
}

# ========== VS Code 网页版（code-server）==========

resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "VS Code Web"
  icon         = "/icon/code.svg"
  url          = "http://localhost:13337/?folder=/home/coder/workspaces/frappe-bench"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 5
    threshold = 6
  }
}

# ========== ERPNext Web ==========

resource "coder_app" "erpnext" {
  agent_id     = coder_agent.main.id
  slug         = "erpnext"
  display_name = "ERPNext"
  icon         = "/emojis/1f4ca.png"
  url          = "http://localhost:8000"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:8000/api/method/ping"
    interval  = 10
    threshold = 12
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
    "&folder=", urlencode("/home/coder/workspaces/frappe-bench"),
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

  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
  ]

  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
  }

  volumes {
    volume_name    = docker_volume.home.name
    container_path = "/home/coder"
  }

  # MariaDB 数据持久化
  volumes {
    volume_name    = docker_volume.mariadb.name
    container_path = "/var/lib/mysql"
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

resource "docker_volume" "mariadb" {
  name = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}-mariadb"
  lifecycle {
    ignore_changes = all
  }
}
