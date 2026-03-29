#!/bin/bash
# RAGFlow 升级脚本 - 在服务器上执行
# 使用方法: bash upgrade-script.sh

set -e

echo "=========================================="
echo "RAGFlow 升级脚本"
echo "=========================================="

# 配置
BACKUP_DIR=~/ragflow-backup-$(date +%Y%m%d-%H%M%S)
RAGFLOW_DIR=~/ragflow  # 请根据实际情况修改

echo ""
echo "步骤 1: 备份数据到 $BACKUP_DIR"
mkdir -p $BACKUP_DIR

# 备份 MySQL
echo "  - 备份 MySQL..."
MYSQL_CONTAINER=$(docker ps --format "{{.Names}}" | grep -i mysql | head -1)
if [ -n "$MYSQL_CONTAINER" ]; then
    read -s -p "请输入 MySQL root 密码: " MYSQL_PASS
    echo ""
    docker exec $MYSQL_CONTAINER mysqldump -u root -p$MYSQL_PASS ragflow > $BACKUP_DIR/mysql-backup.sql
    echo "  MySQL 备份完成"
else
    echo "  警告: 未找到 MySQL 容器"
fi

# 备份 Volumes
echo "  - 备份 Volumes..."
for volume in $(docker volume ls --format "{{.Name}}" | grep -E "ragflow|esdata|minio|redis"); do
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
docker compose down

echo ""
echo "步骤 3: 备份旧代码"
mv $RAGFLOW_DIR ~/ragflow-old-v0.24.0

echo ""
echo "步骤 4: 拉取新版本"
git clone https://github.com/infiniflow/ragflow.git $RAGFLOW_DIR
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

# 复制 Logo（从备份的旧代码中复制）
if [ -f ~/ragflow-old-v0.24.0/web/public/logo.svg ]; then
    cp ~/ragflow-old-v0.24.0/web/public/logo.svg public/logo.svg
    cp ~/ragflow-old-v0.24.0/web/src/assets/logo-with-text.svg src/assets/logo-with-text.svg
    echo "Logo 文件已复制"
fi

echo "Logo 修改完成"

echo ""
echo "步骤 6: 编译前端"
npm install
npm run build

# 复制到 docker 目录
mkdir -p ../docker/nginx
cp -r dist/* ../docker/nginx/

echo ""
echo "步骤 7: 启动服务"
cd ../docker
docker compose up -d

echo ""
echo "=========================================="
echo "升级完成!"
echo "=========================================="
echo "备份位置: $BACKUP_DIR"
echo ""
echo "检查服务状态:"
echo "  docker compose ps"
echo ""
echo "查看日志:"
echo "  docker logs -f ragflow-server"
