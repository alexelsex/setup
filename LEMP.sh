#!/bin/bash

echo "===================="
echo "Шаг 1: Обновление системы и установка зависимостей"
echo "===================="

# Обновляем систему
sudo apt update && sudo apt upgrade -y

# Устанавливаем необходимые зависимости
sudo apt-get install -y software-properties-common build-essential libpcre3 libpcre3-dev libssl-dev zlib1g zlib1g-dev pwgen
sudo apt install -y libmaxminddb-dev libmaxminddb0 mmdb-bin
sudo apt install -y libgoogle-perftools-dev

echo "===================="
echo "Шаг 2: Установка MariaDB"
echo "===================="

# Получаем список доступных версий MariaDB
echo "Получение списка доступных версий MariaDB..."
AVAILABLE_VERSIONS=$(wget -qO- https://downloads.mariadb.org/ | grep -oP '10\.[0-9]+\.[0-9]+' | sort -r | uniq)

# Отображаем список версий и просим пользователя выбрать
echo "Доступные версии MariaDB:"
echo "$AVAILABLE_VERSIONS"
echo
read -p "Введите версию MariaDB для установки (например, 10.6.19): " SELECTED_VERSION

# Проверяем, что версия введена корректно
if echo "$AVAILABLE_VERSIONS" | grep -q "^$SELECTED_VERSION$"; then
    echo "Вы выбрали версию: $SELECTED_VERSION"
else
    echo "Ошибка: Введена некорректная версия MariaDB!"
    exit 1
fi

# Установка MariaDB с выбранной версией
curl -fsSL https://mariadb.org/mariadb_release_signing_key.asc | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/mariadb.gpg > /dev/null
sudo add-apt-repository -y "deb [arch=amd64,arm64,ppc64el] https://mariadb.mirror.liquidtelecom.com/repo/$SELECTED_VERSION/ubuntu focal main"
sudo apt update
sudo apt-get install -y aptitude

# Установка MariaDB через aptitude
sudo aptitude install mariadb-server mariadb-client

# Настройка безопасности MariaDB
ROOT_PASSWORD=$(pwgen -s 32 1)
echo "Root password: $ROOT_PASSWORD"
sudo mysql -u root -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('$ROOT_PASSWORD');"
sudo mysql -e "DELETE FROM mysql.user WHERE User='';"
sudo mysql -e "DROP DATABASE IF EXISTS test;"
sudo mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
sudo mysql -e "FLUSH PRIVILEGES;"

# Автозагрузка MariaDB при старте системы
sudo systemctl enable mariadb

echo "===================="
echo "Шаг 3: Установка и сборка OpenResty с модулем testcookie"
echo "===================="

# Получаем список доступных версий OpenResty
echo "Получение latest -v OpenResty..."
LATEST_VERSION=$(wget -qO- https://openresty.org/en/download.html | grep -oP 'openresty-[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?\.tar\.gz' | head -n 1)
# Проверяем, найдена ли последняя версия
if [ -z "$LATEST_VERSION" ]; then
    echo "Ошибка: Не удалось получить последнюю версию OpenResty."
    exit 1
fi

# Извлекаем номер версии из имени файла
SELECTED_VERSION=$(echo $LATEST_VERSION | sed 's/openresty-//;s/\.tar\.gz//')

echo "Последняя стабильная версия OpenResty: $SELECTED_VERSION"

# Скачивание последней версии OpenResty
wget https://openresty.org/download/$LATEST_VERSION
if [ $? -ne 0 ]; then
    echo "Ошибка: Версия OpenResty $LATEST_VERSION не найдена на сервере."
    exit 1
fi

tar -xzvf openresty-$SELECTED_VERSION.tar.gz

# Скачивание модуля testcookie
git clone https://github.com/kyprizel/testcookie-nginx-module.git

# Клонируем geoip2
git clone https://github.com/leev/ngx_http_geoip2_module.git /opt/ngx_http_geoip2_module

# Сборка и установка OpenResty с модулем testcookie
cd openresty-$SELECTED_VERSION
./configure --prefix=/usr/nginx --add-module=/opt/testcookie-nginx-module --add-module=/opt/ngx_http_geoip2_module --with-pcre-jit --with-http_ssl_module --with-http_stub_status_module --with-http_v2_module --with-http_sub_module --with-http_realip_module --with-stream --with-stream_realip_module --with-stream_ssl_module --with-google_perftools_module --without-mail_pop3_module --without-mail_smtp_module --without-mail_imap_module --without-http_uwsgi_module --without-http_scgi_module --with-stream_ssl_preread_module
make
sudo make install

# Проверка версии OpenResty
sudo /usr/nginx/nginx/sbin/nginx -V

# Создаем конфиг директорию
sudo mkdir -p /etc/nginx
sudo cp -r /usr/nginx/nginx/conf/* /etc/nginx/

# Создаем systemd-сервис
sudo bash -c 'cat <<EOF > /etc/systemd/system/openresty.service
[Unit]
Description=OpenResty
After=network.target

[Service]
Type=forking
ExecStart=/usr/nginx/nginx/sbin/nginx -c /etc/nginx/nginx.conf
ExecReload=/usr/nginx/nginx/sbin/nginx -s reload
ExecStop=/usr/nginx/nginx/sbin/nginx -s quit
PIDFile=/usr/nginx/nginx/logs/nginx.pid
Restart=always

[Install]
WantedBy=multi-user.target
EOF'

# Активируем и запускаем
sudo systemctl daemon-reload
sudo systemctl enable openresty
sudo systemctl start openresty

# Создание папок для виртуальных хостов
sudo mkdir -p /etc/nginx/sites-available
sudo mkdir -p /etc/nginx/sites-enabled

echo "===================="
echo "Шаг 4: Настройка оптимизации Nginx"
echo "===================="

# Определение количества процессорных ядер и максимального числа файловых дескрипторов
WORKER_PROCESSES=$(nproc)
WORKER_CONNECTIONS=$(ulimit -n)

# Добавляем настройки в основной конфигурационный файл Nginx (/etc/nginx/nginx.conf)
sudo bash -c "cat > /etc/nginx/nginx.conf" <<EOF
user www-data;
worker_processes  $WORKER_PROCESSES;

events {
    worker_connections  $WORKER_CONNECTIONS;
}

http {
    include       mime.types;
    default_type  application/octet-stream;
    server_names_hash_bucket_size 128;
    sendfile        on;
    keepalive_timeout  65;

    server {
        listen       80;
        server_name  localhost;

        location / {
            root   html;
            index  index.html index.htm;
        }

        error_page   500 502 503 504  /50x.html;
        location = /50x.html {
            root   html;
        }
    }

    include /etc/nginx/sites-enabled/*;
}
EOF

# Перезапуск OpenResty
sudo systemctl restart openresty
if [ $? -eq 0 ]; then
    echo "OpenResty успешно установлен и запущен"
else
    echo "Ошибка при установке и запуске OpenResty"
    exit 1
fi

echo "===================="
echo "Шаг 5: Установка PHP 8.2 и необходимых модулей"
echo "===================="

# Установка PHP и PHP-FPM
sudo add-apt-repository ppa:ondrej/php
sudo apt update

# Устанавливаем PHP 8.2 и необходимые модули
sudo apt-get install -y php8.2-fpm php8.2-curl php8.2-mbstring php8.2-mysql php8.2-mcrypt php8.2-memcache php8.2-memcached php8.2-bcmath php8.2-xml php8.2-common php8.2-gd php8.2-zip php8.2-cli

echo "===================="
echo "Шаг 6: Установка и настройка phpMyAdmin"
echo "===================="

# Скачивание phpMyAdmin Latest Stable
cd /opt
DATA="$(wget https://www.phpmyadmin.net/home_page/version.txt -q -O-)"
URL="$(echo $DATA | cut -d ' ' -f 3)"
VERSION="$(echo $DATA | cut -d ' ' -f 1)"
wget https://files.phpmyadmin.net/phpMyAdmin/${VERSION}/phpMyAdmin-${VERSION}-all-languages.tar.gz
tar xvf phpMyAdmin-${VERSION}-all-languages.tar.gz

# Перемещаем phpMyAdmin в нужную директорию
sudo mv phpMyAdmin-*/ /usr/share/phpmyadmin
sudo mkdir -p /var/lib/phpmyadmin/tmp
sudo chown -R www-data:www-data /var/lib/phpmyadmin
sudo mkdir -p /usr/share/phpmyadmin/tmp
sudo chown -R www-data:www-data /usr/share/phpmyadmin/tmp

# Настройка phpMyAdmin
sudo cp /usr/share/phpmyadmin/config.sample.inc.php /usr/share/phpmyadmin/config.inc.php

# Генерация Blowfish-секрета для phpMyAdmin
BLOWFISH_SECRET=$(pwgen -s 32 1)
sudo sed -i "s/\$cfg\['blowfish_secret'\] = '';/\$cfg['blowfish_secret'] = '$BLOWFISH_SECRET';/" /usr/share/phpmyadmin/config.inc.php

echo "Blowfish secret установлен: $BLOWFISH_SECRET"

echo "===================="
echo "Шаг 7: Создание конфигурации Nginx для phpMyAdmin"
echo "===================="

# Устанавливаем переменную для URL, генерируем случайный поддомен с помощью pwgen
SUBDOMAIN=$(pwgen -s 38 1)
DOMAIN="$SUBDOMAIN.porn"

# Путь к конфигурации Nginx
NGINX_CONF_PATH="/etc/nginx/sites-available/phpmyadmin"

# Создаем конфигурационный файл Nginx для phpMyAdmin
sudo bash -c "cat > $NGINX_CONF_PATH" <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    root /usr/share/phpmyadmin;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php\$ {
        include fastcgi_params;
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock; 
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

# Создаем симлинк для phpMyAdmin
sudo ln -s /etc/nginx/sites-available/phpmyadmin /etc/nginx/sites-enabled/

# Перезагрузка OpenResty для применения новой конфигурации
sudo systemctl restart openresty
if [ $? -eq 0 ]; then
    echo "OpenResty успешно перезапущен с конфигурацией для phpMyAdmin"
    echo "phpMyAdmin доступен по адресу: http://$DOMAIN"
else
    echo "Ошибка при перезапуске OpenResty после добавления phpMyAdmin"
    exit 1
fi

echo "===================="
echo "Шаг 8: Генерация SSL-сертификата и настройка default хоста"
echo "===================="

# Генерация SSL-сертификата и ключа для default хоста
sudo mkdir -p /etc/nginx/ssl

# Генерация приватного ключа
sudo openssl genrsa -out /etc/nginx/ssl/default.key 2048

# Генерация самоподписанного сертификата
sudo openssl req -new -x509 -key /etc/nginx/ssl/default.key -out /etc/nginx/ssl/default.crt -days 3650 -subj "/CN=default"

# Генерация Diffie-Hellman параметров
echo "Генерация DH параметров, это может занять время..."
sudo openssl dhparam -out /etc/nginx/ssl/dhparams.pem 2048

# Создаем конфигурацию default-хоста Nginx
DEFAULT_CONF_PATH="/etc/nginx/sites-available/default"
sudo bash -c "cat > $DEFAULT_CONF_PATH" <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;

    server_name _;

    ssl_certificate /etc/nginx/ssl/default.crt;
    ssl_certificate_key /etc/nginx/ssl/default.key;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_dhparam /etc/nginx/ssl/dhparams.pem;
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
    ssl_ciphers 'ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA:ECDHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-RSA-AES256-SHA256:DHE-RSA-AES256-SHA:ECDHE-ECDSA-DES-CBC3-SHA:ECDHE-RSA-DES-CBC3-SHA:EDH-RSA-DES-CBC3-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:DES-CBC3-SHA:!DSS';
    ssl_prefer_server_ciphers on;
    ssl_stapling on;

    location / {
        return 403;
    }

    error_page 404 /404.html;
    location = /404.html {
        internal;
    }

    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        internal;
    }
}
EOF

# Создаем симлинк для default хоста
sudo ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/

# Перезагрузка OpenResty
sudo systemctl restart openresty
if [ $? -eq 0 ]; then
    echo "OpenResty успешно перезапущен с SSL"
else
    echo "Ошибка при перезагрузке OpenResty с SSL"
    exit 1
fi

########################################
# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}====================${NC}"
echo -e "${YELLOW}Установка завершена!${NC}"
echo -e "${YELLOW}====================${NC}"
echo -e "\n${GREEN}MYSQL root password: ${RED}$ROOT_PASSWORD${NC}"
echo -e "${GREEN}phpMyAdmin доступен по адресу: ${RED}http://$DOMAIN${NC}"
