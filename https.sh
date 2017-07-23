#!/bin/bash

clear
WEBROOT=$1
DOMAIN=$2
NGINX_ROOT=$3
NGINX_VH_WELL_KNOWN="well-known"
WEBROOT_WELL_KNOWN_DIR="$WEBROOT/.well-known"
NGINX_SITES_AVAILABLE="$NGINX_ROOT/sites-available"
NGINX_SITES_ENABLED="$NGINX_ROOT/sites-enabled"

install_certbot() {
  echo "### Certbot not found, installing"
  echo "### Adding repo"
  sudo add-apt-repository ppa:certbot/certbot
  echo "### Updating list"
  sudo apt-get update
  echo "### Installing certbot"
  sudo apt-get install certbot
  setting_webroot
}

setting_webroot() {
  echo "### Using certbot webroot plugin"
  if [[ ! -d $WEBROOT_WELL_KNOWN_DIR ]]; then
    echo "### Creating $WEBROOT_WELL_KNOWN_DIR directory"
    sudo mkdir -p $WEBROOT_WELL_KNOWN_DIR
  else
    echo "### $WEBROOT_WELL_KNOWN_DIR already exists, skipping"
  fi
}

create_nginx_vh_well_known() {
  echo "### Creating NGINX Vhost for well-known"
  sudo tee "$NGINX_ROOT/sites-available/well-known" > /dev/null << EOF
  server {
    location ~ /.well-known {
      allow all;
    }
  }
EOF
}

create_nginx_vh_domain() {
  echo "### Creating nginx domain vhost"
  sudo tee "$NGINX_ROOT/sites-available/$DOMAIN" > /dev/null << EOF
  server {
    listen 80 default_server;
    listen [::]:80 default_server;
    listen 443 ssl http2 default_server;
    listen [::]:443 ssl http2 default_server;

    server_name $DOMAIN www.$DOMAIN;
    include snippets/ssl-$DOMAIN.conf;
    include snippets/ssl-dh-$DOMAIN.conf;

    root $WEBROOT

    location / {
      try_files \$uri \$uri/index.html;
    }
  }
EOF
}

restart_nginx() {
  echo "### Restarting nginx"
  sudo nginx -t
  sudo service nginx stop
  sudo service nginx start
}

create_certificates() {
  echo "### Creating letsencrypt certificates"
  sudo certbot certonly --webroot --webroot-path=$WEBROOT -d $DOMAIN
}

create_diffie_hellman() {
  echo "### Generating Diffie Hellman group"
  sudo openssl dhparam -out /etc/ssl/certs/dhparam-$DOMAIN.pem 2048
}

create_ssl_snippet() {
  echo "### Creating SSL DH snippet"
  sudo tee "$NGINX_ROOT/snippets/ssl-$DOMAIN.conf" > /dev/null << EOF
  ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
EOF
}

create_ssl_snippet_dh() {
  echo "### Creating SSL DH snippet"
  sudo tee "$NGINX_ROOT/snippets/ssl-dh-$DOMAIN.conf" > /dev/null << EOF
  # from https://cipherli.st/
  # and https://raymii.org/s/tutorials/Strong_SSL_Security_On_nginx.html

  ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
  ssl_prefer_server_ciphers on;
  ssl_ciphers "EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH";
  ssl_ecdh_curve secp384r1;
  ssl_session_cache shared:SSL:10m;
  ssl_session_tickets off;
  ssl_stapling on;
  ssl_stapling_verify on;
  resolver 8.8.8.8 8.8.4.4 valid=300s;
  resolver_timeout 5s;
  # disable HSTS header for now
  #add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload";
  add_header X-Frame-Options DENY;
  add_header X-Content-Type-Options nosniff;

  ssl_dhparam /etc/ssl/certs/dhparam-$DOMAIN.pem;
EOF
}

if ! hash certbot 2>/dev/null; then
  echo "### Certbot already installed, skipping"
  install_certbot
fi
setting_webroot
create_nginx_vh_well_known
restart_nginx
create_certificates
create_diffie_hellman
create_ssl_snippet
create_ssl_snippet_dh
create_nginx_vh_domain
restart_nginx
echo "### SUCCESS!"
echo "Please add the following line to crontab for auto renewal (if not already there):"
echo '15 3 * * * /usr/bin/certbot renew --quiet --renew-hook "/bin/systemctl reload nginx"'
