#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}Starting server setup...${NC}"

# Обновление списка пакетов и системное обновление
echo -e "${GREEN}Updating package list and upgrading system...${NC}"
sudo apt-get update -y && sudo apt-get upgrade -y

# Установка основных утилит
echo -e "${GREEN}Installing essential packages...${NC}"
sudo apt-get install -y mc net-tools software-properties-common curl pwgen ufw

# Установка Node.js, npm и PM2
echo -e "${GREEN}Installing Node.js, npm, and pm2...${NC}"
curl -fsSL https://deb.nodesource.com/setup_current.x | sudo -E bash -
sudo apt-get install -y nodejs
sudo npm install -g pm2

# Установка Python 3 и pip
echo -e "${GREEN}Installing Python 3 and pip...${NC}"
sudo apt-get install -y python3 python3-pip

# Генерация случайного 5-значного порта для SSH
SSH_PORT=$(shuf -i 50000-80000 -n 1)
echo -e "${YELLOW}Generated random SSH port: $SSH_PORT${NC}"

# Замена строки с портом или добавление новой строки
if sudo grep -q "^Port" /etc/ssh/sshd_config; then
    sudo sed -i "s/^Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config
else
    echo "Port $SSH_PORT" | sudo tee -a /etc/ssh/sshd_config
fi

echo "Changing SSH port in /etc/ssh/sshd_config..."

# Перезапуск SSH службы
echo -e "${GREEN}Restarting SSH service...${NC}"
if sudo systemctl restart sshd; then
    echo -e "${GREEN}SSH service restarted successfully.${NC}"
else
    echo -e "${RED}Failed to restart SSH service.${NC}"
fi

# Брандмауэр (UFW)
echo -e "${GREEN}Configuring UFW firewall...${NC}"
sudo ufw allow $SSH_PORT/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable

# Генерация случайного пароля для root
NEW_PASSWORD=$(pwgen -s 32 1)
echo -e "${YELLOW}Generated random password for root: $NEW_PASSWORD${NC}"

# Установка нового пароля для root
echo -e "${GREEN}Updating root password...${NC}"
echo "root:$NEW_PASSWORD" | sudo chpasswd

# Вывод информации о настройке сервера
echo -e "${RED}-----------------------------------------------${NC}"
echo -e "${GREEN}Server setup complete!${NC}"
echo -e "${BLUE}SSH now running on IP: $(hostname -I | awk '{print $1}') Port: $SSH_PORT${NC}"
echo -e "${YELLOW}Root access credentials:${NC}"
echo -e "${BLUE}  IP Address: $(hostname -I | awk '{print $1}')${NC}"
echo -e "${BLUE}  Port: $SSH_PORT${NC}"
echo -e "${YELLOW}  Root Password: $NEW_PASSWORD${NC}"
echo -e "${RED}-----------------------------------------------${NC}"
