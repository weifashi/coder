FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# ========== 构建参数 ==========
ARG INSTALL_GO=true
ARG INSTALL_NODEJS=true
ARG INSTALL_PHP=false
ARG INSTALL_PYTHON=false

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

# ========== Go ==========
RUN if [ "$INSTALL_GO" = "true" ]; then \
    wget -q https://go.dev/dl/go1.23.5.linux-amd64.tar.gz \
    && tar -C /usr/local -xzf go1.23.5.linux-amd64.tar.gz \
    && rm go1.23.5.linux-amd64.tar.gz; \
    fi

ENV GOPATH=/home/coder/go
ENV PATH=$PATH:/usr/local/go/bin:$GOPATH/bin
ENV GOPROXY=https://goproxy.cn,direct

RUN if [ "$INSTALL_GO" = "true" ]; then \
    go install github.com/pilu/fresh@latest; \
    fi

# ========== Node.js 20 ==========
RUN if [ "$INSTALL_NODEJS" = "true" ]; then \
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && corepack enable pnpm \
    && rm -rf /var/lib/apt/lists/*; \
    fi

# ========== PHP 8.3 ==========
RUN if [ "$INSTALL_PHP" = "true" ]; then \
    apt-get update \
    && apt-get install -y software-properties-common \
    && add-apt-repository ppa:ondrej/php \
    && apt-get update \
    && apt-get install -y \
       php8.3 php8.3-cli php8.3-fpm php8.3-common \
       php8.3-mysql php8.3-pgsql php8.3-sqlite3 \
       php8.3-curl php8.3-gd php8.3-mbstring php8.3-xml \
       php8.3-zip php8.3-bcmath php8.3-intl php8.3-redis \
       composer \
    && rm -rf /var/lib/apt/lists/*; \
    fi

# ========== Python 3.11 ==========
RUN if [ "$INSTALL_PYTHON" = "true" ]; then \
    apt-get update \
    && apt-get install -y software-properties-common \
    && add-apt-repository ppa:deadsnakes/ppa \
    && apt-get update \
    && apt-get install -y python3.11 python3.11-dev python3.11-venv \
    && curl -sS https://bootstrap.pypa.io/get-pip.py | python3.11 \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1 \
    && rm -rf /var/lib/apt/lists/*; \
    fi

# ========== Docker (完整安装，支持 DinD) ==========
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
       | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
       https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
       > /etc/apt/sources.list.d/docker.list \
    && apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# ========== code-server (VS Code Web) ==========
RUN curl -fsSL https://code-server.dev/install.sh | sh

# ========== Claude Code (需要 Node.js) ==========
RUN if command -v npm > /dev/null 2>&1; then \
    npm install -g @anthropic-ai/claude-code; \
    fi

# ========== 创建 coder 用户 ==========
RUN useradd -m -s /bin/bash -u 1000 coder \
    && echo "coder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/coder \
    && chmod 0440 /etc/sudoers.d/coder

RUN groupadd -g 998 docker 2>/dev/null || true \
    && usermod -aG docker coder

# ========== Entrypoint ==========
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

USER root
WORKDIR /home/coder
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
