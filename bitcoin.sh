#!/bin/bash

# Цвета для сообщений
GREEN='\033[0;32m'
NC='\033[0m'

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
echo -e "${GREEN}Клонирование Bitcoin Core...${NC}"
git clone --branch v26.2 https://github.com/bitcoin/bitcoin.git
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
