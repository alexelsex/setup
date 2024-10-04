#!/bin/bash

# Цвета для сообщений
GREEN='\033[0;32m'
NC='\033[0m'

# Получение списка доступных версий Bitcoin Core
echo -e "${GREEN}Получение списка доступных версий Bitcoin Core...${NC}"
AVAILABLE_VERSIONS=$(curl -s https://api.github.com/repos/bitcoin/bitcoin/tags | grep '"name":' | awk '{print $2}' | sed 's/[",]//g' | head -n 10)

echo -e "${GREEN}Доступные версии:${NC}"
echo "$AVAILABLE_VERSIONS"

# Запрос версии для установки
echo -e "${GREEN}Введите версию Bitcoin Core для установки из списка выше (например, v26.2).${NC}"
read -p "Версия: " VERSION

# Если версия не указана, используем последнюю
if [ -z "$VERSION" ]; then
    VERSION=$(echo "$AVAILABLE_VERSIONS" | head -n 1)
fi
echo -e "${GREEN}Выбрана версия Bitcoin Core: $VERSION${NC}"

# Запрос пути для хранения данных
read -p "Введите путь для хранения данных (по умолчанию: ~/.bitcoin): " DATA_DIR

# Использование пути по умолчанию, если не указан
if [ -z "$DATA_DIR" ]; then
    DATA_DIR="$HOME/.bitcoin"
fi
echo -e "${GREEN}Путь для данных установлен: $DATA_DIR${NC}"

# Установка зависимостей
echo -e "${GREEN}Установка зависимостей...${NC}"
sudo apt update
sudo apt install -y build-essential libtool autotools-dev automake pkg-config \
    libssl-dev libevent-dev bsdmainutils python3 libboost-all-dev \
    libminiupnpc-dev libzmq3-dev libprotobuf-dev protobuf-compiler \
    libqrencode-dev libsecp256k1-dev git

# Клонирование и установка Bitcoin Core
echo -e "${GREEN}Клонирование Bitcoin Core версии $VERSION...${NC}"
git clone --branch "$VERSION" https://github.com/bitcoin/bitcoin.git
cd bitcoin
./autogen.sh
./configure --disable-wallet --without-gui
make -j$(nproc)
sudo make install
cd ..

# Создание файла службы systemd для Bitcoin
echo -e "${GREEN}Создание службы systemd для Bitcoin Core...${NC}"
sudo tee /etc/systemd/system/bitcoind.service > /dev/null <<EOL
[Unit]
Description=Bitcoin Daemon
After=network.target

[Service]
ExecStart=/usr/local/bin/bitcoind -datadir=$DATA_DIR
ExecStop=/usr/local/bin/bitcoin-cli stop
Restart=always
User=$(whoami)

[Install]
WantedBy=multi-user.target
EOL

# Настройка автозапуска и запуск службы
echo -e "${GREEN}Настройка автозапуска и запуск службы...${NC}"
sudo systemctl daemon-reload
sudo systemctl enable bitcoind
sudo systemctl start bitcoind

# Проверка статуса службы
echo -e "${GREEN}Проверка статуса службы Bitcoin Core...${NC}"
sudo systemctl status bitcoind

echo -e "${GREEN}Установка и запуск Bitcoin Core завершены!${NC}"
