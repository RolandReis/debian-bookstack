## About
This project provides unofficial scripts for installing an updating (coming soon) [Bookstack](https://www.bookstackapp.com/) on Debian 11 including MySQL and Apache2 installation/configuration. Please make sure you have an up-to-date backup of your system or use a freshly installed Debian 11 to run it.

<hr>
## Howto
Clone or download the script to the machine where you would like to install Bookstack on. Make sure to set correct permissions and run the script:
`chmod +x bookstack-debian11.sh`
`./bookstack-debian11.sh`

The script is a perfect fit to install Bookstack as easy as possible on your Debian system and will guide you through following steps:
1. Installing all needed dependencies for Bookstack on Debian 11
2. Running "mysql_secure_installation" if desired
3. Clone and configure the latest Bookstack version from official Bookstack Github project
4. Setup local MySQL database for Bookstack
5. Provide basic Apache2 vHost configuration so that you can login to your new Bookstack instance directly after running the script

Please keep in mind that the script does not contain HTTPS configuration (yet). It also comes with the default login credentials which you should definitely change afterwards.