#!/bin/bash

# Set error handling
set -e
trap 'echo -e "${RED}Error occurred at line $LINENO: $BASH_COMMAND"' ERR

####################################################################################################

# Define colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC="\033[0m" # No Color

# Define application-specific variables
APP_NAME="peering-api-app"
APP_DIR="$HOME/$APP_NAME"
DOMAIN="api.smartcyber.in"
GITHUB_REPO="https://SmartCyberIN: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@github.com/SmartCyberIN/peering-api-app.git"
LOG_FILE="$HOME/$APP_NAME-install.log"
CERTBOT_EMAIL="${CERTBOT_EMAIL:-radha.krishnadivin@gmail.com}"
DB_NAME="${DB_NAME:-laravel_db}"
DB_USER="${DB_USER:-laravel_user}"
DB_PASS="${DB_PASS:-$(openssl rand -base64 16)}"                       # Generate a secure password
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-AwRdKjoMHBs9qmO88BWqbg==}" # Default root password

####################################################################################################

### Function to log messages with timestamps ###
log_message() {
    local MESSAGE="$1"
    echo -e "$(date +'%Y-%m-%d %H:%M:%S') - $MESSAGE" | tee -a "$LOG_FILE"
}

### Function to print messages in a specified color ###
print_message() {
    local COLOR="$1"
    local MESSAGE="$2"
    echo -e "${COLOR}$MESSAGE${NC}"
}

### Function to handle errors gracefully ###
handle_error() {
    local ERROR_MESSAGE="$1"
    print_message "$RED" "$ERROR_MESSAGE"
    log_message "$ERROR_MESSAGE"
    exit 1
}

### Functions for various log levels
print_success() { print_message "$GREEN" "$1"; }
print_error() { print_message "$RED" "$1"; }
print_warning() { print_message "$YELLOW" "$1"; }
print_info() { print_message "$BLUE" "$1"; }

### Function to check command execution and handle errors ###
check_command() {
    "$@" || handle_error "Command '$*' failed with exit code $?"
}

### Function to install a package if it is not already installed ###
install_if_not_present() {
    local PACKAGE="$1"
    if ! command -v "$PACKAGE" &>/dev/null; then
        print_info "Installing $PACKAGE..."
        check_command sudo "$PACKAGE_MANAGER" install -y "$PACKAGE"
    else
        print_success "$PACKAGE is already installed."
    fi
}

####################################################################################################
# Installation functions
####################################################################################################

### Function to detect the package manager ###
detect_package_manager() {
    print_info "Detecting package manager..."

    # Check for common package managers
    if command -v apt &>/dev/null; then
        PACKAGE_MANAGER="apt"
        print_success "Package manager detected: apt"
    elif command -v dnf &>/dev/null; then
        PACKAGE_MANAGER="dnf"
        print_success "Package manager detected: dnf"
    elif command -v yum &>/dev/null; then
        PACKAGE_MANAGER="yum"
        print_success "Package manager detected: yum"
    else
        handle_error "Unsupported package manager. Please install apt, dnf, or yum."
    fi
}

# Step 1: Detect and update package manager
detect_package_manager

print_info "Starting installation for $APP_NAME..."
### Function to update and upgrade the system ###
update_system() {
    print_info "Updating package manager..."
    check_command sudo "$PACKAGE_MANAGER" update -y
    check_command sudo "$PACKAGE_MANAGER" upgrade -y
    print_success "System updated successfully."
}

# Step 2: Update the system
update_system

### Function to install Apache ###
install_apache() {
    install_if_not_present "apache2"
    sudo systemctl start apache2
    sudo systemctl enable apache2
}

# Step 3: Install Apache
install_apache

### Function to install PHP and necessary extensions ###
install_php() {
    print_info "Installing PHP 8.2 and necessary extensions..."
    check_command sudo add-apt-repository ppa:ondrej/php -y
    check_command sudo add-apt-repository ppa:ondrej/apache2 -y
    check_command sudo apt update

    local REQUIRED_PACKAGES=(
        "git" "curl" "unzip" "php8.2"
        "libapache2-mod-php8.2" "php8.2-mysql" "php8.2-mysqlnd" "php8.2-xml"
        "php8.2-mbstring" "php8.2-curl" "php8.2-zip" "php8.2-bcmath" "php8.2-gd"
    )

    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        install_if_not_present "$pkg"
    done

    print_success "PHP 8.2 and extensions installed successfully."
}

# Step 4: Install PHP 8.2
install_php

### Function to install MySQL Server ###
install_mysql() {
    # print_info "Installing MySQL Server..."
    install_if_not_present mysql-server
    # check_command sudo mysql_secure_installation

    print_info "Securing MySQL installation..."
    sleep 5 # Wait for MySQL to start

    # Ensure MySQL service is running
    if ! sudo systemctl is-active --quiet mysql; then
        print_error "MySQL service is not running, attempting to start..."
        check_command sudo systemctl start mysql
    fi

    # Secure MySQL installation
    sudo mysql --user=root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test_%';
FLUSH PRIVILEGES;
EOF

    print_success "MySQL Server installed and secured successfully."
}

# Step 5: Install MySQL Server
install_mysql

### Function to create the database and user ###
setup_database() {
    print_info "Setting up MySQL database and user..."

    # # Prompt for passwords if not set
    # if [[ -z "$DB_PASS" ]]; then
    #     read -sp "Enter password for database user '$DB_USER': " DB_PASS
    #     echo
    # fi

    # MySQL commands for database and user setup
    mysql_script="
    CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;
    CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
    GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost' WITH GRANT OPTION;
    FLUSH PRIVILEGES;
"

    # Execute MySQL commands and handle errors
    if ! echo "$mysql_script" | sudo mysql -u root -p"$MYSQL_ROOT_PASSWORD" 2>error.log; then
        print_error "Database setup failed. Please check MySQL root credentials and try again. Error: $(cat error.log)"
        return 1
    fi

    print_success "Database setup completed successfully."

    # Change authentication method if needed
    if ! sudo mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "ALTER USER '$DB_USER'@'localhost' IDENTIFIED WITH mysql_native_password BY '$DB_PASS';" 2>>error.log; then
        print_warning "Could not change authentication method for '$DB_USER'. Proceeding without changing."
    fi

    # Validate the connection
    if ! mysql -u "$DB_USER" -p"$DB_PASS" -e "SHOW DATABASES;" 2>error.log; then
        print_error "Failed to connect to the database with user '$DB_USER'. Check the username and password. Error: $(cat error.log)"
        return 1
    fi

    print_success "Database connection verified '$DB_NAME' and user '$DB_USER' created successfully!"
}

# Step 6: Create the database and user
setup_database

### Function to install composer ###
install_composer() {
    print_info "Installing Composer..."
    # Download and install Composer
    check_command curl -sS https://getcomposer.org/installer | php
    # Move Composer to a global location
    check_command sudo mv composer.phar /usr/local/bin/composer
    # Make Composer executable
    check_command sudo chmod +x /usr/local/bin/composer

    print_success "Composer installed successfully."
}

# Step 7: Install Composer
install_composer

### Function to clone the application from GitHub ###
clone_app() {
    print_info "Cloning Laravel app from GitHub..."
    [ -d "$APP_DIR" ] && {
        print_warning "$APP_DIR exists. Removing..."
        sudo rm -rf "$APP_DIR"
    }
    check_command git clone "$GITHUB_REPO" "$APP_DIR"
}

# Step 8: Clone the application from GitHub
clone_app

### Function to set up the .env file ###
setup_env() {
    print_info "Setting up .env file..."
    cp "$APP_DIR/.env.example" "$APP_DIR/.env"
    cd "$APP_DIR" || handle_error "Failed to change directory to $APP_DIR"

    # Update .env file with database credentials
    sed -i "s|DB_DATABASE=.*|DB_DATABASE=$DB_NAME|" .env
    sed -i "s|DB_USERNAME=.*|DB_USERNAME=$DB_USER|" .env
    sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=$DB_PASS|" .env

    print_success ".env file configured successfully."
}

# Step 9: Create a MySQL Database
setup_env

### Function to install dependencies ###
install_dependencies() {
    print_info "Installing Composer dependencies..."
    check_command composer require SmartCyberIN/install SmartCyberIN/Laravel SmartCyberIN/peering
    check_command composer install #--no-dev
    print_success "Dependencies installed successfully."
}

# Step 10: Install Composer dependencies
install_dependencies

### Function to configure Apache ###
configure_apache() {
    print_info "Configuring Apache..."

    for dir in /etc/apache2/sites-available /etc/apache2/sites-enabled; do
        sudo mkdir -p "$dir" || handle_error "Failed to create directory $dir"
    done

    # Create a new Apache configuration file
    sudo tee /etc/apache2/sites-available/$APP_NAME.conf >/dev/null <<EOL
<VirtualHost *:80>
    ServerName $DOMAIN
    ServerAlias www.$DOMAIN
    DocumentRoot $APP_DIR

    <Directory $APP_DIR>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/$APP_NAME-error.log
    CustomLog \${APACHE_LOG_DIR}/$APP_NAME-access.log combined
</VirtualHost>
EOL

    # Enable the site and rewrite module
    check_command sudo a2ensite $APP_NAME.conf
    check_command sudo a2enmod rewrite

    # Restart Apache
    check_command sudo systemctl restart apache2

    # Test Apache configuration
    print_info "Testing Apache configuration..."
    check_command sudo apache2ctl configtest

    print_success "Apache configured and running for $APP_NAME."
}

# Step 11: Configure Apache
configure_apache

### Function to set permissions for storage and cache ###
set_permissions() {
    print_info "Setting permissions for storage and cache..."

    # Generate application key
    check_command php artisan key:generate

    # Clear caches
    check_command php artisan optimize:clear

    # Ensure necessary directories are executable
    for dir in "$HOME" "$APP_DIR"; do
        check_command sudo chmod +x "$dir"
    done

    # Install any necessary packages or features
    check_command php artisan smartcyber:install

    # Change ownership to www-data for the application directory
    check_command sudo chown -R www-data:www-data "$APP_DIR"
    check_command sudo chmod -R 775 "$APP_DIR/public"
    check_command sudo chmod -R 775 "$APP_DIR/storage"
    check_command sudo chmod -R 775 "$APP_DIR/bootstrap/cache"

    check_command sudo touch "$APP_DIR/storage/logs/laravel.log"
    check_command sudo chown www-data:www-data "$APP_DIR/storage/logs/laravel.log"
    check_command sudo chmod 644 "$APP_DIR/storage/logs/laravel.log"

    # Remove default Apache configuration files (if they exist)
    check_command sudo rm -f /etc/apache2/sites-available/000-default.conf
    check_command sudo rm -f /etc/apache2/sites-available/default-ssl.conf

    # Restart Apache
    check_command sudo systemctl restart apache2

    print_success "Permissions set successfully."
}

# Step 12: Set permissions for storage and cache
set_permissions

# Function to install Certbot and obtain SSL certificate
setup_ssl() {
    # print_info "Installing Certbot..."
    install_if_not_present certbot
    install_if_not_present python3-certbot-apache

    # Check if a certificate already exists for the domain
    if sudo certbot certificates | grep -q "$DOMAIN"; then
        print_warning "A certificate already exists for $DOMAIN. No new certificate will be obtained."
    else
        print_info "Obtaining SSL certificate..."
        check_command sudo certbot --apache -d "$DOMAIN" --email "$CERTBOT_EMAIL" --agree-tos --non-interactive
        print_success "SSL certificate obtained for $DOMAIN."
    fi

    print_info "Setting up automatic certificate renewal..."
    check_command sudo certbot renew --quiet
}

# Step 13: Install SSL certificate
setup_ssl

# Function to install cron job
cron_job() {
    # Define application-specific variables
    CRON_LOG_FILE="$HOME/$APP_NAME-queue_worker.log"
    CRON_JOB="*/15 * * * * cd $APP_DIR && php artisan queue:work >> $CRON_LOG_FILE 2>&1"

    # Function to check if the cron job exists
    check_cron_job() {
        crontab -l | grep -F "$CRON_JOB" >/dev/null 2>&1
    }

    # Function to add the cron job
    add_cron_job() {
        (
            crontab -l
            echo "$CRON_JOB"
        ) | crontab -
    }

    # Main script logic
    if check_cron_job; then
        print_warning "Cron job already exists."
    else
        print_info "Adding cron job for Laravel queue worker..."
        add_cron_job
        print_success "Cron job added successfully."
    fi
}

# Step 14: Install cron job
cron_job

##################################################

print_success "Laravel application hosted at http://$DOMAIN and https://$DOMAIN !"
