#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Запрос имени сервера
echo -e "${BLUE}Please enter the desired server name (hostname):${NC}"
read -p "Hostname: " SERVER_NAME

# Проверка на пустой ввод
if [ -z "$SERVER_NAME" ]; then
    echo -e "${RED}Hostname cannot be empty. Please try again.${NC}"
    exit 1
fi

# Установка имени и перезапуск службы
sudo hostnamectl set-hostname "$SERVER_NAME"
echo -e "${GREEN}Hostname set to: $SERVER_NAME${NC}"
sudo systemctl restart systemd-hostnamed

echo -e "${BLUE}Starting server setup...${NC}"

# Обновление списка пакетов и системное обновление
echo -e "${GREEN}Updating package list and upgrading system...${NC}"
sudo apt-get update -y && sudo apt-get upgrade -y

# Установка основных утилит
echo -e "${GREEN}Installing essential packages...${NC}"
sudo apt-get install -y mc net-tools software-properties-common pwgen ufw glances python3 python3-pip bpytop

# Установка Node.js, npm и PM2
echo -e "${GREEN}Installing Node.js, npm, and pm2...${NC}"
curl -fsSL https://deb.nodesource.com/setup_current.x | sudo -E bash -
sudo apt-get install -y nodejs
sudo npm install -g pm2

# Генерация случайного 5-значного порта для SSH
SSH_PORT=$(shuf -i 20000-65535 -n 1)
echo -e "${YELLOW}Generated random SSH port: $SSH_PORT${NC}"

# Замена строки с портом или добавление новой строки
if sudo grep -q "^#\?Port" /etc/ssh/sshd_config; then
    sudo sed -i "s/^#\?Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config
else
    echo "Port $SSH_PORT" | sudo tee -a /etc/ssh/sshd_config
fi

echo "Changing SSH port in /etc/ssh/sshd_config..."

# Перезапуск SSH службы
echo -e "${GREEN}Restarting SSH service...${NC}"

sudo systemctl daemon-reload

# Определяем, какая служба активна
SSH_SERVICE=$(systemctl list-units --type=service --all | grep -E 'ssh\.service|sshd\.service' | awk '{print $1}' | head -n 1)

# Проверяем, нашлась ли служба и перезапускаем её
if [ -n "$SSH_SERVICE" ]; then
    if sudo systemctl restart "$SSH_SERVICE"; then
        echo -e "${GREEN}SSH service restarted successfully.${NC}"
    else
        echo -e "${RED}Failed to restart SSH service.${NC}"
    fi
else
    echo -e "${RED}No SSH service found.${NC}"
fi

# Брандмауэр (UFW)
echo -e "${GREEN}Configuring UFW firewall...${NC}"
sudo ufw allow $SSH_PORT/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable

# Генерация случайного пароля для root
NEW_PASSWORD=$(pwgen -s 32 1)
#echo -e "${YELLOW}Generated random password for root: $NEW_PASSWORD${NC}"

# Установка нового пароля для root
echo -e "${GREEN}Updating root password...${NC}"
echo "root:$NEW_PASSWORD" | sudo chpasswd
echo -e "\n"
echo -e "${GREEN}Server setup complete!${NC}"
echo -e "\n"
# Вывод информации о настройке сервера
echo -e "${YELLOW}-----------------------------------------------${NC}"
#echo -e "${RED}SSH now running on IP: $(hostname -I | awk '{print $1}') Port: $SSH_PORT${NC}"
echo -e "${YELLOW}$SERVER_NAME credentials:${NC}"
echo -e "${GREEN}- IP Address: $(hostname -I | awk '{print $1}')${NC}"
echo -e "${GREEN}- Port: $SSH_PORT${NC}"
echo -e "${GREEN}- Root Password: $NEW_PASSWORD${NC}"
echo -e "${YELLOW}-----------------------------------------------${NC}"
echo -e "\n"
