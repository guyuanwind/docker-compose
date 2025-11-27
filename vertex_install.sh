#!/bin/bash

# 定义颜色，让输出更清晰
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 帮助信息
usage() {
    echo -e "用法: $0 -u <用户名> -p <密码> [-o <端口>]"
    echo -e "示例: $0 -u admin -p password123 -o 4000"
    exit 1
}

# 检查是否以 Root 运行
if [ "$(id -u)" != "0" ]; then
   echo -e "${RED}错误: 此脚本必须以 Root 权限运行${NC}"
   exit 1
fi

# 初始化默认变量 (默认端口 4000)
PORT=4000

# 解析命令行参数
# u: 用户名, p: 密码, o: 端口
while getopts "u:p:o:" opt; do
  case ${opt} in
    u ) USERNAME=$OPTARG ;;
    p ) PASSWORD=$OPTARG ;;
    o ) PORT=$OPTARG ;;
    * ) usage ;;
  esac
done

# 验证必填参数
if [[ -z "$USERNAME" ]] || [[ -z "$PASSWORD" ]]; then
    echo -e "${RED}错误: 用户名 (-u) 和密码 (-p) 是必须的。${NC}"
    usage
fi

echo -e "${CYAN}=== 开始安装 Vertex ===${NC}"

# 1. 检查并安装 Docker
echo -e "${GREEN}==> 正在检查 Docker 环境...${NC}"
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}Docker 未安装，正在执行自动安装...${NC}"
    bash <(curl -sL 'https://get.docker.com')
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Docker 安装失败，请检查网络或尝试手动安装。${NC}"
        exit 1
    fi
    
    systemctl start docker
    systemctl enable docker
    echo -e "${GREEN}Docker 安装完成。${NC}"
else
    echo -e "${GREEN}Docker 已安装，跳过安装步骤。${NC}"
fi

# 2. 清理旧容器 (防止冲突)
if [ "$(docker ps -aq -f name=vertex)" ]; then
    echo -e "${YELLOW}检测到同名 vertex 容器，正在删除旧容器...${NC}"
    docker rm -f vertex > /dev/null
fi

# 3. 第一次启动 Vertex (初始化目录)
# 注意：使用 --network host 模式，-p 映射无效，必须通过环境变量 -e PORT 指定程序监听端口
echo -e "${GREEN}==> 正在初次启动 Vertex 以生成配置文件...${NC}"
docker run -d \
  --name vertex \
  --network host \
  -e TZ=Asia/Shanghai \
  -e PORT=$PORT \
  -e HTTPS_ENABLE=false \
  -e REDISPORT=6379 \
  -e PUID=0 \
  -e PGID=0 \
  -v /root/vertex:/vertex \
  --restart always \
  lswl/vertex:stable > /dev/null

if [ $? -ne 0 ]; then
    echo -e "${RED}容器启动失败。${NC}"
    exit 1
fi

# 等待几秒钟让容器生成初始化文件
echo -e "${YELLOW}正在等待初始化 (5秒)...${NC}"
sleep 5

# 4. 配置用户名和密码
echo -e "${GREEN}==> 正在配置账号密码...${NC}"

# 停止容器以写入配置文件
docker stop vertex > /dev/null

# 确保数据目录存在 (防止初始化过慢目录未生成)
mkdir -p /root/vertex/data

# 计算密码的 MD5 值 (Vertex 要求的格式)
MD5_PASS=$(echo -n "$PASSWORD" | md5sum | awk '{print $1}')

# 写入 setting.json
cat << EOF > /root/vertex/data/setting.json
{
  "username": "$USERNAME",
  "password": "$MD5_PASS"
}
EOF

echo -e "${GREEN}配置已写入 (User: $USERNAME)${NC}"

# 5. 重启容器以应用配置
echo -e "${GREEN}==> 正在重启 Vertex 容器...${NC}"
docker start vertex > /dev/null

# 6. 获取公网IP用于展示
PUBLIC_IP=$(curl -s https://ipinfo.io/ip)
if [[ -z "$PUBLIC_IP" ]]; then
    PUBLIC_IP="您的服务器IP"
fi

# 7. 完成输出说明
echo -e "\n"
echo -e "${CYAN}################################################${NC}"
echo -e "${GREEN}          Vertex 安装配置成功！                 ${NC}"
echo -e "${CYAN}################################################${NC}"
echo -e ""
echo -e "  ${YELLOW}访问地址:${NC}   http://${PUBLIC_IP}:${PORT}"
echo -e "  ${YELLOW}用户名:${NC}     ${USERNAME}"
echo -e "  ${YELLOW}密码:${NC}       ${PASSWORD}"
echo -e ""
echo -e "${CYAN}################################################${NC}"
echo -e "如果无法访问，请检查服务器防火墙是否放行端口 ${RED}${PORT}${NC}"
