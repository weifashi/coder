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

# ========== Go 1.23 ==========
RUN wget -q https://go.dev/dl/go1.23.5.linux-amd64.tar.gz \
    && tar -C /usr/local -xzf go1.23.5.linux-amd64.tar.gz \
    && rm go1.23.5.linux-amd64.tar.gz

ENV GOPATH=/home/coder/go
ENV PATH=$PATH:/usr/local/go/bin:$GOPATH/bin
ENV GOPROXY=https://goproxy.cn,direct

# ========== Node.js 20 ==========
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && corepack enable pnpm \
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

# ========== Go 开发工具 ==========
RUN go install github.com/pilu/fresh@latest

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

# ========== Entrypoint ==========
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

# 保持 root，由 entrypoint 切换到 coder
USER root
WORKDIR /home/coder
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]