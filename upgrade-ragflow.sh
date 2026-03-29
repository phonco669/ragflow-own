#!/bin/bash
# RAGFlow 升级脚本
# 从 v0.24.0 升级到最新版本，保留 Logo 修改

set -e  # 遇到错误立即退出

echo "=========================================="
echo "RAGFlow 升级脚本"
echo "从 v0.24.0 升级到最新版本"
echo "=========================================="

# 配置
BACKUP_DIR=~/ragflow-backup-$(date +%Y%m%d-%H%M%S)
OLD_RAGFLOW_DIR=~/ragflow-old-v0.24.0
NEW_RAGFLOW_DIR=~/ragflow
LOGO_DIR="/path/to/your/logo"  # 需要替换为实际的 Logo 路径

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 步骤1: 数据备份
echo ""
echo -e "${YELLOW}步骤 1/6: 备份数据...${NC}"
mkdir -p $BACKUP_DIR
cd $BACKUP_DIR

echo "备份目录: $BACKUP_DIR"

# 备份 MySQL
echo "  - 备份 MySQL 数据库..."
MYSQL_CONTAINER=$(docker ps --format "{{.Names}}" | grep -E "mysql|mariadb" | head -1)
if [ -n "$MYSQL_CONTAINER" ]; then
    docker exec $MYSQL_CONTAINER mysqldump -u root -p ragflow > mysql-backup.sql 2>/dev/null || echo "  警告: MySQL 备份可能需要密码"
else
    echo "  警告: 未找到 MySQL 容器"
fi

# 备份 Docker Volumes
echo "  - 备份 Docker Volumes..."

# MinIO
MINIO_VOLUME=$(docker volume ls --format "{{.Name}}" | grep -i minio | head -1)
if [ -n "$MINIO_VOLUME" ]; then
    docker run --rm -v $MINIO_VOLUME:/data -v $(pwd):/backup alpine tar czf /backup/minio-backup.tar.gz -C /data . 2>/dev/null || echo "  警告: MinIO 备份失败"
else
    echo "  警告: 未找到 MinIO Volume"
fi

# Elasticsearch
ES_VOLUME=$(docker volume ls --format "{{.Name}}" | grep -E "esdata|elastic" | head -1)
if [ -n "$ES_VOLUME" ]; then
    docker run --rm -v $ES_VOLUME:/data -v $(pwd):/backup alpine tar czf /backup/es-backup.tar.gz -C /data . 2>/dev/null || echo "  警告: ES 备份失败"
else
    echo "  警告: 未找到 Elasticsearch Volume"
fi

# Redis
REDIS_VOLUME=$(docker volume ls --format "{{.Name}}" | grep -i redis | head -1)
if [ -n "$REDIS_VOLUME" ]; then
    docker run --rm -v $REDIS_VOLUME:/data -v $(pwd):/backup alpine tar czf /backup/redis-backup.tar.gz -C /data . 2>/dev/null || echo "  警告: Redis 备份失败"
else
    echo "  警告: 未找到 Redis Volume"
fi

# 记录版本
echo "v0.24.0" > version.txt

echo -e "${GREEN}备份完成!${NC}"
echo "备份文件:"
ls -lh $BACKUP_DIR

# 步骤2: 停止服务
echo ""
echo -e "${YELLOW}步骤 2/6: 停止当前服务...${NC}"
cd $NEW_RAGFLOW_DIR/docker 2>/dev/null || cd $NEW_RAGFLOW_DIR
docker compose -f docker-compose.yml down 2>/dev/null || docker-compose down 2>/dev/null || echo "服务已停止或不存在"

# 步骤3: 备份旧代码
echo ""
echo -e "${YELLOW}步骤 3/6: 备份旧代码...${NC}"
if [ -d "$NEW_RAGFLOW_DIR" ]; then
    mv $NEW_RAGFLOW_DIR $OLD_RAGFLOW_DIR
    echo "旧代码已备份到: $OLD_RAGFLOW_DIR"
fi

# 步骤4: 克隆新版本
echo ""
echo -e "${YELLOW}步骤 4/6: 克隆最新版本...${NC}"
git clone https://github.com/infiniflow/ragflow.git $NEW_RAGFLOW_DIR
cd $NEW_RAGFLOW_DIR

# 获取最新标签
LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "main")
echo "最新版本: $LATEST_TAG"
git checkout $LATEST_TAG

# 步骤5: 应用 Logo 修改
echo ""
echo -e "${YELLOW}步骤 5/6: 应用 Logo 修改...${NC}"

# 5.1 修改 conf.json
cat > web/src/conf.json << 'EOF'
{
  "appName": "元析立方"
}
EOF
echo "  - 已修改 conf.json"

# 5.2 修改 index.html
cd web
sed -i 's/<title>.*<\/title>/<title>元析立方<\/title>/g' index.html
echo "  - 已修改 index.html"

# 5.3 复制 Logo 文件
if [ -d "$LOGO_DIR" ]; then
    cp "$LOGO_DIR/logo.svg" public/logo.svg
    cp "$LOGO_DIR/logo-with-text.svg" src/assets/logo-with-text.svg
    echo "  - 已复制 Logo 文件"
else
    echo -e "${RED}  警告: 未找到 Logo 目录 $LOGO_DIR${NC}"
    echo "  请手动复制 Logo 文件到:"
    echo "    - web/public/logo.svg"
    echo "    - web/src/assets/logo-with-text.svg"
fi

# 5.4 修改 locales/en.ts
sed -i "s/title: 'A leading RAG engine for LLM context'/title: '元析立方 MetaCube'/g" src/locales/en.ts
sed -i "s/welcome: 'Welcome to'/welcome: '欢迎来到'/g" src/locales/en.ts
sed -i "s/title: 'RAGFlow'/title: '元析立方'/g" src/locales/en.ts
echo "  - 已修改 locales/en.ts"

# 5.5 修改 locales/zh.ts
sed -i "s/title: 'A leading RAG engine for LLM context'/title: '元析立方 MetaCube'/g" src/locales/zh.ts
echo "  - 已修改 locales/zh.ts"

# 5.6 修改 banner.tsx
sed -i "s/{t('header.welcome')}/欢迎来到/g" src/pages/home/banner.tsx
sed -i "s/RAGFlow/元析立方/g" src/pages/home/banner.tsx
echo "  - 已修改 banner.tsx"

# 5.7 修改 login-next/index.tsx
sed -i "s/RAGFlow/元析立方/g" src/pages/login-next/index.tsx
echo "  - 已修改 login-next/index.tsx"

# 5.8 修改 next-search/search-view.tsx
sed -i "s/RAGFlow/元析立方/g" src/pages/next-search/search-view.tsx
echo "  - 已修改 next-search/search-view.tsx"

echo -e "${GREEN}Logo 修改应用完成!${NC}"

# 步骤6: 编译前端
echo ""
echo -e "${YELLOW}步骤 6/6: 编译前端...${NC}"
echo "  - 安装依赖..."
npm install

echo "  - 编译..."
npm run build

# 复制编译结果到 docker 目录
echo "  - 复制编译结果..."
mkdir -p ../docker/nginx
cp -r dist/* ../docker/nginx/ 2>/dev/null || cp -r dist ../docker/nginx/

echo -e "${GREEN}编译完成!${NC}"

# 启动服务
echo ""
echo -e "${YELLOW}启动服务...${NC}"
cd ../docker
docker compose -f docker-compose.yml up -d

echo ""
echo "=========================================="
echo -e "${GREEN}升级完成!${NC}"
echo "=========================================="
echo ""
echo "备份位置: $BACKUP_DIR"
echo "旧代码位置: $OLD_RAGFLOW_DIR"
echo ""
echo "请检查服务状态:"
echo "  docker compose ps"
echo ""
echo "查看日志:"
echo "  docker logs -f ragflow-server"
echo ""
echo "访问地址: http://your-server-ip"
