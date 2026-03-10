FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# ========== 基础工具 ==========
RUN apt-get update && apt-get install -y \
    curl wget git vim nano unzip zip \
    build-essential make gcc g++ \
    ca-certificates gnupg lsb-release \
    openssh-client sudo locales jq gosu \
    iproute2 net-tools \
    && rm -rf /var/lib/apt/lists/*

RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8

# ========== Python 3.11 ==========
RUN apt-get update && apt-get install -y \
    software-properties-common \
    && add-apt-repository ppa:deadsnakes/ppa \
    && apt-get update && apt-get install -y \
    python3.11 python3.11-dev python3.11-venv \
    && rm -rf /var/lib/apt/lists/*

RUN curl -sS https://bootstrap.pypa.io/get-pip.py | python3.11 \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1

# ========== Node.js 18 (Frappe 要求) ==========
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g yarn \
    && rm -rf /var/lib/apt/lists/*

# ========== MariaDB + Redis (容器内运行) ==========
RUN apt-get update && apt-get install -y \
    mariadb-server mariadb-client libmariadb-dev \
    redis-server \
    && rm -rf /var/lib/apt/lists/*

# ========== Frappe/ERPNext 系统依赖 ==========
RUN apt-get update && apt-get install -y \
    xvfb libfontconfig wkhtmltopdf \
    libcups2-dev pango1.0-tests \
    libcairo2-dev libjpeg-dev libgif-dev librsvg2-dev \
    && rm -rf /var/lib/apt/lists/*

# ========== Docker (完整安装，支持 DinD) ==========
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
       | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
       https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
       > /etc/apt/sources.list.d/docker.list \
    && apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# ========== Bench CLI ==========
RUN pip install frappe-bench

# ========== code-server (VS Code Web) ==========
RUN curl -fsSL https://code-server.dev/install.sh | sh

# ========== Claude Code ==========
RUN npm install -g @anthropic-ai/claude-code

# ========== 创建 coder 用户 ==========
RUN useradd -m -s /bin/bash -u 1000 coder \
    && echo "coder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/coder \
    && chmod 0440 /etc/sudoers.d/coder

RUN groupadd -g 998 docker 2>/dev/null || true \
    && usermod -aG docker coder

# ========== MariaDB 配置 (Frappe 要求) ==========
RUN printf '[mysqld]\ncharacter-set-server = utf8mb4\ncollation-server = utf8mb4_unicode_ci\n\n[mysql]\ndefault-character-set = utf8mb4\n' \
    > /etc/mysql/mariadb.conf.d/frappe.cnf

# ========== Entrypoint ==========
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

USER root
WORKDIR /home/coder
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
