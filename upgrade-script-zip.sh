#!/bin/bash
# RAGFlow 升级脚本 - 使用压缩包
# 使用方法: bash upgrade-script-zip.sh <版本号>
# 例如: bash upgrade-script-zip.sh v0.25.0

set -e

# 获取版本号，默认为最新版本
VERSION=${1:-v0.25.0}

echo "=========================================="
echo "RAGFlow 升级脚本 (压缩包版)"
echo "升级版本: $VERSION"
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
echo "步骤 4: 下载并解压新版本"
cd /opt/soft

# 下载压缩包
echo "  下载 $VERSION 版本..."
DOWNLOAD_URL="https://github.com/infiniflow/ragflow/archive/refs/tags/$VERSION.tar.gz"

if wget --timeout=60 -O ragflow-$VERSION.tar.gz "$DOWNLOAD_URL"; then
    echo "  下载成功"
elif wget --timeout=60 -O ragflow-$VERSION.tar.gz "https://ghproxy.com/$DOWNLOAD_URL"; then
    echo "  使用镜像下载成功"
else
    echo "  下载失败，尝试 curl..."
    curl -L -o ragflow-$VERSION.tar.gz "$DOWNLOAD_URL" --max-time 120
fi

# 解压
echo "  解压..."
tar -xzf ragflow-$VERSION.tar.gz
mv ragflow-${VERSION#v} $RAGFLOW_DIR
rm ragflow-$VERSION.tar.gz

cd $RAGFLOW_DIR
echo "新版本已准备好"

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
echo "版本: $VERSION"
echo "备份位置: $BACKUP_DIR"
echo ""
echo "检查服务状态:"
echo "  docker-compose ps"
echo ""
echo "查看日志:"
echo "  docker-compose logs -f ragflow-server"
