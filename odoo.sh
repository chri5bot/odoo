#!/bin/bash
################################################################################
# Script for installing Odoo on Ubuntu 16.04, 18.04, 20.04, and 22.04
# Author: Yenthe Van Ginneken
# Updated by: [Your Name]
#-------------------------------------------------------------------------------
# This script will install Odoo on your Ubuntu server. It can install multiple
# Odoo instances on one Ubuntu because of the different xmlrpc_ports.
#-------------------------------------------------------------------------------
################################################################################

# Exit on any error
set -e

OE_USER="odoo"
OE_HOME="/home/$OE_USER"
OE_HOME_EXT="$OE_HOME/${OE_USER}-server"
INSTALL_WKHTMLTOPDF="True"
OE_PORT="8069"
OE_VERSION="16.0"
IS_ENTERPRISE="False"
INSTALL_POSTGRESQL_FOURTEEN="True"
INSTALL_NGINX="False"
OE_SUPERADMIN="admin"
GENERATE_RANDOM_PASSWORD="True"
OE_CONFIG="${OE_USER}-server"
WEBSITE_NAME="_"
LONGPOLLING_PORT="8072"
ENABLE_SSL="True"
ADMIN_EMAIL="odoo@example.com"

#--------------------------------------------------
# Update Server
#--------------------------------------------------
echo -e "\n---- Update Server ----"
sudo apt update
sudo apt upgrade -y

#--------------------------------------------------
# Install Python 3.10
#--------------------------------------------------
echo -e "\n---- Install Python 3.10 ----"
sudo apt install -y python3.10 python3.10-venv python3.10-dev

#--------------------------------------------------
# Install PostgreSQL Server
#--------------------------------------------------
echo -e "\n---- Install PostgreSQL Server ----"
if [ "$INSTALL_POSTGRESQL_FOURTEEN" = "True" ]; then
    echo -e "\n---- Installing PostgreSQL V14 ----"
    sudo apt install -y wget ca-certificates curl gnupg
    wget -qO - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
    echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" | sudo tee /etc/apt/sources.list.d/pgdg.list
    sudo apt update
    sudo apt install -y postgresql-14
else
    echo -e "\n---- Installing the default PostgreSQL version ----"
    sudo apt install -y postgresql
fi

echo -e "\n---- Creating the ODOO PostgreSQL User ----"
sudo -u postgres createuser -s "$OE_USER" || true

#--------------------------------------------------
# Install Dependencies
#--------------------------------------------------
echo -e "\n--- Installing required packages ---"
sudo apt install -y git build-essential wget \
libxslt-dev libzip-dev libldap2-dev libsasl2-dev nodejs npm libjpeg-dev zlib1g-dev \
libfreetype6-dev liblcms2-dev libwebp-dev libharfbuzz-dev libfribidi-dev libxcb1-dev \
libpq-dev

echo -e "\n---- Installing nodeJS NPM and rtlcss ----"
sudo npm install -g rtlcss

# Create symlink for node if necessary
if [ ! -e /usr/bin/node ]; then
    sudo ln -s /usr/bin/nodejs /usr/bin/node
fi

#--------------------------------------------------
# Install Wkhtmltopdf if needed
#--------------------------------------------------
if [ "$INSTALL_WKHTMLTOPDF" = "True" ]; then
    echo -e "\n---- Install wkhtmltopdf ----"
    if [[ $(lsb_release -r -s) == "22.04" ]]; then
        # Ubuntu 22.04 LTS
        sudo apt install -y wkhtmltopdf
    else
        # For older versions of Ubuntu
        if [ "$(getconf LONG_BIT)" == "64" ]; then
            WKHTMLTOX_X64="https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.6-1/wkhtmltox_0.12.6-1.$(lsb_release -cs)_amd64.deb"
            wget $WKHTMLTOX_X64
            sudo apt install -y ./"$(basename $WKHTMLTOX_X64)"
        else
            WKHTMLTOX_X32="https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.6-1/wkhtmltox_0.12.6-1.$(lsb_release -cs)_i386.deb"
            wget $WKHTMLTOX_X32
            sudo apt install -y ./"$(basename $WKHTMLTOX_X32)"
        fi
    fi
else
    echo "Wkhtmltopdf isn't installed due to the choice of the user!"
fi

echo -e "\n---- Create ODOO system user ----"
sudo adduser --system --quiet --shell=/bin/bash --home="$OE_HOME" --gecos 'ODOO' --group "$OE_USER"

echo -e "\n---- Create Log directory ----"
sudo mkdir -p /var/log/"$OE_USER"
sudo chown "$OE_USER":"$OE_USER" /var/log/"$OE_USER"

#--------------------------------------------------
# Install ODOO
#--------------------------------------------------
echo -e "\n==== Installing ODOO Server ===="
sudo -u "$OE_USER" git clone --depth 1 --branch "$OE_VERSION" https://github.com/odoo/odoo "$OE_HOME_EXT/"

# Create virtual environment with Python 3.10
echo -e "\n---- Create virtual environment ----"
sudo -u "$OE_USER" python3.10 -m venv "$OE_HOME/venv"

echo -e "\n---- Install python packages/requirements ----"
sudo -u "$OE_USER" "$OE_HOME/venv/bin/pip" install --upgrade pip
sudo -u "$OE_USER" "$OE_HOME/venv/bin/pip" install wheel
sudo -u "$OE_USER" "$OE_HOME/venv/bin/pip" install -r "$OE_HOME_EXT/requirements.txt"

if [ "$IS_ENTERPRISE" = "True" ]; then
    # Odoo Enterprise install!
    sudo -H "$OE_HOME/venv/bin/pip" install psycopg2-binary pdfminer.six num2words ofxparse dbfread ebaysdk firebase_admin pyOpenSSL
    sudo npm install -g less less-plugin-clean-css

    sudo -u "$OE_USER" mkdir -p "$OE_HOME/enterprise/addons"

    echo "Please enter your GitHub credentials to clone the Odoo Enterprise repository:"
    sudo -u "$OE_USER" git clone --depth 1 --branch "$OE_VERSION" https://github.com/odoo/enterprise "$OE_HOME/enterprise/addons" || {
        echo "Failed to clone Odoo Enterprise repository. Exiting."
        exit 1
    }

    echo -e "\n---- Added Enterprise code under $OE_HOME/enterprise/addons ----"
fi

echo -e "\n---- Create custom module directory ----"
sudo -u "$OE_USER" mkdir -p "$OE_HOME/custom/addons"

echo -e "\n---- Setting permissions on home folder ----"
sudo chown -R "$OE_USER":"$OE_USER" "$OE_HOME/"

echo -e "* Creating server config file"
if [ "$GENERATE_RANDOM_PASSWORD" = "True" ]; then
    echo -e "* Generating random admin password"
    OE_SUPERADMIN=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c16)
fi

sudo touch /etc/"${OE_CONFIG}".conf
sudo chown "$OE_USER":"$OE_USER" /etc/"${OE_CONFIG}".conf
sudo chmod 640 /etc/"${OE_CONFIG}".conf

cat <<EOF | sudo tee /etc/"${OE_CONFIG}".conf
[options]
; This is the password that allows database operations:
admin_passwd = ${OE_SUPERADMIN}
http_port = ${OE_PORT}
logfile = /var/log/${OE_USER}/${OE_CONFIG}.log
EOF

if [ "$IS_ENTERPRISE" = "True" ]; then
    echo "addons_path=${OE_HOME}/enterprise/addons,${OE_HOME_EXT}/addons" | sudo tee -a /etc/"${OE_CONFIG}".conf
else
    echo "addons_path=${OE_HOME_EXT}/addons,${OE_HOME}/custom/addons" | sudo tee -a /etc/"${OE_CONFIG}".conf
fi

#--------------------------------------------------
# Create systemd unit file
#--------------------------------------------------
echo -e "* Creating systemd unit file"
cat <<EOF | sudo tee /etc/systemd/system/"$OE_CONFIG".service
[Unit]
Description=Odoo
Requires=postgresql.service
After=network.target postgresql.service

[Service]
Type=simple
User=${OE_USER}
ExecStart=${OE_HOME}/venv/bin/python ${OE_HOME_EXT}/odoo-bin --config=/etc/${OE_CONFIG}.conf
WorkingDirectory=${OE_HOME_EXT}/
StandardOutput=journal+console

[Install]
WantedBy=multi-user.target
EOF

echo -e "* Starting Odoo Service"
sudo systemctl daemon-reload
sudo systemctl enable "$OE_CONFIG"
sudo systemctl start "$OE_CONFIG"

#--------------------------------------------------
# Install Nginx if needed
#--------------------------------------------------
if [ "$INSTALL_NGINX" = "True" ]; then
    echo -e "\n---- Installing and setting up Nginx ----"
    sudo apt install -y nginx
    cat <<EOF | sudo tee /etc/nginx/sites-available/"$WEBSITE_NAME"
server {
    listen 80;
    server_name $WEBSITE_NAME;

    proxy_read_timeout 720s;
    proxy_connect_timeout 720s;
    proxy_send_timeout 720s;

    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Real-IP \$remote_addr;
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-XSS-Protection "1; mode=block";
    proxy_set_header X-Client-IP \$remote_addr;
    proxy_set_header HTTP_X_FORWARDED_HOST \$remote_addr;

    access_log /var/log/nginx/${OE_USER}-access.log;
    error_log /var/log/nginx/${OE_USER}-error.log;

    proxy_buffers 16 64k;
    proxy_buffer_size 128k;

    client_max_body_size 0;

    location / {
        proxy_pass http://127.0.0.1:${OE_PORT};
        proxy_redirect off;
    }

    location /longpolling {
        proxy_pass http://127.0.0.1:${LONGPOLLING_PORT};
    }

    location ~* .(js|css|png|jpg|jpeg|gif|ico)$ {
        expires 2d;
        proxy_pass http://127.0.0.1:${OE_PORT};
        add_header Cache-Control "public, no-transform";
    }

    gzip on;
    gzip_min_length 1100;
    gzip_buffers 4 32k;
    gzip_types text/css text/plain application/javascript application/json image/jpeg image/png;
    gzip_vary on;
}
EOF

    sudo ln -s /etc/nginx/sites-available/"$WEBSITE_NAME" /etc/nginx/sites-enabled/
    sudo rm /etc/nginx/sites-enabled/default
    sudo systemctl reload nginx
    echo "proxy_mode = True" | sudo tee -a /etc/"${OE_CONFIG}".conf
    echo "Done! The Nginx server is up and running. Configuration can be found at /etc/nginx/sites-available/$WEBSITE_NAME"
else
    echo "Nginx isn't installed due to choice of the user!"
fi

#--------------------------------------------------
# Enable SSL with Certbot
#--------------------------------------------------
if [ "$INSTALL_NGINX" = "True" ] && [ "$ENABLE_SSL" = "True" ] && [ "$ADMIN_EMAIL" != "odoo@example.com" ] && [ "$WEBSITE_NAME" != "_" ]; then
    sudo apt update -y
    sudo apt install -y snapd
    sudo snap install core; sudo snap refresh core
    sudo snap install --classic certbot
    sudo ln -s /snap/bin/certbot /usr/bin/certbot
    sudo certbot --nginx -d "$WEBSITE_NAME" --noninteractive --agree-tos --email "$ADMIN_EMAIL" --redirect
    sudo systemctl reload nginx
    echo "SSL/HTTPS is enabled!"
else
    echo "SSL/HTTPS isn't enabled due to choice of the user or because of a misconfiguration!"
    if [ "$ADMIN_EMAIL" = "odoo@example.com" ]; then 
        echo "Certbot requires a valid email address. Please update the ADMIN_EMAIL variable."
    fi
    if [ "$WEBSITE_NAME" = "_" ]; then
        echo "Website name is set as '_'. Cannot obtain SSL Certificate for '_'. Please set the WEBSITE_NAME variable to your domain name."
    fi
fi

echo -e "* Starting Odoo Service"
sudo systemctl restart "$OE_CONFIG"
echo "-----------------------------------------------------------"
echo "Done! The Odoo server is up and running. Specifications:"
echo "Port: $OE_PORT"
echo "User service: $OE_USER"
echo "Configuration file location: /etc/${OE_CONFIG}.conf"
echo "Logfile location: /var/log/$OE_USER"
echo "PostgreSQL User: $OE_USER"
echo "Code location: $OE_HOME_EXT/"
echo "Addons folder: $OE_HOME_EXT/addons/"
echo "Password superadmin (database): $OE_SUPERADMIN"
echo "Start Odoo service: sudo systemctl start $OE_CONFIG"
echo "Stop Odoo service: sudo systemctl stop $OE_CONFIG"
echo "Restart Odoo service: sudo systemctl restart $OE_CONFIG"
if [ "$INSTALL_NGINX" = "True" ]; then
    echo "Nginx configuration file: /etc/nginx/sites-available/$WEBSITE_NAME"
fi
echo "-----------------------------------------------------------"
