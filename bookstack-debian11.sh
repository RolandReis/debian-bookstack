#!/bin/bash
# Roland Reis, 03/2022
# use this script to install bookstack on your local system
# including mysql and apache2 installation/configuration
###########################################################

# check privileges
if [ "$EUID" -ne 0 ]; then
  printf "Error: Please run as root\n"
  exit 3
fi

# get os info
OS=$(cat /etc/debian_version)
if [[ $OS != "11."* ]]; then
  printf "Error: This script is only tested for Debian 11.x, you are running $OS\n"
  exit 3
else
  # update local repo and install dependencies
  printf "\nUpdating package information..."
  apt update >/dev/null 2>&1
  printf " Done\nInstalling dependencies (might take some time)..."
  apt -y install apache2 mariadb-server libapache2-mod-php7.4 php7.4 php7.4-fpm php7.4-curl php7.4-mbstring php7.4-ldap php7.4-tidy php7.4-xml php7.4-zip php7.4-gd php7.4-mysql mariadb-client git curl  >/dev/null 2>&1
  printf " Done\n"
  # mysql secure installation
  read -p "Do you want to run mysql_secure_installation (recommended)? [y|n] " -n 1 -r
  if [[ ! $REPLY =~ ^[Yy]$ ]]
  then
    printf "\nSkipping mysql secure installation...\n"
  else
    printf "\nSecuring mysql installation, please follow the instructions:"
    mysql_secure_installation
    sleep 2
  fi
  #enable services
  printf "\nStarting services..."
  systemctl start mariadb.service >/dev/null 2>&1
  systemctl enable mariadb.service >/dev/null 2>&1
  systemctl enable apache2.service >/dev/null 2>&1
  printf " Done\n"
  # database/user setup
  read -p "Please enter the name of the new bookstack database [bookstack]: " DBNAME
  DBNAME=${DBNAME:-"bookstack"}
  read -p "Please enter administrative database user [root]: " DBADMIN
  DBADMIN=${DBADMIN:-"root"}
  read -s -p "Please enter password for administrative user $DBADMIN: " DBADMINPASS
  BSPASS=$(date +%s | sha256sum | base64 | head -c 32 ; echo)
  printf " Done\nSetting up database environment..."
  mysql -h localhost -u ${DBADMIN} -p${DBADMINPASS} <<MYSQL_PREP
  CREATE DATABASE $DBNAME;
  CREATE USER 'bookstack'@'localhost' IDENTIFIED BY '$BSPASS';
  GRANT ALL ON $DBNAME.* TO 'bookstack'@'localhost';
  FLUSH PRIVILEGES;
MYSQL_PREP
  printf " Done\n"

  # bookstack installation
  read -p "Please enter the directory where you would like to install bookstack [/var/www/bookstack]: " BSDIR
  BSDIR=${BSDIR:-"/var/www/bookstack"}
  printf "Creating directory $BSDIR..."
  mkdir -p $BSDIR
  printf " Done\n"
  printf "Cloning bookstack project from github to $BSDIR..."
  git clone https://github.com/BookStackApp/BookStack.git --branch release --single-branch $BSDIR >/dev/null 2>&1
  printf " Done\n"
  printf "Running initial installation..."
  cd $BSDIR && curl -s https://getcomposer.org/installer > composer-setup.php && php composer-setup.php --quiet && rm -f composer-setup.php
  export COMPOSER_ALLOW_SUPERUSER=1 && php composer.phar install --no-dev --no-plugins >/dev/null 2>&1
  printf " Done\n"
  printf "Creating bookstack configuration file $BSDIR/.env..."
  BSCONFIG="$BSDIR/.env"
  cp $BSDIR/.env.example $BSCONFIG
  printf " Done\n"
  printf "Generating App Key... "
  php artisan key:generate --no-interaction --force
  printf "Making final changes to bookstack configuration file..."
  sed -i -e '/APP_URL=/ s/=.*/=http\:\/\/'"$HOSTNAME"'\//' $BSCONFIG
  sed -i -e '/DB_DATABASE=/ s/=.*/='"$DBNAME"'/' $BSCONFIG
  sed -i -e '/DB_USERNAME=/ s/=.*/=bookstack/' $BSCONFIG
  sed -i -e '/DB_PASSWORD=/ s/=.*/='"$BSPASS"'/' $BSCONFIG
  cat << EOF >> $BSCONFIG

# Failed Access Logging
LOG_FAILED_LOGIN_MESSAGE='Failed login for %u'

# Application Environment
APP_ENV=production
APP_DEBUG=false

# Redis Cache
# In this section you can set up redis cache connection if available
#CACHE_DRIVER=redis
#SESSION_DRIVER=redis
#REDIS_SERVERS=
#CACHE_PREFIX=bookstack
EOF
  printf " Done\n"
  printf "Loading database schema..."
  php artisan migrate --no-interaction --force >/dev/null 2>&1
  printf " Done\nSetting up correct permissions..."
  chown www-data:www-data -R bootstrap/cache public/uploads storage
  chmod -R 755 bootstrap/cache public/uploads storage

  # apache2 webserver configuration
  printf " Done\nSetting up apache2 webserver configuration for bookstack..."
  a2enmod rewrite >/dev/null 2>&1
  cat << HTTPDCONF > /etc/apache2/sites-available/bookstack.conf
<VirtualHost *:80>
	ServerName FQDN
	ServerAdmin webmaster@localhost
	DocumentRoot $BSDIR/public/

    <Directory $BSDIR/public/>
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
        <IfModule mod_rewrite.c>
            <IfModule mod_negotiation.c>
                Options -MultiViews -Indexes
            </IfModule>

            RewriteEngine On

            # Handle Authorization Header
            RewriteCond %{HTTP:Authorization} .
            RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]

            # Redirect Trailing Slashes If Not A Folder...
            RewriteCond %{REQUEST_FILENAME} !-d
            RewriteCond %{REQUEST_URI} (.+)/$
            RewriteRule ^ %1 [L,R=301]

            # Handle Front Controller...
            RewriteCond %{REQUEST_FILENAME} !-d
            RewriteCond %{REQUEST_FILENAME} !-f
            RewriteRule ^ index.php [L]
        </IfModule>
    </Directory>

	ErrorLog ${APACHE_LOG_DIR}/bookstack_error.log
	CustomLog ${APACHE_LOG_DIR}/bookstack_access.log combined
</VirtualHost>
HTTPDCONF
  # enable webserver config
  a2dissite 000-default.conf >/dev/null 2>&1
  a2ensite bookstack.conf >/dev/null 2>&1
  systemctl restart apache2
  printf " Done\n"
  sleep 2
  # fin
  printf "\n#####################################################################################################\n"
  printf "Everything done! Setup summary:\n"
  printf "DB Name:         %10s$DBNAME\n"
  printf "DB User:         %10sbookstack\n"
  printf "DB Password:     %10s$BSPASS\n"
  printf "Bookstack Dir:   %10s$BSDIR\n"
  printf "Bookstack Config:%10s$BSDIR/.env\n"
  printf "Webserver Config:%10s/etc/apache2/sites-available/bookstack.conf\n\n"
  printf "Bookstack URL:   %10shttp://$HOSTNAME/\n"
  printf "Administrator:   %10sadmin@admin.com\n"
  printf "Admin Password:  %10spassword\n\n"
  printf "In addition to securing Apache2, login via a public network should only be done via HTTPS\n"
  printf "(and certificate). Obviously, the default login should also be changed as soon as possible\n"
  printf "and the official documentation should be consulted: https://www.bookstackapp.com/docs/admin/security/\n"
  exit 0
fi