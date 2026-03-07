SHELL := /bin/bash
.PHONY: help up down restart status logs logs-coder logs-db \
       build build-no-cache template-push template-create template-list template-versions \
       db-shell db-backup db-restore \
       env clean nuke ws-list ws-stop-all update

COMPOSE    := docker compose
TMPL_DIR   := templates
BACKUP_DIR := backups

# 模板名称，可通过 T=xxx 指定，例如: make build T=ttpos-dev
T :=

# Coder CLI: 优先本地，fallback 到 docker exec
CODER := $(shell command -v coder 2>/dev/null || echo "__use_docker__")
ifeq ($(CODER),__use_docker__)
  CODER_CMD = $(COMPOSE) exec coder coder
else
  CODER_CMD = coder
endif

# 自动发现所有模板（templates/ 下的子目录）
TEMPLATES := $(sort $(patsubst $(TMPL_DIR)/%/,%,$(wildcard $(TMPL_DIR)/*/)))

# 交互选择模板的 bash 脚本片段（在 recipe 中使用）
define _pick_template
if [ -n "$(T)" ]; then \
  TPL="$(T)"; \
else \
  tmpls=( $(TEMPLATES) ); \
  if [ $${#tmpls[@]} -eq 0 ]; then \
    echo "错误: $(TMPL_DIR)/ 下没有模板"; exit 1; \
  elif [ $${#tmpls[@]} -eq 1 ]; then \
    TPL="$${tmpls[0]}"; \
    echo "自动选择唯一模板: $$TPL"; \
  else \
    echo "可用模板:"; \
    for i in "$${!tmpls[@]}"; do echo "  $$((i+1))) $${tmpls[$$i]}"; done; \
    read -p "请选择模板 [1-$${#tmpls[@]}]: " choice; \
    if [[ "$$choice" =~ ^[0-9]+$$ ]] && [ "$$choice" -ge 1 ] && [ "$$choice" -le "$${#tmpls[@]}" ]; then \
      TPL="$${tmpls[$$((choice-1))]}"; \
    else \
      echo "错误: 无效选择"; exit 1; \
    fi; \
  fi; \
fi; \
if [ ! -d "$(TMPL_DIR)/$$TPL" ]; then \
  echo "错误: 模板不存在: $$TPL"; exit 1; \
fi
endef

# ========== Help ==========

help: ## 显示帮助信息
	@echo ""
	@echo "Coder 平台管理命令"
	@echo "=========================================="
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "模板相关命令支持 T=<模板名> 参数，不指定则交互选择"
	@echo "  例如: make build T=ttpos-dev"
	@echo ""
	@echo "当前可用模板:"
	@for t in $(TEMPLATES); do echo "  - $$t"; done
	@echo ""

.DEFAULT_GOAL := help

# ========== 服务管理 ==========

up: ## 启动所有服务（后台运行）
	$(COMPOSE) up -d

down: ## 停止所有服务
	$(COMPOSE) down

restart: ## 重启所有服务
	$(COMPOSE) restart

restart-coder: ## 仅重启 Coder 服务
	$(COMPOSE) restart coder

status: ## 查看服务运行状态
	$(COMPOSE) ps

# ========== 日志 ==========

logs: ## 查看所有服务日志（实时）
	$(COMPOSE) logs -f

logs-coder: ## 查看 Coder 服务日志
	$(COMPOSE) logs -f coder

logs-db: ## 查看数据库日志
	$(COMPOSE) logs -f database

# ========== 镜像构建 ==========

build: ## 构建工作区镜像（T=模板名）
	@$(_pick_template); \
	docker build -t $$TPL-workspace:latest $(TMPL_DIR)/$$TPL

build-no-cache: ## 构建工作区镜像-无缓存（T=模板名）
	@$(_pick_template); \
	docker build --no-cache -t $$TPL-workspace:latest $(TMPL_DIR)/$$TPL

# ========== 模板管理 ==========

template-push: ## 推送模板到 Coder（T=模板名）
	@$(_pick_template); \
	cd $(TMPL_DIR)/$$TPL && $(CODER_CMD) templates push $$TPL -y

template-create: ## 首次创建模板（T=模板名）
	@$(_pick_template); \
	cd $(TMPL_DIR)/$$TPL && $(CODER_CMD) templates create $$TPL -y

template-list: ## 列出所有模板
	$(CODER_CMD) templates list

template-versions: ## 查看模板版本历史（T=模板名）
	@$(_pick_template); \
	$(CODER_CMD) templates versions $$TPL

# ========== 数据库 ==========

db-shell: ## 进入数据库交互终端
	$(COMPOSE) exec database psql -U $${POSTGRES_USER:-coder} -d $${POSTGRES_DB:-coder}

db-backup: ## 备份数据库到 backups/ 目录
	@mkdir -p $(BACKUP_DIR)
	$(COMPOSE) exec database pg_dump -U $${POSTGRES_USER:-coder} $${POSTGRES_DB:-coder} \
		| gzip > $(BACKUP_DIR)/coder-db-$$(date +%Y%m%d-%H%M%S).sql.gz
	@echo "备份完成: $(BACKUP_DIR)/"
	@ls -lh $(BACKUP_DIR)/*.sql.gz | tail -1

db-restore: ## 从备份恢复数据库（用法: make db-restore FILE=backups/xxx.sql.gz）
	@test -n "$(FILE)" || (echo "错误: 请指定 FILE 参数，例如: make db-restore FILE=backups/xxx.sql.gz" && exit 1)
	@test -f "$(FILE)" || (echo "错误: 文件不存在: $(FILE)" && exit 1)
	@echo "警告: 即将恢复数据库，当前数据会被覆盖！"
	@read -p "确认继续？[y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	gunzip -c $(FILE) | $(COMPOSE) exec -T database psql -U $${POSTGRES_USER:-coder} -d $${POSTGRES_DB:-coder}
	@echo "恢复完成"

# ========== 环境配置 ==========

env: ## 生成 .env 和 .gitignore 示例文件
	@test -f .env && echo ".env 已存在，跳过" || ( \
		echo "POSTGRES_USER=coder" > .env && \
		echo "POSTGRES_PASSWORD=changeme" >> .env && \
		echo "POSTGRES_DB=coder" >> .env && \
		echo 'CODER_ACCESS_URL=http://localhost:7080' >> .env && \
		echo "" >> .env && \
		echo "# GitHub OAuth" >> .env && \
		echo "CODER_OAUTH2_GITHUB_CLIENT_ID=" >> .env && \
		echo "CODER_OAUTH2_GITHUB_CLIENT_SECRET=" >> .env && \
		echo "CODER_OAUTH2_GITHUB_ALLOWED_ORGS=" >> .env && \
		echo ".env 文件已生成，请修改其中的配置" \
	)
	@test -f .gitignore && echo ".gitignore 已存在，跳过" || ( \
		echo ".env" > .gitignore && \
		echo "backups/" >> .gitignore && \
		echo ".terraform/" >> .gitignore && \
		echo "*.tfstate" >> .gitignore && \
		echo "*.tfstate.backup" >> .gitignore && \
		echo ".terraform.lock.hcl" >> .gitignore && \
		echo ".gitignore 文件已生成" \
	)

# ========== 清理 ==========

clean: ## 停止服务并删除容器
	$(COMPOSE) down --remove-orphans

nuke: ## 停止服务并删除所有数据（危险！）
	@echo "警告: 这将删除所有容器、卷和数据！"
	@read -p "确认继续？[y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	$(COMPOSE) down -v --remove-orphans
	@echo "所有数据已清除"

# ========== 工作区管理 ==========

ws-list: ## 列出所有工作区
	$(CODER_CMD) list

ws-stop-all: ## 停止所有工作区
	@echo "停止所有运行中的工作区..."
	$(CODER_CMD) list -o json | jq -r '.[] | select(.latest_build.status=="running") | .name' | \
		xargs -I{} $(CODER_CMD) stop {}

# ========== 更新 ==========

update: ## 更新 Coder 到最新版本
	$(COMPOSE) pull coder
	$(COMPOSE) up -d coder
	@echo "Coder 已更新并重启"
