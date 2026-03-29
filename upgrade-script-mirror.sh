#!/bin/bash
# RAGFlow 升级脚本 - 使用国内镜像加速
# 使用方法: bash upgrade-script-mirror.sh

set -e

echo "=========================================="
echo "RAGFlow 升级脚本 (国内镜像版)"
echo "=========================================="

# 配置
BACKUP_DIR=~/ragflow-backup-$(date +%Y%m%d-%H%M%S)
RAGFLOW_DIR=/opt/soft/ragflow

echo ""
echo "步骤 1: 备份数据到 $BACKUP_DIR"
mkdir -p $BACKUP_DIR

# 备份 MySQL
echo "  - 备份 MySQL..."
MYSQL_CONTAINER=$(docker ps --format "{{.Names}}" | grep -i mysql | head -1)
if [ -n "$MYSQL_CONTAINER" ]; then
    MYSQL_PASS=""
    if [ -f "$RAGFLOW_DIR/docker/.env" ]; then
        MYSQL_PASS=$(grep -E "^MYSQL_PASSWORD=" $RAGFLOW_DIR/docker/.env | cut -d= -f2)
    fi
    
    if [ -n "$MYSQL_PASS" ]; then
        docker exec $MYSQL_CONTAINER mysqldump -u root -p'$MYSQL_PASS' ragflow > $BACKUP_DIR/mysql-backup.sql 2>/dev/null && echo "  MySQL 备份完成" || echo "  警告: MySQL 备份失败"
    else
        docker exec $MYSQL_CONTAINER mysqldump -u root ragflow > $BACKUP_DIR/mysql-backup.sql 2>/dev/null && echo "  MySQL 备份完成" || echo "  警告: MySQL 备份失败"
    fi
else
    echo "  警告: 未找到 MySQL 容器"
fi

# 备份 Volumes
echo "  - 备份 Volumes..."
for volume in $(docker volume ls --format "{{.Name}}" | grep "^ragflow_"); do
    echo "    备份 $volume..."
    docker run --rm -v $volume:/data -v $BACKUP_DIR:/backup alpine \
        tar czf /backup/${volume}-backup.tar.gz -C /data . 2>/dev/null || echo "    跳过 $volume"
done

echo "v0.24.0" > $BACKUP_DIR/version.txt
echo "备份完成! 位置: $BACKUP_DIR"
ls -lh $BACKUP_DIR

echo ""
echo "步骤 2: 停止服务"
cd $RAGFLOW_DIR/docker
docker-compose down

echo ""
echo "步骤 3: 备份旧代码"
if [ -d "/opt/soft/ragflow-old-v0.24.0" ]; then
    rm -rf /opt/soft/ragflow-old-v0.24.0
fi
mv $RAGFLOW_DIR /opt/soft/ragflow-old-v0.24.0

echo ""
echo "步骤 4: 使用国内镜像拉取新版本"
echo "  尝试使用 ghproxy 镜像..."
if git clone https://ghproxy.com/https://github.com/infiniflow/ragflow.git $RAGFLOW_DIR; then
    echo "  使用 ghproxy 成功"
else
    echo "  ghproxy 失败，尝试其他镜像..."
    if git clone https://mirror.ghproxy.com/https://github.com/infiniflow/ragflow.git $RAGFLOW_DIR; then
        echo "  使用 mirror.ghproxy 成功"
    else
        echo "  镜像失败，尝试直接克隆..."
        git clone https://github.com/infiniflow/ragflow.git $RAGFLOW_DIR
    fi
fi

cd $RAGFLOW_DIR

# 获取最新版本
LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "main")
echo "切换到版本: $LATEST_TAG"
git checkout $LATEST_TAG

echo ""
echo "步骤 5: 应用 Logo 修改"
cd web

# 修改配置文件
cat > src/conf.json << 'EOF'
{
  "appName": "元析立方"
}
EOF

# 修改标题
sed -i 's/<title>.*<\/title>/<title>元析立方<\/title>/g' index.html

# 修改 locales
sed -i "s/title: 'A leading RAG engine for LLM context'/title: '元析立方 MetaCube'/g" src/locales/en.ts
sed -i "s/welcome: 'Welcome to'/welcome: '欢迎来到'/g" src/locales/en.ts
sed -i "s/title: 'RAGFlow'/title: '元析立方'/g" src/locales/en.ts
sed -i "s/title: 'A leading RAG engine for LLM context'/title: '元析立方 MetaCube'/g" src/locales/zh.ts

# 修改页面
sed -i "s/{t('header.welcome')}/欢迎来到/g" src/pages/home/banner.tsx
sed -i "s/RAGFlow/元析立方/g" src/pages/home/banner.tsx
sed -i "s/RAGFlow/元析立方/g" src/pages/login-next/index.tsx
sed -i "s/RAGFlow/元析立方/g" src/pages/next-search/search-view.tsx

# 复制 Logo
if [ -f /opt/soft/ragflow-old-v0.24.0/web/public/logo.svg ]; then
    cp /opt/soft/ragflow-old-v0.24.0/web/public/logo.svg public/logo.svg
    cp /opt/soft/ragflow-old-v0.24.0/web/src/assets/logo-with-text.svg src/assets/logo-with-text.svg
    echo "Logo 文件已复制"
fi

echo "Logo 修改完成"

echo ""
echo "步骤 6: 编译前端"
echo "  - 安装依赖（可能需要几分钟）..."
npm install || { echo "  错误: npm install 失败"; exit 1; }

echo "  - 编译..."
npm run build || { echo "  错误: npm build 失败"; exit 1; }

# 复制到 docker 目录
mkdir -p ../docker/nginx
cp -r dist/* ../docker/nginx/

echo ""
echo "步骤 7: 启动服务"
cd ../docker
docker-compose up -d

echo ""
echo "=========================================="
echo "升级完成!"
echo "=========================================="
echo "备份位置: $BACKUP_DIR"
echo ""
echo "检查服务状态:"
echo "  docker-compose ps"
echo ""
echo "查看日志:"
echo "  docker-compose logs -f ragflow-server"
