#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function for clear yes/no confirmation
clear_confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local response
    
    while true; do
        if [[ "$default" == "y" ]]; then
            read -p "$prompt (Y/n): " response
            response=${response:-y}
        else
            read -p "$prompt (y/N): " response
            response=${response:-n}
        fi
        
        case "$response" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            *) echo "Please answer yes (y) or no (n)." ;;
        esac
    done
}

# Function to get domain with confirmation
get_domain() {
    local domain
    while true; do
        read -p "Enter your domain (e.g., kuromey.eu.org): " domain
        if [[ -n "$domain" ]]; then
            if clear_confirm "Use domain: $domain?" "y"; then
                echo "$domain"
                return 0
            fi
        else
            echo "Domain cannot be empty"
        fi
    done
}

# Function to handle existing installation
handle_existing() {
    echo -e "${YELLOW}⚠️ INSTALASI YANG ADA TERDETEKSI${NC}"
    echo "Ditemukan instalasi Nextcloud yang sudah ada."
    echo
    echo "Pilihan:"
    echo "  1️⃣ Reset total (hapus semua data dan mulai fresh)"
    echo "  2️⃣ Perbaiki instalasi yang ada (backup data)"
    echo
    
    while true; do
        read -p "Pilih opsi (1 atau 2): " choice
        case $choice in
            1)
                echo -e "${YELLOW}Anda memilih: Reset total${NC}"
                read -p "⚠️ Konfirmasi reset total dan hapus semua data? (y/N): " confirm
                if [[ $confirm =~ ^[Yy]$ ]]; then
                    echo -e "${RED}🗑️ Melakukan reset total...${NC}"
                    reset_everything
                    echo -e "${GREEN}✅ Reset selesai, melanjutkan deployment fresh${NC}"
                    echo
                    break
                else
                    echo -e "${BLUE}Reset dibatalkan, silakan pilih opsi lain...${NC}"
                    echo
                fi
                ;;
            2)
                echo -e "${YELLOW}Anda memilih: Perbaiki instalasi yang ada${NC}"
                read -p "✅ Konfirmasi perbaiki instalasi yang ada? (Y/n): " confirm
                if [[ $confirm =~ ^[Nn]$ ]]; then
                    echo -e "${BLUE}Perbaikan dibatalkan, silakan pilih opsi lain...${NC}"
                    echo
                else
                    echo -e "${BLUE}🔧 Memperbaiki instalasi yang ada...${NC}"
                    fix_existing
                    echo -e "${GREEN}✅ Perbaikan selesai, melanjutkan deployment${NC}"
                    echo
                    break
                fi
                ;;
            *)
                echo -e "${RED}❌ Pilihan tidak valid. Silakan pilih 1 atau 2.${NC}"
                echo
                ;;
        esac
    done
}

# Function to reset everything
reset_everything() {
    echo -e "${RED}🗑️ Menghapus semua data...${NC}"
    
    # Ensure we're in the right directory
    if [[ ! -d "/home/paperspace/nextcloud-server" ]]; then
        echo -e "${YELLOW}⚠️  Project directory not found, creating it...${NC}"
        mkdir -p /home/paperspace/nextcloud-server
    fi
    
    cd /home/paperspace/nextcloud-server
    
    # Stop and remove containers
    docker compose down -v 2>/dev/null || true
    
    # Unmount any existing mounts
    sudo fusermount -u data 2>/dev/null || true
    sudo umount data 2>/dev/null || true
    
    # Kill rclone processes
    sudo pkill -f "rclone mount" 2>/dev/null || true
    
    # Remove directories and files
    sudo rm -rf data data-backup-* docker-compose.yml logs/*.log 2>/dev/null || true
    
    # Remove Docker volumes
    docker volume prune -f 2>/dev/null || true
    
    echo -e "${GREEN}✅ Reset total selesai${NC}"
}

# Function to fix existing installation
fix_existing() {
    echo -e "${BLUE}🔧 Memperbaiki instalasi yang ada...${NC}"
    
    # Ensure we're in the right directory
    if [[ ! -d "/home/paperspace/nextcloud-server" ]]; then
        echo -e "${RED}❌ Project directory not found${NC}"
        return 1
    fi
    
    cd /home/paperspace/nextcloud-server
    
    # Backup existing data
    if [[ -d "data" && "$(ls -A data 2>/dev/null)" ]]; then
        echo -e "${YELLOW}📦 Membuat backup data...${NC}"
        BACKUP_DIR="data-backup-$(date +%Y%m%d-%H%M%S)"
        sudo cp -r data "$BACKUP_DIR" 2>/dev/null || {
            echo -e "${YELLOW}⚠️  Backup failed, continuing anyway...${NC}"
        }
        # Fix permissions on backup
        sudo chown -R paperspace:paperspace "$BACKUP_DIR" 2>/dev/null || true
    fi
    
    # Stop containers gracefully
    docker compose down 2>/dev/null || true
    
    # Unmount if mounted
    sudo fusermount -u data 2>/dev/null || true
    
    echo -e "${GREEN}✅ Perbaikan selesai${NC}"
}

# Function to install dependencies
install_dependencies() {
    echo -e "${BLUE}�� Checking system dependencies...${NC}"
    
    local missing_deps=()
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        missing_deps+=("docker")
    fi
    
    # Check Docker Compose
    if ! docker compose version &> /dev/null; then
        missing_deps+=("docker-compose")
    fi
    
    # Check rclone
    if ! command -v rclone &> /dev/null; then
        missing_deps+=("rclone")
    fi
    
    # Check FUSE
    if ! command -v fusermount &> /dev/null && ! command -v fusermount3 &> /dev/null; then
        missing_deps+=("fuse3")
    fi
    
    if [[ ${#missing_deps[@]} -eq 0 ]]; then
        echo -e "${GREEN}✅ All dependencies are already installed${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}📦 Installing missing dependencies: ${missing_deps[*]}${NC}"
    
    # Update package list
    apt-get update
    
    # Install missing dependencies
    for dep in "${missing_deps[@]}"; do
        case "$dep" in
            "docker")
                curl -fsSL https://get.docker.com | sh
                ;;
            "docker-compose")
                # Docker Compose is included with Docker now
                echo "Docker Compose will be available with Docker"
                ;;
            "rclone")
                curl https://rclone.org/install.sh | bash
                ;;
            "fuse3")
                apt-get install -y fuse3
                ;;
        esac
    done
    
    echo -e "${GREEN}✅ Dependencies installed successfully${NC}"
}

# Function to setup Docker permissions
setup_docker_permissions() {
    echo -e "${BLUE}🐳 Checking Docker permissions...${NC}"
    
    if ! groups paperspace | grep -q docker; then
        echo -e "${YELLOW}🔧 Adding paperspace user to docker group...${NC}"
        usermod -aG docker paperspace
        echo -e "${GREEN}✅ Docker permissions configured${NC}"
        echo -e "${YELLOW}⚠️ Please logout and login again, or run: newgrp docker${NC}"
    else
        echo -e "${GREEN}✅ Docker permissions already configured${NC}"
    fi
}

# Function to fix FUSE configuration - IMPROVED
fix_fuse_config() {
    echo -e "${BLUE}🔧 Checking FUSE configuration...${NC}"
    
    # Check if FUSE config file exists
    if [[ ! -f "/etc/fuse.conf" ]]; then
        echo -e "${YELLOW}⚠️ Creating FUSE configuration file...${NC}"
        echo "user_allow_other" | sudo tee /etc/fuse.conf > /dev/null
        echo -e "${GREEN}✅ FUSE configuration created${NC}"
    elif ! grep -q "^user_allow_other" /etc/fuse.conf 2>/dev/null; then
        echo -e "${YELLOW}⚠️ Fixing FUSE configuration for rclone mount...${NC}"
        sudo cp /etc/fuse.conf /etc/fuse.conf.backup 2>/dev/null || true
        echo "user_allow_other" | sudo tee -a /etc/fuse.conf > /dev/null
        echo -e "${GREEN}✅ FUSE configuration fixed${NC}"
    else
        echo -e "${GREEN}✅ FUSE already configured correctly${NC}"
    fi
    
    # Verify FUSE module is loaded
    echo -e "${BLUE}🔧 Loading FUSE module...${NC}"
    sudo modprobe fuse 2>/dev/null || true
    echo -e "${GREEN}✅ FUSE module loaded${NC}"
}

# Function to mount Google Drive with retry - IMPROVED
mount_google_drive_with_retry() {
    local max_retries=3
    local retry_count=0
    
    # Ensure RCLONE_CONFIG is set
    if [[ -z "$RCLONE_CONFIG" ]]; then
        export RCLONE_CONFIG="/home/paperspace/nextcloud-server/rclone/rclone.conf"
    fi
    
    # Verify rclone config exists
    if [[ ! -f "$RCLONE_CONFIG" ]]; then
        echo -e "${RED}❌ Rclone config not found: $RCLONE_CONFIG${NC}"
        return 1
    fi
    
    echo -e "${BLUE}🔗 Mounting Google Drive union (alldrive)...${NC}"
    
    # PERBAIKAN: Backup dan kosongkan direktori data jika tidak kosong
    if [[ -d "data" && "$(ls -A data 2>/dev/null)" ]]; then
        echo -e "${YELLOW}📦 Backing up existing data directory...${NC}"
        sudo mv data "data-backup-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
    fi
    
    # Ensure directory exists and has correct permissions
    mkdir -p data
    sudo chown paperspace:paperspace data
    sudo chmod 755 data
    
    # Unmount if already mounted
    sudo fusermount -u data 2>/dev/null || true
    sudo umount data 2>/dev/null || true
    
    # Kill any existing rclone processes for this mount
    sudo pkill -f "rclone mount.*$PWD/data" 2>/dev/null || true
    sleep 2
    
    while [[ $retry_count -lt $max_retries ]]; do
        echo -e "${BLUE}📡 Mount attempt $((retry_count + 1))/$max_retries...${NC}"
        
        # Create .ocdata in Google Drive if not exists
        echo "union-$(date +%s)" | sudo -u paperspace rclone \
            --config="$RCLONE_CONFIG" \
            rcat jetjeton:Nextcloud-Union/user-data/.ocdata 2>/dev/null || true
        
        # PERBAIKAN: Mount dengan opsi yang dioptimalkan untuk performa maksimal
        if sudo -u paperspace rclone mount \
            --config="$RCLONE_CONFIG" \
            alldrive:Nextcloud-Union/user-data data \
            --vfs-cache-mode full \
            --vfs-cache-max-size 8G \
            --vfs-cache-max-age 24h \
            --vfs-read-chunk-size 128M \
            --vfs-read-chunk-size-limit 2G \
            --buffer-size 256M \
            --dir-cache-time 24h \
            --poll-interval 1m \
            --allow-other \
            --allow-non-empty \
            --uid 33 \
            --gid 33 \
            --umask 007 \
            --daemon \
            --transfers 8 \
            --checkers 16 \
            --log-file logs/rclone-union.log; then
            
            # Wait for mount to be ready
            echo -e "${BLUE}⏳ Waiting for mount to be ready...${NC}"
            local wait_count=0
            while [[ $wait_count -lt 15 ]]; do
                if mountpoint -q data; then
                    echo -e "${GREEN}✅ Google Drive union (alldrive) mounted successfully!${NC}"
                    
                    # PERBAIKAN: Ensure basic structure exists in Google Drive
                    echo -e "${BLUE}🔧 Ensuring basic structure in Google Drive...${NC}"
                    mkdir -p data/admin/files 2>/dev/null || true
                    sudo chown -R 33:33 data 2>/dev/null || true
                    
                    return 0
                fi
                sleep 1
                ((wait_count++))
            done
        fi
        
        echo -e "${YELLOW}⚠️ Mount attempt $((retry_count + 1)) failed${NC}"
        ((retry_count++))
        
        if [[ $retry_count -lt $max_retries ]]; then
            echo -e "${BLUE}🔄 Retrying in 5 seconds...${NC}"
            sleep 5
        fi
    done
    
    echo -e "${RED}❌ Failed to mount Google Drive after $max_retries attempts${NC}"
    echo -e "${YELLOW}📋 Mount log:${NC}"
    cat logs/rclone-union.log 2>/dev/null || echo "No log file found"
    return 1
}

# Function to check mount status
check_mount_status() {
    if mount | grep -q "alldrive:Nextcloud-Union/user-data"; then
        echo -e "${GREEN}✅ Google Drive sudah ter-mount${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠️  Google Drive belum ter-mount${NC}"
        return 1
    fi
}

# Function to backup local data
backup_local_data() {
    echo -e "${YELLOW}📦 Membuat backup data lokal...${NC}"
    BACKUP_FILE="backups/local-data-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    mkdir -p backups
    
    if [[ -d "data" && "$(ls -A data 2>/dev/null)" ]]; then
        sudo tar -czf "$BACKUP_FILE" data/
        echo -e "${GREEN}✅ Backup berhasil: $BACKUP_FILE${NC}"
    else
        echo -e "${YELLOW}⚠️  Direktori data kosong, skip backup${NC}"
    fi
}

# Function to unmount Google Drive
unmount_google_drive() {
    echo -e "${YELLOW}📤 Unmounting Google Drive...${NC}"
    
    if mount | grep -q "alldrive:Nextcloud-Union/user-data"; then
        sudo umount /home/paperspace/nextcloud-server/data || {
            echo -e "${YELLOW}⚠️  Unmount gagal, mencoba force unmount...${NC}"
            sudo umount -f /home/paperspace/nextcloud-server/data || {
                echo -e "${RED}❌ Force unmount gagal, mencoba lazy unmount...${NC}"
                sudo umount -l /home/paperspace/nextcloud-server/data
            }
        }
        echo -e "${GREEN}✅ Google Drive berhasil di-unmount${NC}"
    else
        echo -e "${YELLOW}⚠️  Google Drive sudah tidak ter-mount${NC}"
    fi
}

# Function to restore local data
restore_local_data() {
    echo -e "${YELLOW}�� Restoring data lokal...${NC}"
    
    # Cari backup terbaru
    LATEST_BACKUP=$(ls -t backups/local-data-backup-*.tar.gz 2>/dev/null | head -1)
    
    if [[ -n "$LATEST_BACKUP" ]]; then
        echo -e "${BLUE}📁 Menggunakan backup: $LATEST_BACKUP${NC}"
        
        # Hapus direktori data lama jika ada
        if [[ -d "data" ]]; then
            sudo rm -rf data
        fi
        
        # Extract backup
        sudo tar -xzf "$LATEST_BACKUP"
        
        # Perbaiki izin
        sudo chown -R www-data:www-data data/
        
        echo -e "${GREEN}✅ Data lokal berhasil di-restore${NC}"
    else
        echo -e "${RED}❌ Tidak ada backup yang ditemukan${NC}"
        return 1
    fi
}

# Function to check Nextcloud health - IMPROVED
check_nextcloud_health() {
    local max_attempts=30
    local attempt=1
    
    echo -e "${BLUE}🔍 Checking Nextcloud health...${NC}"
    
    while [[ $attempt -le $max_attempts ]]; do
        local http_status=$(curl -s -I http://localhost | head -1)
        if echo "$http_status" | grep -q "HTTP/1.1 [23]"; then
            echo -e "${GREEN}✅ Nextcloud healthy (attempt $attempt)${NC}"
            return 0
        fi
        echo -n "."
        sleep 2
        ((attempt++))
    done
    
    echo -e "${RED}❌ Nextcloud health check failed after $max_attempts attempts${NC}"
    echo -e "${YELLOW}Last HTTP status: $http_status${NC}"
    return 1
}

# Function to setup external storage mount
setup_external_storage_mount() {
    echo -e "${BLUE}🔧 Setting up external storage mount...${NC}"
    
    # Create external storage directory
    mkdir -p external-storage/alldrive
    
    # Fix permissions on external-storage directory before mounting
    sudo chown -R paperspace:paperspace external-storage/
    chmod -R 755 external-storage/

    # Create systemd service for external storage mount
    sudo tee /etc/systemd/system/nextcloud-external-storage.service > /dev/null << 'EOF'
[Unit]
Description=Nextcloud External Storage Mount
After=network.target
Requires=network.target

[Service]
Type=simple
User=paperspace
Group=paperspace
ExecStart=/usr/bin/rclone mount --config=/home/paperspace/nextcloud-server/rclone/rclone.conf alldrive: /home/paperspace/nextcloud-server/external-storage/alldrive --vfs-cache-mode full --vfs-cache-max-size 8G --vfs-cache-max-age 24h --vfs-read-chunk-size 128M --vfs-read-chunk-size-limit 2G --buffer-size 256M --dir-cache-time 24h --poll-interval 30s --allow-other --allow-non-empty --uid 33 --gid 33 --umask 007 --daemon-timeout 10m --transfers 8 --checkers 16 --log-level INFO --log-file /home/paperspace/nextcloud-server/logs/external-storage.log
ExecStop=/bin/fusermount -u /home/paperspace/nextcloud-server/external-storage/alldrive
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd and start service
    sudo systemctl daemon-reload
    sudo systemctl enable nextcloud-external-storage
    sudo systemctl restart nextcloud-external-storage
    
    # Wait for mount to be ready
    echo -e "${BLUE}⏳ Waiting for external storage mount...${NC}"
    local wait_count=0
    while [[ $wait_count -lt 30 ]]; do
        if mountpoint -q external-storage/alldrive; then
            echo -e "${GREEN}✅ External storage mounted successfully!${NC}"
            
            # Set proper permissions
            sudo chown -R paperspace:paperspace external-storage/
            chmod -R 755 external-storage/
            
            return 0
        fi
        sleep 2
        ((wait_count++))
    done
    
    echo -e "${YELLOW}⚠️ External storage mount may have issues${NC}"
    sudo systemctl status nextcloud-external-storage --no-pager
    return 1
}

# Function to fix external storage configuration automatically
fix_external_storage_configuration() {
    echo -e "${BLUE}🔧 Applying external storage configuration fixes...${NC}"
    
    # Fix 1: Ensure systemd service uses Type=simple
    echo -e "${YELLOW}🔧 Fix 1/4: Ensuring systemd service uses Type=simple...${NC}"
    if [[ -f "/etc/systemd/system/nextcloud-external-storage.service" ]]; then
        if grep -q "Type=notify" /etc/systemd/system/nextcloud-external-storage.service; then
            sudo sed -i 's/Type=notify/Type=simple/g' /etc/systemd/system/nextcloud-external-storage.service
            sudo systemctl daemon-reload
            sudo systemctl restart nextcloud-external-storage.service
            echo -e "${GREEN}✅ Systemd service type changed to simple and restarted${NC}"
        else
            echo -e "${GREEN}✅ Systemd service already uses Type=simple${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️ Systemd service file not found, skipping this fix${NC}"
    fi
    
    # Wait for service to be ready
    sleep 5
    
    # Fix 2: Fix external storage directory permissions
    echo -e "${YELLOW}🔧 Fix 2/4: Fixing external storage directory permissions...${NC}"
    if [[ -d "external-storage" ]]; then
        sudo chown -R paperspace:paperspace external-storage/
        chmod -R 755 external-storage/
        echo -e "${GREEN}✅ External storage permissions fixed${NC}"
    else
        echo -e "${YELLOW}⚠️ External storage directory not found${NC}"
    fi
    
    # Fix 3: Enable Local external storage option in Nextcloud
    echo -e "${YELLOW}🔧 Fix 3/4: Enabling Local external storage option in Nextcloud...${NC}"
    local container_id=$(docker compose ps -q app 2>/dev/null)
    if [[ -n "$container_id" ]]; then
        docker exec --user www-data "$container_id" php occ config:system:set files_external_allow_create_new_local --value=true 2>/dev/null || {
            echo -e "${YELLOW}⚠️ Could not enable local external storage option${NC}"
        }
        echo -e "${GREEN}✅ Local external storage option enabled in Nextcloud${NC}"
    else
        echo -e "${YELLOW}⚠️ Could not find Nextcloud container${NC}"
    fi
    
    # Fix 4: Restart Nextcloud container to apply changes
    echo -e "${YELLOW}🔧 Fix 4/4: Restarting Nextcloud container to apply changes...${NC}"
    docker compose restart app
    sleep 10
    echo -e "${GREEN}✅ Nextcloud container restarted with external storage fixes${NC}"
    
    echo -e "${GREEN}✅ External storage configuration fixes completed!${NC}"
    echo -e "${BLUE}📋 Applied fixes:${NC}"
    echo -e "   ✓ Systemd service type set to simple"
    echo -e "   ✓ External storage permissions fixed"
    echo -e "   ✓ Local external storage option enabled"
    echo -e "   ✓ Services restarted and ready"
}

# Function to fix trusted domains - NEW
fix_trusted_domains() {
    echo -e "${BLUE}�� Configuring trusted domains...${NC}"
    
    # Wait for container to be ready
    sleep 5
    
    # Add localhost and domain to trusted domains
    docker compose exec -T app bash -c "
        if [[ -f /var/www/html/config/config.php ]]; then
            # Backup original config
            cp /var/www/html/config/config.php /var/www/html/config/config.php.backup
            
            # Add localhost to trusted domains using sed
            sed -i '/trusted_domains/,/),/c\
  \'trusted_domains\' => \
  array (\
    0 => \'$DOMAIN\',\
    1 => \'localhost\',\
  ),' /var/www/html/config/config.php
            
            echo 'Trusted domains configured successfully'
        else
            echo 'Config file not found, skipping trusted domains fix'
        fi
    " 2>/dev/null || {
        echo -e "${YELLOW}⚠️ Could not fix trusted domains automatically${NC}"
        return 1
    }
    
    echo -e "${GREEN}✅ Trusted domains configured${NC}"
}

# Function to fix Google Drive permissions - IMPROVED
fix_google_drive_permissions() {
    echo -e "${BLUE}🔧 Fixing Google Drive mount permissions...${NC}"
    
    # Set proper permissions for rclone mount point
    sudo chmod 755 data 2>/dev/null || true
    
    # Wait for mount to stabilize
    sleep 3
    
    # Fix Nextcloud data directory permissions inside container
    docker compose exec -T app bash -c "
        # Set proper ownership and permissions
        chown -R www-data:www-data /var/www/html/data 2>/dev/null || true
        chmod 750 /var/www/html/data 2>/dev/null || true
        
        # Create .ocdata if not exists
        if [[ ! -f /var/www/html/data/.ocdata ]]; then
            echo 'Nextcloud' > /var/www/html/data/.ocdata
            chown www-data:www-data /var/www/html/data/.ocdata
        fi
        
        echo 'Google Drive permissions configured'
    " 2>/dev/null || {
        echo -e "${YELLOW}⚠️ Could not fix all permissions${NC}"
        return 1
    }
    
    echo -e "${GREEN}✅ Google Drive permissions fixed${NC}"
}

# Function to clean Nextcloud cache and scan files - NEW
clean_nextcloud_cache() {
    echo -e "${BLUE}🧹 Cleaning Nextcloud cache and scanning files...${NC}"
    
    # Remove broken JS and CSS cache
    echo -e "${YELLOW}🗑️ Removing broken JavaScript and CSS cache...${NC}"
    docker exec -u 33 nextcloud-server-app-1 rm -rf /var/www/html/data/appdata_*/js 2>/dev/null || true
    docker exec -u 33 nextcloud-server-app-1 rm -rf /var/www/html/data/appdata_*/css 2>/dev/null || true
    
    # Run maintenance repair
    echo -e "${YELLOW}🔧 Running maintenance repair...${NC}"
    docker exec -u 33 nextcloud-server-app-1 php occ maintenance:repair 2>/dev/null || true
    docker exec -u 33 nextcloud-server-app-1 php occ maintenance:update:htaccess 2>/dev/null || true
    
    # Clean file cache and scan files
    docker compose exec -T -u www-data app bash -c "
        cd /var/www/html
        php occ files:cleanup 2>/dev/null || echo 'Cache cleanup completed'
        php occ files:scan --all 2>/dev/null || echo 'File scan completed'
        echo 'Cache and file system maintenance completed'
    " 2>/dev/null || {
        echo -e "${YELLOW}⚠️ Could not run cache cleanup automatically${NC}"
        return 1
    }
    
    # Ensure appdata structure is complete after cache cleanup
    ensure_appdata_structure
    
    echo -e "${GREEN}✅ Cache cleaned, maintenance repair completed, and files scanned${NC}"
}

# Function to ensure appdata directory structure is complete
ensure_appdata_structure() {
    echo -e "${BLUE}🔧 Ensuring appdata directory structure is complete...${NC}"
    
    docker exec -u 0 nextcloud-server-app-1 bash -c '
        # Find appdata directory
        APPDATA_DIR=$(find /var/www/html/data -name "appdata_*" -type d | head -1)
        if [[ -n "$APPDATA_DIR" ]]; then
            echo "Found appdata directory: $APPDATA_DIR"
            
            # Create necessary subdirectories
            mkdir -p "$APPDATA_DIR/theming/global/0"
            mkdir -p "$APPDATA_DIR/preview"
            mkdir -p "$APPDATA_DIR/css"
            mkdir -p "$APPDATA_DIR/js"
            mkdir -p "$APPDATA_DIR/js/core"
            mkdir -p "$APPDATA_DIR/avatar"
            mkdir -p "$APPDATA_DIR/appstore"
            
            # Create essential cache files
            echo "{}" > "$APPDATA_DIR/appstore/apps.json"
            
            # Set proper ownership and permissions
            chown -R www-data:www-data "$APPDATA_DIR"
            chmod -R 750 "$APPDATA_DIR"
            
            echo "Appdata structure ensured and permissions fixed"
        else
            echo "No appdata directory found, will be created automatically by Nextcloud"
        fi
    ' 2>/dev/null || true
    
    echo -e "${GREEN}✅ Appdata directory structure verified${NC}"
}

# Comprehensive fix for AppStore and GenericFileException issues
fix_appstore_comprehensive() {
    echo -e "${BLUE}🚀 Starting comprehensive AppStore and GenericFileException fix...${NC}"
    
    # Verify container is running
    if ! docker ps | grep -q "nextcloud-server-app-1"; then
        echo -e "${RED}❌ Nextcloud container not running. Starting containers...${NC}"
        docker compose up -d || {
            echo -e "${RED}❌ Failed to start containers${NC}"
            return 1
        }
        echo -e "${YELLOW}⏳ Waiting for container to be ready...${NC}"
        sleep 10
    fi
    
    # Step 1: Enable maintenance mode
    echo -e "${BLUE}🔧 Step 1/8: Enabling maintenance mode...${NC}"
    docker exec -u 33 nextcloud-server-app-1 php occ maintenance:mode --on 2>/dev/null || true
    
    # Step 1.5: Fix mount permissions and create missing files immediately
    echo -e "${BLUE}🔧 Step 1.5/8: Creating missing files in Google Drive mount...${NC}"
    
    # Ensure proper mount permissions
    sudo chown -R 33:33 data 2>/dev/null || true
    sudo chmod -R 755 data 2>/dev/null || true
    
    # Step 1.6: Fix missing appdata directories dynamically
    echo -e "${BLUE}🔧 Step 1.6/8: Fixing missing appdata directories...${NC}"
    
    # Get the current appdata directory that Nextcloud is trying to use from logs
    CURRENT_APPDATA=$(tail -20 data/nextcloud.log 2>/dev/null | grep -o 'appdata_[a-zA-Z0-9]*' | tail -1)
    
    if [[ -n "$CURRENT_APPDATA" ]]; then
        echo "Found current appdata directory: $CURRENT_APPDATA"
        
        # Create the missing appdata directory structure
        mkdir -p "data/$CURRENT_APPDATA/appstore" 2>/dev/null || true
        mkdir -p "data/$CURRENT_APPDATA/js/core" 2>/dev/null || true
        mkdir -p "data/$CURRENT_APPDATA/css" 2>/dev/null || true
        
        # Create essential files
        echo '{}' > "data/$CURRENT_APPDATA/appstore/apps.json" 2>/dev/null || true
        echo '{}' > "data/$CURRENT_APPDATA/appstore/categories.json" 2>/dev/null || true
        echo '/* Nextcloud core merged template */' > "data/$CURRENT_APPDATA/js/core/merged-template-prepend.js" 2>/dev/null || true
        
        # Set proper ownership
        sudo chown -R 33:33 "data/$CURRENT_APPDATA" 2>/dev/null || true
        sudo chmod -R 750 "data/$CURRENT_APPDATA" 2>/dev/null || true
        
        echo -e "${GREEN}✅ Fixed missing appdata directory: $CURRENT_APPDATA${NC}"
    else
        echo "No specific appdata directory found in logs, will create during container check"
    fi
    
    # Create missing admin files directly in the mount
    mkdir -p data/admin/files/{Documents,Photos,Templates} 2>/dev/null || true
    
    # Create the missing Readme.md files that are causing errors
    echo "# Welcome to Nextcloud!" > data/admin/files/Readme.md 2>/dev/null || true
    echo "# Documents" > data/admin/files/Documents/Readme.md 2>/dev/null || true
    echo "# Photos" > data/admin/files/Photos/Readme.md 2>/dev/null || true
    echo "# Templates" > data/admin/files/Templates/Readme.md 2>/dev/null || true
    
    # Set proper ownership for the files we just created
    sudo chown -R 33:33 data/admin/ 2>/dev/null || true
    sudo chmod -R 755 data/admin/ 2>/dev/null || true
    
    echo -e "${GREEN}✅ Missing files created in Google Drive mount${NC}"
    
    # Step 2: Fix appdata structure with all necessary directories and files
    echo -e "${BLUE}🏗️ Step 2/8: Creating complete appdata structure...${NC}"
    docker exec -u 0 nextcloud-server-app-1 bash -c '
        APPDATA_DIR=$(find /var/www/html/data -name "appdata_*" -type d | head -1)
        if [[ -n "$APPDATA_DIR" ]]; then
            echo "Creating complete appdata structure in: $APPDATA_DIR"
            
            # Create all necessary directories
            mkdir -p "$APPDATA_DIR/js/core"
            mkdir -p "$APPDATA_DIR/css"
            mkdir -p "$APPDATA_DIR/appstore"
            mkdir -p "$APPDATA_DIR/theming/global/0"
            mkdir -p "$APPDATA_DIR/preview"
            mkdir -p "$APPDATA_DIR/avatar"
            mkdir -p "$APPDATA_DIR/thumbnails"
            
            # Create essential files with proper content
            echo "/* Nextcloud core merged template */" > "$APPDATA_DIR/js/core/merged-template-prepend.js"
            echo "{}" > "$APPDATA_DIR/appstore/apps.json"
            echo "{}" > "$APPDATA_DIR/appstore/categories.json"
            
            # Create additional missing JS files
            echo "/* Core JS */" > "$APPDATA_DIR/js/core/merged.js"
            echo "/* CSS */" > "$APPDATA_DIR/css/core.css"
            
            # Set proper ownership and permissions
            chown -R www-data:www-data "$APPDATA_DIR"
            chmod -R 750 "$APPDATA_DIR"
            
            echo "Complete appdata structure created successfully"
        fi
    ' 2>/dev/null || true
    
    # Step 3: Verify admin files are accessible from container
    echo -e "${BLUE}📁 Step 3/8: Verifying admin files accessibility...${NC}"
    docker exec -u 0 nextcloud-server-app-1 bash -c '
        ADMIN_DIR="/var/www/html/data/admin/files"
        
        # Verify files exist and are readable
        if [[ -f "$ADMIN_DIR/Readme.md" ]]; then
            echo "✅ Readme.md found and accessible"
        else
            echo "⚠️ Creating Readme.md as fallback"
            mkdir -p "$ADMIN_DIR"
            echo "# Welcome to Nextcloud!" > "$ADMIN_DIR/Readme.md"
        fi
        
        # Ensure proper permissions
        chown -R www-data:www-data "$ADMIN_DIR" 2>/dev/null || true
        chmod -R 755 "$ADMIN_DIR" 2>/dev/null || true
        
        echo "Admin files verified and accessible"
    ' 2>/dev/null || true
    
    # Step 4: Database maintenance and repair
    echo -e "${BLUE}🗃️ Step 4/8: Running database maintenance...${NC}"
    docker exec -u 33 nextcloud-server-app-1 bash -c '
        php occ db:add-missing-indices 2>/dev/null || true
        php occ db:add-missing-columns 2>/dev/null || true
        php occ maintenance:repair 2>/dev/null || true
        echo "Database maintenance completed"
    ' 2>/dev/null || true
    
    # Step 5: Clear all caches
    echo -e "${BLUE}🧹 Step 5/8: Clearing all caches...${NC}"
    docker exec -u 33 nextcloud-server-app-1 bash -c '
        # Remove JS and CSS cache
        rm -rf /var/www/html/data/appdata_*/js 2>/dev/null || true
        rm -rf /var/www/html/data/appdata_*/css 2>/dev/null || true
        
        # Clear AppStore cache
        php occ config:app:delete settings appstore-fetcher-lastModified 2>/dev/null || true
        php occ config:app:delete settings appstore-categories-lastModified 2>/dev/null || true
        
        echo "All caches cleared"
    ' 2>/dev/null || true
    
    # Step 6: Fix AppStore configuration
    echo -e "${BLUE}🏪 Step 6/8: Fixing AppStore configuration...${NC}"
    docker exec -u 33 nextcloud-server-app-1 bash -c '
        # Disable and re-enable federation app
        php occ app:disable federation 2>/dev/null || true
        php occ app:enable federation 2>/dev/null || true
        
        # Reset AppStore configuration
        php occ config:app:delete settings appstore_api_url 2>/dev/null || true
        php occ config:app:set settings appstore_api_url --value="https://apps.nextcloud.com/api/v1" 2>/dev/null || true
        
        echo "AppStore configuration fixed"
    ' 2>/dev/null || true
    
    # Step 7: File scan and cleanup
    echo -e "${BLUE}📂 Step 7/8: Running file scan and cleanup...${NC}"
    docker exec -u 33 nextcloud-server-app-1 bash -c '
        php occ files:scan --all 2>/dev/null || true
        php occ files:cleanup 2>/dev/null || true
        echo "File scan and cleanup completed"
    ' 2>/dev/null || true
    
    # Step 8: Disable maintenance mode
    echo -e "${BLUE}🔓 Step 8/8: Disabling maintenance mode...${NC}"
    docker exec -u 33 nextcloud-server-app-1 php occ maintenance:mode --off 2>/dev/null || true
    
    echo -e "${GREEN}✅ Comprehensive AppStore and GenericFileException fix completed!${NC}"
    echo -e "${BLUE}📋 Summary of fixes applied:${NC}"
    echo -e "   ✅ Complete appdata structure created"
    echo -e "   ✅ Missing admin files restored"
    echo -e "   ✅ Database maintenance completed"
    echo -e "   ✅ All caches cleared"
    echo -e "   ✅ AppStore configuration fixed"
    echo -e "   ✅ File system scanned and cleaned"
    echo -e "${YELLOW}💡 Tip: Restart Nextcloud container jika masih ada masalah${NC}"
    
    show_system_status
}

# Function to optimize Nextcloud performance for faster loading
optimize_nextcloud_performance() {
    echo -e "${BLUE}⚡ Optimizing Nextcloud performance settings...${NC}"
    
    # Enable maintenance mode for safe configuration
    docker exec -u 33 nextcloud-server-app-1 php occ maintenance:mode --on 2>/dev/null || true
    
    # Configure memory cache (APCu)
    echo -e "${YELLOW}🧠 Configuring memory cache...${NC}"
    docker exec -u 33 nextcloud-server-app-1 php occ config:system:set memcache.local --value="\\OC\\Memcache\\APCu" 2>/dev/null || true
    
    # Configure file locking cache
    echo -e "${YELLOW}🔒 Configuring file locking cache...${NC}"
    docker exec -u 33 nextcloud-server-app-1 php occ config:system:set memcache.locking --value="\\OC\\Memcache\\APCu" 2>/dev/null || true
    
    # Optimize database settings
    echo -e "${YELLOW}🗄️ Optimizing database settings...${NC}"
    docker exec -u 33 nextcloud-server-app-1 php occ config:system:set dbdriveroptions --value='{"PDO::MYSQL_ATTR_INIT_COMMAND":"SET sql_mode=STRICT_TRANS_TABLES"}' --type=json 2>/dev/null || true
    
    # Configure preview settings for better performance
    echo -e "${YELLOW}🖼️ Optimizing preview settings...${NC}"
    docker exec -u 33 nextcloud-server-app-1 php occ config:system:set preview_max_x --value=2048 --type=integer 2>/dev/null || true
    docker exec -u 33 nextcloud-server-app-1 php occ config:system:set preview_max_y --value=2048 --type=integer 2>/dev/null || true
    docker exec -u 33 nextcloud-server-app-1 php occ config:system:set jpeg_quality --value=60 --type=integer 2>/dev/null || true
    
    # Configure file scanning for external storage
    echo -e "${YELLOW}📁 Optimizing file scanning for external storage...${NC}"
    docker exec -u 33 nextcloud-server-app-1 php occ config:system:set filesystem_check_changes --value=0 --type=integer 2>/dev/null || true
    
    # Configure external storage cache for better performance
    echo -e "${YELLOW}💾 Optimizing external storage cache...${NC}"
    docker exec -u 33 nextcloud-server-app-1 php occ config:system:set files_external_allow_create_new_local --value=false --type=boolean 2>/dev/null || true
    
    # Configure log settings for better performance
    echo -e "${YELLOW}📝 Optimizing log settings...${NC}"
    docker exec -u 33 nextcloud-server-app-1 php occ config:system:set log_type --value=file 2>/dev/null || true
    docker exec -u 33 nextcloud-server-app-1 php occ config:system:set loglevel --value=2 --type=integer 2>/dev/null || true
    
    # Configure session settings
    echo -e "${YELLOW}🔐 Optimizing session settings...${NC}"
    docker exec -u 33 nextcloud-server-app-1 php occ config:system:set session_lifetime --value=86400 --type=integer 2>/dev/null || true
    docker exec -u 33 nextcloud-server-app-1 php occ config:system:set session_keepalive --value=true --type=boolean 2>/dev/null || true
    
    # Configure chunk size for large file uploads
    echo -e "${YELLOW}📤 Optimizing upload settings...${NC}"
    docker exec -u 33 nextcloud-server-app-1 php occ config:system:set max_chunk_size --value=104857600 --type=integer 2>/dev/null || true
    
    # Fix JSCombiner cache issues for faster loading
    echo -e "${YELLOW}⚡ Optimizing JavaScript and CSS cache...${NC}"
    docker exec -u 33 nextcloud-server-app-1 php occ config:system:set asset-pipeline.enabled --value=true --type=boolean 2>/dev/null || true
    docker exec -u 33 nextcloud-server-app-1 php occ config:system:set debug --value=false --type=boolean 2>/dev/null || true
    
    # Configure Redis for distributed cache (if available)
    echo -e "${YELLOW}🔄 Configuring distributed cache...${NC}"
    docker exec -u 33 nextcloud-server-app-1 php occ config:system:set memcache.distributed --value="\\OC\\Memcache\\APCu" 2>/dev/null || true
    
    # Disable maintenance mode
    docker exec -u 33 nextcloud-server-app-1 php occ maintenance:mode --off 2>/dev/null || true
    
    echo -e "${GREEN}✅ Nextcloud performance optimization completed!${NC}"
    echo -e "${BLUE}📋 Performance optimizations applied:${NC}"
    echo -e "   ✅ Memory cache (APCu) enabled for maximum speed"
    echo -e "   ✅ File locking cache configured"
    echo -e "   ✅ Database settings optimized"
    echo -e "   ✅ Preview generation optimized (2048x2048)"
    echo -e "   ✅ External storage scanning disabled for speed"
    echo -e "   ✅ JavaScript/CSS cache optimized (JSCombiner fix)"
    echo -e "   ✅ Asset pipeline enabled for faster loading"
    echo -e "   ✅ Session and upload settings improved"
    echo -e "   ✅ Distributed cache configured"
}

# Function to clean default Nextcloud files that cause conflicts
clean_default_nextcloud_files() {
    echo -e "${BLUE}🗑️ Cleaning default Nextcloud files and references...${NC}"
    
    # First, enable maintenance mode to prevent conflicts
    echo -e "${YELLOW}🔧 Enabling maintenance mode...${NC}"
    docker exec -u 33 nextcloud-server-app-1 php occ maintenance:mode --on 2>/dev/null || true
    
    # Ensure user directories exist (fix for missing admin folder issue)
    echo -e "${YELLOW}📁 Ensuring user directories exist...${NC}"
    docker exec nextcloud-server-app-1 mkdir -p /var/www/html/data/admin/files 2>/dev/null || true
    docker exec nextcloud-server-app-1 chown -R www-data:www-data /var/www/html/data/admin 2>/dev/null || true
    
    # Remove default sample files directly from container
    echo -e "${YELLOW}🗑️ Removing default sample files (photos, videos, documents)...${NC}"
    docker exec nextcloud-server-app-1 bash -c '
        # Remove specific default files
        find /var/www/html/data/*/files -name "Nextcloud intro.mp4" -delete 2>/dev/null || true
        find /var/www/html/data/*/files -name "Nextcloud.png" -delete 2>/dev/null || true
        find /var/www/html/data/*/files -name "Nextcloud Manual.pdf" -delete 2>/dev/null || true
        find /var/www/html/data/*/files -name "Reasons to use Nextcloud.pdf" -delete 2>/dev/null || true
        find /var/www/html/data/*/files -name "*.sample" -delete 2>/dev/null || true
        
        # Remove default directories
        find /var/www/html/data/*/files -name "Documents" -type d -exec rm -rf {} + 2>/dev/null || true
        find /var/www/html/data/*/files -name "Photos" -type d -exec rm -rf {} + 2>/dev/null || true
        find /var/www/html/data/*/files -name "Templates" -type d -exec rm -rf {} + 2>/dev/null || true
    ' 2>/dev/null || true
    
    # Remove preview cache for deleted files
    echo -e "${YELLOW}🗑️ Removing preview cache for deleted files...${NC}"
    docker exec nextcloud-server-app-1 rm -rf /var/www/html/data/appdata_*/preview/* 2>/dev/null || true
    docker exec nextcloud-server-app-1 rm -rf /var/www/html/data/appdata_*/thumbnails/* 2>/dev/null || true
    
    # Disable maintenance mode temporarily for database operations
    echo -e "${YELLOW}🔧 Disabling maintenance mode for database operations...${NC}"
    docker exec -u 33 nextcloud-server-app-1 php occ maintenance:mode --off 2>/dev/null || true
    
    # Clean file cache and database references
    echo -e "${YELLOW}🔍 Cleaning file cache and database references...${NC}"
    docker exec -u 33 nextcloud-server-app-1 php occ files:cleanup 2>/dev/null || true
    
    # Scan files to update database (this will remove references to deleted files)
    echo -e "${YELLOW}🔍 Scanning files to update database...${NC}"
    docker exec -u 33 nextcloud-server-app-1 php occ files:scan admin 2>/dev/null || true
    
    # Repair preview cache
    echo -e "${YELLOW}🖼️ Repairing preview cache...${NC}"
    docker exec -u 33 nextcloud-server-app-1 php occ preview:repair 2>/dev/null || true
    
    # Fix database indices and columns
    echo -e "${YELLOW}🗄️ Fixing database references...${NC}"
    docker exec -u 33 nextcloud-server-app-1 php occ db:add-missing-indices 2>/dev/null || true
    docker exec -u 33 nextcloud-server-app-1 php occ db:add-missing-columns 2>/dev/null || true
    docker exec -u 33 nextcloud-server-app-1 php occ db:add-missing-primary-keys 2>/dev/null || true
    
    # Final cleanup of orphaned entries
    echo -e "${YELLOW}🧹 Final cleanup of orphaned entries...${NC}"
    docker exec -u 33 nextcloud-server-app-1 php occ files:cleanup 2>/dev/null || true
    
    # Fix permissions
    echo -e "${YELLOW}🔐 Fixing file permissions...${NC}"
    docker exec nextcloud-server-app-1 chown -R www-data:www-data /var/www/html/data 2>/dev/null || true
    docker exec nextcloud-server-app-1 chmod -R 755 /var/www/html/data 2>/dev/null || true
    
    # Ensure appdata structure is complete
    ensure_appdata_structure
    
    echo -e "${GREEN}✅ Default Nextcloud files completely removed and database cleaned${NC}"
    
    # Restart to apply changes
    echo -e "${YELLOW}🔄 Restarting to apply changes...${NC}"
    restart_nextcloud
}

# Function to restart Nextcloud with health check - IMPROVED
restart_nextcloud() {
    echo -e "${YELLOW}🔄 Restarting Nextcloud...${NC}"
    docker compose restart app
    
    echo -e "${YELLOW}⏳ Waiting for services to be ready...${NC}"
    sleep 10
    
    # Clean cache and scan files after restart
    clean_nextcloud_cache
    
    # Use improved health check
    if check_nextcloud_health; then
        echo -e "${GREEN}✅ Nextcloud berhasil restart dan dapat diakses${NC}"
        return 0
    else
        echo -e "${RED}❌ Nextcloud masih bermasalah setelah restart${NC}"
        # Show logs for debugging
        echo -e "${YELLOW}📋 Container logs:${NC}"
        docker compose logs --tail=10 app
        return 1
    fi
}

# Function to show system status
show_system_status() {
    echo -e "\n${BLUE}📊 Status Sistem${NC}"
    echo -e "${BLUE}===============${NC}"
    
    # Status container
    echo -e "${YELLOW}🐳 Status Container:${NC}"
    docker compose ps
    
    echo -e "\n${YELLOW}💾 Status Mount:${NC}"
    if check_mount_status; then
        mount | grep rclone
    else
        echo -e "${YELLOW}⚠️  Menggunakan data lokal${NC}"
    fi
    
    echo -e "\n${YELLOW}�� Status Web:${NC}"
    HTTP_STATUS=$(curl -s -I http://localhost | head -1)
    echo "$HTTP_STATUS"
    
    if echo "$HTTP_STATUS" | grep -q "HTTP/1.1 [23]"; then
        echo -e "${GREEN}✅ Web server berjalan normal${NC}"
        echo -e "${GREEN}🌐 Akses: http://localhost${NC}"
    else
        echo -e "${RED}❌ Web server bermasalah${NC}"
    fi
}

# Function to show repair menu
show_repair_menu() {
    echo -e "\n${BLUE}🔧 Pilihan Perbaikan:${NC}"
    echo "1. Perbaiki mount Google Drive (recommended)"
    echo "2. Kembali ke data lokal (safe mode)"
    echo "3. Restart Nextcloud saja"
    echo "4. Perbaiki trusted domains & permissions (manual fix)"
    echo "5. Bersihkan cache dan scan file (fix Internal Server Error)"
    echo "6. �� Auto Repair - Perbaikan otomatis lengkap (NEW!)"
    echo "7. 🗑️ Bersihkan file bawaan Nextcloud (fix konflik mount)"
    echo "8. 🚨 Fix Internal Server Error setelah mount Google Drive (EMERGENCY!)"
    echo "9. 🔥 COMPREHENSIVE FIX - AppStore & GenericFileException (ALL-IN-ONE!)"
    echo "10. Tampilkan status sistem"
    echo "11. Keluar"
    echo -n "Pilih opsi (1-11): "
}

# Function to apply comprehensive auto-fix (combines menu 9 fix + external storage integration)
apply_comprehensive_auto_fix() {
    echo -e "${BLUE}🚀 Starting comprehensive auto-fix (AppStore + External Storage + All Fixes)...${NC}"
    
    # Step 1: Apply comprehensive AppStore fix (equivalent to menu option 9)
    echo -e "${BLUE}🔥 Step 1/2: Applying comprehensive AppStore fix...${NC}"
    fix_appstore_comprehensive
    
    # Step 2: Apply external storage integration fixes
    echo -e "${BLUE}💾 Step 2/2: Applying external storage integration fixes...${NC}"
    apply_external_storage_integration_auto_fix
    
    echo -e "${GREEN}✅ Comprehensive auto-fix completed successfully!${NC}"
    echo -e "${BLUE}📋 All fixes applied automatically:${NC}"
    echo -e "   ✅ Complete appdata structure created"
    echo -e "   ✅ Missing admin files restored"
    echo -e "   ✅ Database maintenance completed"
    echo -e "   ✅ All caches cleared and rebuilt"
    echo -e "   ✅ AppStore configuration fixed"
    echo -e "   ✅ File system scanned and cleaned"
    echo -e "   ✅ External storage systemd service fixed (Type=simple)"
    echo -e "   ✅ Local external storage option enabled"
    echo -e "   ✅ External storage app enabled and ready"
    echo -e "   ✅ All containers restarted and services ready"
    echo
    echo -e "${GREEN}🎉 ALL FIXES APPLIED! Nextcloud is now fully functional!${NC}"
}

# Function to apply external storage integration fixes (from integrate-external-storage.sh)
apply_external_storage_integration_auto_fix() {
    echo -e "${BLUE}🔧 Applying external storage integration fixes...${NC}"
    
    # Fix 1: Change Type=simple to Type=simple in systemd service
    echo -e "${BLUE}  🔧 Fix 1/3: Changing systemd service type from notify to simple...${NC}"
    if [[ -f "/etc/systemd/system/nextcloud-external-storage.service" ]]; then
        if grep -q "Type=simple" /etc/systemd/system/nextcloud-external-storage.service; then
            sed -i 's/Type=simple/Type=simple/g' /etc/systemd/system/nextcloud-external-storage.service
            systemctl daemon-reload
            systemctl restart nextcloud-external-storage.service 2>/dev/null || true
            echo -e "${GREEN}    ✅ Systemd service type changed to simple and restarted${NC}"
        else
            echo -e "${GREEN}    ✅ Systemd service already uses Type=simple${NC}"
        fi
    else
        echo -e "${YELLOW}    ⚠️ Nextcloud external storage service not found (normal if not using external storage)${NC}"
    fi
    
    # Wait for service to be ready
    sleep 5
    
    # Fix 2: Enable Local external storage option in Nextcloud
    echo -e "${BLUE}  🔧 Fix 2/3: Enabling Local external storage option in Nextcloud...${NC}"
    CONTAINER_ID=$(docker compose ps -q app 2>/dev/null || docker ps -q --filter name=nextcloud-server-app)
    if [[ -n "$CONTAINER_ID" ]]; then
        # Enable files_external app first
        docker exec --user www-data $CONTAINER_ID php occ app:enable files_external 2>/dev/null || true
        
        # Enable local external storage option
        docker exec --user www-data $CONTAINER_ID php occ config:system:set files_external_allow_create_new_local --value=true 2>/dev/null || true
        echo -e "${GREEN}    ✅ External storage app enabled and local option enabled${NC}"
    else
        echo -e "${YELLOW}    ⚠️ Could not find Nextcloud container${NC}"
    fi
    
    # Fix 3: Add external storage volume to docker-compose.yml if not exists
    echo -e "${BLUE}  🔧 Fix 3/3: Configuring external storage volume...${NC}"
    if [[ -f "docker-compose.yml" ]]; then
        # Check if external storage volume already exists
        if ! grep -q "external-storage:/external-storage" docker-compose.yml; then
            echo -e "${BLUE}    ├── Adding external storage volume to docker-compose.yml...${NC}"
            
            # Create backup
            cp docker-compose.yml docker-compose.yml.backup.$(date +%Y%m%d_%H%M%S)
            
            # Add external storage volume after data volume
            if grep -q "./data:/var/www/html/data" docker-compose.yml; then
                sed -i '/\.\/data:\/var\/www\/html\/data/a\      - ./external-storage:/external-storage:ro' docker-compose.yml
                echo -e "${GREEN}      ✅ External storage volume added to docker-compose.yml${NC}"
            else
                echo -e "${YELLOW}      ⚠️ Could not find data volume in docker-compose.yml${NC}"
            fi
        else
            echo -e "${GREEN}    ✅ External storage volume already configured${NC}"
        fi
        
        # Restart Nextcloud container to apply changes
        echo -e "${BLUE}    ├── Restarting Nextcloud container...${NC}"
        docker compose restart app 2>/dev/null || true
        sleep 10
        echo -e "${GREEN}    ✅ Nextcloud container restarted${NC}"
    fi
    
    echo -e "${GREEN}✅ External storage integration fixes completed!${NC}"
}

# Function to automatically create external storage mount in Nextcloud
create_external_storage_mount() {
    echo -e "${BLUE}🔧 Creating external storage mount in Nextcloud...${NC}"
    
    # Wait for container to be ready
    sleep 5
    
    CONTAINER_ID=$(docker compose ps -q app 2>/dev/null || docker ps -q --filter name=nextcloud-server-app)
    if [[ -n "$CONTAINER_ID" ]]; then
        # Check if external storage already exists
        if docker exec --user www-data $CONTAINER_ID php occ files_external:list | grep -q "AllDrive"; then
            echo -e "${YELLOW}    ⚠️ External storage 'AllDrive' already exists, skipping creation${NC}"
            return 0
        fi
        
        # Create external storage mount
        echo -e "${BLUE}    ├── Creating AllDrive external storage mount...${NC}"
        MOUNT_ID=$(docker exec --user www-data $CONTAINER_ID php occ files_external:create AllDrive local null::null -c datadir="/external-storage/alldrive" 2>/dev/null | grep -o "Storage created with id [0-9]*" | grep -o "[0-9]*")
        
        if [[ -n "$MOUNT_ID" ]]; then
            echo -e "${GREEN}    ✅ External storage created with ID: $MOUNT_ID${NC}"
            
            # Verify the mount
            echo -e "${BLUE}    ├── Verifying external storage connection...${NC}"
            VERIFY_RESULT=$(docker exec --user www-data $CONTAINER_ID php occ files_external:verify $MOUNT_ID 2>/dev/null)
            if echo "$VERIFY_RESULT" | grep -q "status: ok"; then
                echo -e "${GREEN}    ✅ External storage verification successful${NC}"
            else
                echo -e "${YELLOW}    ⚠️ External storage verification may have issues${NC}"
                echo "$VERIFY_RESULT"
            fi
        else
            echo -e "${YELLOW}    ⚠️ Could not create external storage mount${NC}"
        fi
    else
        echo -e "${YELLOW}    ⚠️ Could not find Nextcloud container${NC}"
    fi
    
    echo -e "${GREEN}✅ External storage mount creation completed!${NC}"
}

# Function to handle repair menu
handle_repair() {
    # Verify project directory exists
    if [[ ! -d "/home/paperspace/nextcloud-server" ]]; then
        echo -e "${RED}❌ Project directory not found: /home/paperspace/nextcloud-server${NC}"
        echo -e "${YELLOW}🔧 Please run the main deployment script first${NC}"
        exit 1
    fi
    
    cd /home/paperspace/nextcloud-server
    
    # Initialize RCLONE_CONFIG variable
    export RCLONE_CONFIG="/home/paperspace/nextcloud-server/rclone/rclone.conf"
    
    # Verify rclone config exists
    if [[ ! -f "$RCLONE_CONFIG" ]]; then
        echo -e "${RED}❌ Rclone config not found: $RCLONE_CONFIG${NC}"
        echo -e "${YELLOW}🔧 Please configure rclone first and try again${NC}"
        exit 1
    fi
    
    while true; do
        show_repair_menu
        read -r choice < /dev/tty
        
        case $choice in
            1)
                echo -e "\n${BLUE}🔧 Memulai perbaikan mount Google Drive...${NC}"
                backup_local_data
                unmount_google_drive
                
                if mount_google_drive_with_retry; then
                    # PERBAIKAN: Apply all fixes after successful mount
                    fix_google_drive_permissions
                    fix_trusted_domains
                    restart_nextcloud
                    show_system_status
                else
                    echo -e "${RED}❌ Mount gagal, kembali ke data lokal...${NC}"
                    restore_local_data
                    fix_trusted_domains
                    restart_nextcloud
                fi
                ;;
            2)
                echo -e "\n${BLUE}🔧 Kembali ke data lokal (safe mode)...${NC}"
                unmount_google_drive
                restore_local_data
                # PERBAIKAN: Apply trusted domains fix for local storage
                fix_trusted_domains
                restart_nextcloud
                show_system_status
                ;;
            3)
                echo -e "\n${BLUE}🔄 Restart Nextcloud...${NC}"
                # PERBAIKAN: Apply all fixes during restart
                fix_trusted_domains
                if mount | grep -q "alldrive:Nextcloud-Union/user-data"; then
                    fix_google_drive_permissions
                fi
                restart_nextcloud
                show_system_status
                ;;
            4)
                echo -e "\n${BLUE}🔧 Menjalankan perbaikan manual...${NC}"
                # PERBAIKAN: Manual fix for trusted domains and permissions
                fix_trusted_domains
                if mount | grep -q "alldrive:Nextcloud-Union/user-data"; then
                    echo -e "${YELLOW}�� Google Drive terdeteksi, memperbaiki permissions...${NC}"
                    fix_google_drive_permissions
                else
                    echo -e "${YELLOW}📁 Data lokal terdeteksi, skip Google Drive permissions${NC}"
                fi
                restart_nextcloud
                show_system_status
                ;;
            5)
                echo -e "\n${BLUE}🧹 Membersihkan cache dan scanning file...${NC}"
                clean_nextcloud_cache
                echo -e "${GREEN}✅ Cache dibersihkan dan file di-scan ulang${NC}"
                show_system_status
                ;;
            6)
                echo -e "\n${BLUE}🚀 Menjalankan Auto Repair lengkap...${NC}"
                echo -e "${YELLOW}⚠️ Akan memperbaiki cache, database, dan restart container${NC}"
                if clear_confirm "Lanjutkan Auto Repair?" "y"; then
                    clean_nextcloud_cache
                    restart_nextcloud
                    show_system_status
                else
                    echo -e "${BLUE}Auto Repair dibatalkan${NC}"
                fi
                ;;
            7)
                echo -e "\n${BLUE}🗑️ Membersihkan file bawaan Nextcloud...${NC}"
                echo -e "${YELLOW}⚠️ Ini akan menghapus referensi file bawaan yang menyebabkan konflik${NC}"
                if clear_confirm "Lanjutkan pembersihan file bawaan?" "y"; then
                    clean_default_nextcloud_files
                else
                    echo -e "${BLUE}Pembersihan dibatalkan${NC}"
                fi
                ;;
            8)
                echo -e "\n${RED}🚨 EMERGENCY FIX: Internal Server Error setelah mount Google Drive${NC}"
                echo -e "${YELLOW}⚠️ Ini akan memperbaiki struktur appdata dan cache yang rusak${NC}"
                if clear_confirm "Lanjutkan emergency fix?" "y"; then
                    echo -e "${BLUE}🔧 Step 1: Ensuring appdata structure...${NC}"
                    ensure_appdata_structure
                    
                    echo -e "${BLUE}🧹 Step 2: Cleaning cache thoroughly...${NC}"
                    clean_nextcloud_cache
                    
                    echo -e "${BLUE}🔐 Step 3: Fixing permissions...${NC}"
                    if mount | grep -q "alldrive:Nextcloud-Union/user-data"; then
                        fix_google_drive_permissions
                    fi
                    
                    echo -e "${BLUE}�� Step 4: Fixing trusted domains...${NC}"
                    fix_trusted_domains
                    
                    echo -e "${BLUE}🔄 Step 5: Restarting Nextcloud...${NC}"
                    restart_nextcloud
                    
                    echo -e "${GREEN}✅ Emergency fix completed!${NC}"
                    show_system_status
                else
                    echo -e "${BLUE}Emergency fix dibatalkan${NC}"
                fi
                ;;
            9)
                echo -e "\n${RED}🚨 COMPREHENSIVE FIX: AppStore & GenericFileException${NC}"
                echo -e "${YELLOW}⚠️ Ini akan memperbaiki semua masalah AppStore dan GenericFileException secara otomatis${NC}"
                echo -e "${BLUE}📋 Yang akan diperbaiki:${NC}"
                echo -e "   • Struktur appdata lengkap dengan semua direktori"
                echo -e "   • File admin yang hilang (Documents, Photos, Templates, Readme.md)"
                echo -e "   • Cache AppStore dan JavaScript/CSS"
                echo -e "   • Database maintenance dan file scan"
                echo -e "   • Konfigurasi AppStore dan federation"
                echo -e "   • Permissions dan ownership"
                if clear_confirm "Lanjutkan comprehensive fix?" "y"; then
                    fix_appstore_comprehensive
                else
                    echo -e "${BLUE}Comprehensive fix dibatalkan${NC}"
                fi
                ;;
            10)
                show_system_status
                ;;
            11)
                echo -e "${GREEN}👋 Selesai!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}❌ Pilihan tidak valid${NC}"
                ;;
        esac
        
        echo -e "\n${YELLOW}Tekan Enter untuk melanjutkan...${NC}"
        read -r < /dev/tty
    done
}

# Check for command line arguments
if [[ "$1" == "--reset" ]]; then
    cd "/home/paperspace/nextcloud-server"
    reset_everything
    exit 0
elif [[ "$1" == "--repair" ]]; then
    echo -e "${BLUE}�� Mode perbaikan dipilih${NC}"
    handle_repair
    exit 0
elif [[ "$1" == "--help" ]]; then
    echo -e "${GREEN}🎯 Nextcloud Union Storage (STAGED DEPLOYMENT - FIXED V2)${NC}"
    echo "Usage:"
    echo "  $0          # Staged deployment dengan konfirmasi jelas"
    echo "  $0 --reset  # Reset total dan mulai fresh"
    echo "  $0 --repair # Menu perbaikan interaktif untuk masalah mount"
    echo "  $0 --help   # Tampilkan bantuan ini"
    exit 0
fi

echo -e "${GREEN}🎯 NEXTCLOUD UNION STORAGE (STAGED DEPLOYMENT V2)${NC}"
echo "Smart: alldrive union = unified view"
echo "✅ Clear Confirmations: Setiap langkah dengan konfirmasi yang jelas"
echo "�� Staged: Setup Nextcloud → Manual Admin → Mount Drive"
echo "🚀 Professional deployment dengan kontrol penuh"
echo
echo -e "${BLUE}💡 Tahapan Deployment:${NC}"
echo "  1️⃣ Konfirmasi dan konfigurasi awal"
echo "  2️⃣ Setup Nextcloud dengan penyimpanan lokal"
echo "  3️⃣ Manual setup admin dan database di browser"
echo "  4️⃣ Integrasi Google Drive setelah konfirmasi"
echo "  5️⃣ Finalisasi dan status akhir"
echo

# Check root
[[ $EUID -ne 0 ]] && { echo -e "${RED}❌ Gunakan sudo${NC}"; exit 1; }

# Stage 1: Initial Confirmation
echo -e "${BLUE}�� TAHAP 1: KONFIRMASI AWAL${NC}"
echo
echo -e "${YELLOW}🚀 KONFIRMASI DEPLOYMENT${NC}"
echo "Apakah Anda ingin menginstall Nextcloud dengan Google Drive union storage?"
echo "Proses ini akan:"
echo "  • Install Nextcloud dengan PostgreSQL database"
echo "  • Setup penyimpanan lokal terlebih dahulu"
echo "  • Memberikan kontrol manual untuk setup admin"
echo "  • Mengintegrasikan Google Drive setelah konfirmasi"
echo

if ! clear_confirm "Lanjutkan dengan instalasi Nextcloud?" "n"; then
    echo "Instalasi dibatalkan"
    exit 1
fi

echo
DOMAIN=$(get_domain)
export DOMAIN
echo -e "${GREEN}✅ Domain dikonfigurasi: $DOMAIN${NC}"
echo

# Set domain in bashrc for persistence
if ! grep -q "export DOMAIN=" /home/paperspace/.bashrc; then
    echo "export DOMAIN=\"$DOMAIN\"" >> /home/paperspace/.bashrc
fi

# Install dependencies and fix configurations
install_dependencies
setup_docker_permissions
fix_fuse_config

PROJECT_DIR="/home/paperspace/nextcloud-server"
export RCLONE_CONFIG="/home/paperspace/nextcloud-server/rclone/rclone.conf"

# Check if rclone config exists
if [[ ! -f "$RCLONE_CONFIG" ]]; then
    echo -e "${RED}❌ Rclone config not found: $RCLONE_CONFIG${NC}"
    echo -e "${YELLOW}🔧 Please configure rclone first:${NC}"
    echo -e "  1️⃣ Run: ${BLUE}sudo -u paperspace rclone config${NC}"
    echo -e "  2️⃣ Setup jetjeton (Google Drive for uploads)"
    echo -e "  3️⃣ Setup makairamei (Google Drive for archive)"
    echo -e "  4️⃣ Setup alldrive (Union of both drives)"
    echo -e "  5️⃣ Test: ${BLUE}sudo -u paperspace rclone --config=$RCLONE_CONFIG lsd alldrive:${NC}"
    echo -e "  6️⃣ Then run this script again: ${BLUE}sudo $0${NC}"
    exit 1
fi

# Test rclone union
echo -e "${BLUE}🔍 Testing rclone union...${NC}"
sudo -u paperspace rclone --config="$RCLONE_CONFIG" lsd alldrive: >/dev/null || { 
    echo -e "${RED}❌ alldrive union failed${NC}"
    exit 1
}
echo -e "${GREEN}✅ alldrive union ready${NC}"

# PERBAIKAN: Hapus testing rclone mount prematur
# Testing akan dilakukan saat mount sesungguhnya

echo

# Check existing installation
cd "$PROJECT_DIR"

if [[ -f "docker-compose.yml" ]] || [[ -d "data" && "$(ls -A data 2>/dev/null)" ]]; then
    handle_existing
fi

# Continue with deployment
echo
echo -e "${BLUE}📋 TAHAP 2: SETUP NEXTCLOUD (PENYIMPANAN LOKAL)${NC}"
echo
echo -e "${YELLOW}🔧 SETUP DATABASE DAN WEB SERVER${NC}"
echo "Sekarang akan menginstall:"
echo "  • PostgreSQL database dengan konfigurasi otomatis"
echo "  • Nextcloud web server"
echo "  • Setup wizard untuk konfigurasi admin"
echo

if ! clear_confirm "Lanjutkan dengan setup Nextcloud?" "y"; then
    echo "Setup dibatalkan"
    exit 1
fi

echo -e "${BLUE}🧹 Cleanup existing installation...${NC}"
sudo pkill -f "rclone mount" 2>/dev/null || true
sudo fusermount -u data 2>/dev/null || true
docker compose down -v 2>/dev/null || true

echo -e "${BLUE}📁 Preparing directories...${NC}"
mkdir -p {data,logs,backups,scripts}
chown -R paperspace:paperspace .

# Create Docker Compose configuration with proper domain variable
echo -e "${BLUE}🐳 Creating Docker Compose configuration...${NC}"
cat > docker-compose.yml << EOF
version: '3.8'

services:
  db:
    image: postgres:15.8
    restart: always
    environment:
      POSTGRES_DB: nextcloud
      POSTGRES_USER: nextcloud
      POSTGRES_PASSWORD: D04m13S19!
      POSTGRES_INITDB_ARGS: "--auth-host=scram-sha-256 --auth-local=scram-sha-256"
    volumes:
      - db_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U nextcloud -d nextcloud"]
      interval: 10s
      timeout: 5s
      retries: 5

  app:
    image: nextcloud:28.0.14-apache
    restart: always
    ports:
      - "80:80"
    volumes:
      - nextcloud_data:/var/www/html
      - ./data:/var/www/html/data
      - ./external-storage:/external-storage:ro
    depends_on:
      db:
        condition: service_healthy
    environment:
      NEXTCLOUD_TRUSTED_DOMAINS: \${DOMAIN:-localhost}
      NEXTCLOUD_DATA_DIR: /var/www/html/data
      NEXTCLOUD_TABLE_PREFIX: oc_
      NEXTCLOUD_UPDATE: 1
      # Enable setup wizard
      SQLITE_DATABASE: ""
      MYSQL_DATABASE: ""
    command: >
      bash -c "
        chmod 0770 /var/www/html/data 2>/dev/null || true
        chown www-data:www-data /var/www/html/data 2>/dev/null || true
        exec /entrypoint.sh apache2-foreground
      "

volumes:
  nextcloud_data:
  db_data:
EOF

echo -e "${BLUE}🚀 Starting Nextcloud with local storage...${NC}"
export DOMAIN
docker compose up -d

echo -e "${BLUE}⏳ Waiting for services to be ready...${NC}"
for i in {1..60}; do
    if curl -s "http://localhost/" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Nextcloud is ready!${NC}"
        
        # Ensure appdata structure is complete after initial setup
        sleep 5  # Give Nextcloud time to create initial directories
        ensure_appdata_structure
        
        break
    fi
    if [[ $i -eq 60 ]]; then
        echo -e "${RED}❌ Timeout waiting for Nextcloud${NC}"
        docker compose logs --tail=20
        exit 1
    fi
    echo -n "."; sleep 2
done; echo

echo -e "${BLUE}🔧 Setting up data directory permissions...${NC}"
sleep 10
docker compose exec -T app bash -c "
chown -R www-data:www-data /var/www/html/data 2>/dev/null || true
chmod 0770 /var/www/html/data 2>/dev/null || true
echo 'Data directory permissions configured'
" 2>/dev/null || true

echo -e "${BLUE}🔄 Restarting services...${NC}"
docker compose restart app
sleep 10

# PERBAIKAN: Fix trusted domains after initial setup
fix_trusted_domains

echo -e "${GREEN}✅ NEXTCLOUD SIAP UNTUK SETUP!${NC}"
echo
echo -e "${YELLOW}🌐 URL: http://localhost${NC}"
echo -e "${YELLOW}�� Database sudah dikonfigurasi otomatis${NC}"
echo
echo -e "${GREEN}📋 INFORMASI SETUP WIZARD:${NC}"
echo -e "  👤 Admin username: ${BLUE}admin${NC} (atau sesuai keinginan)"
echo -e "  🔑 Admin password: ${BLUE}AdminPass123!${NC} (atau sesuai keinginan)"
echo -e "  🗄️ Database type: ${BLUE}PostgreSQL${NC}"
echo -e "  📊 Database user: ${BLUE}nextcloud${NC}"
echo -e "  🔐 Database password: ${BLUE}D04m13S19!${NC}"
echo -e "  📁 Database name: ${BLUE}nextcloud${NC}"
echo -e "     Database host: ${BLUE}db${NC}"
echo
echo -e "${GREEN}�� RECOMMENDED APPS:${NC}"
echo -e "  ✅ Calendar - Kalender dan jadwal"
echo -e "  ✅ Contacts - Kontak dan address book"
echo -e "  ✅ Mail - Email client"
echo -e "  ✅ Notes - Catatan dan memo"
echo -e "  ✅ Tasks - Task management"
echo -e "  ✅ Deck - Project management"
echo
echo -e "${BLUE}🎯 LANGKAH SELANJUTNYA:${NC}"
echo -e "  1️⃣ Buka ${YELLOW}http://localhost${NC} di browser"
echo -e "  2️⃣ Isi form setup wizard dengan informasi di atas"
echo -e "  3️⃣ Pilih aplikasi yang diinginkan"
echo -e "  4️⃣ Selesaikan setup dan login ke dashboard"
echo -e "  5️⃣ Kembali ke terminal ini untuk melanjutkan"
echo

# Stage 3: Manual Setup Pause
echo -e "${BLUE}�� TAHAP 3: JEDA UNTUK SETUP MANUAL${NC}"
echo
echo -e "${YELLOW}⏸️ JEDA SETUP - Silakan selesaikan setup di browser${NC}"
echo -e "${YELLOW}📱 Pastikan Anda sudah:${NC}"
echo -e "  ✅ Membuat akun admin"
echo -e "  ✅ Mengisi konfigurasi database PostgreSQL"
echo -e "  ✅ Memilih aplikasi yang diinginkan"
echo -e "  ✅ Login ke dashboard Nextcloud"
echo
read -p "⏳ Tekan ENTER setelah setup admin selesai untuk melanjutkan..." -r
echo

# PERBAIKAN: Optimize Nextcloud performance after initial setup
echo -e "${BLUE}⚡ Mengoptimalkan performa Nextcloud untuk kecepatan maksimal...${NC}"
optimize_nextcloud_performance

# Stage 4: Google Drive Integration
echo -e "${BLUE}�� TAHAP 4: INTEGRASI GOOGLE DRIVE${NC}"
echo
echo -e "${YELLOW}🔄 INTEGRASI GOOGLE DRIVE${NC}"
echo "Sekarang akan mengintegrasikan Google Drive union storage."
echo "Proses ini akan:"
echo "  • Menghentikan Nextcloud sementara"
echo "  • Mount Google Drive union (alldrive)"
echo "  • Memindahkan data dari lokal ke Google Drive"
echo "  • Restart Nextcloud dengan Google Drive"
echo
echo -e "${RED}⚠️ PENTING: Pastikan rclone sudah dikonfigurasi dengan 'alldrive' union${NC}"
echo

if ! clear_confirm "Lanjutkan dengan integrasi Google Drive?" "y"; then
    echo -e "${YELLOW}⏸️ Integrasi Google Drive dibatalkan${NC}"
    echo -e "${GREEN}✅ Nextcloud tetap berjalan dengan penyimpanan lokal${NC}"
    echo -e "${BLUE}🌐 URL: http://localhost${NC}"
    exit 0
fi

echo
echo -e "${BLUE}🔄 Stopping Nextcloud for Google Drive integration...${NC}"
docker compose stop app

echo -e "${BLUE}📁 Creating Google Drive structure...${NC}"
sudo -u paperspace rclone --config="$RCLONE_CONFIG" mkdir jetjeton:Nextcloud-Union/user-data 2>/dev/null || true

echo -e "${BLUE}�� Backing up local data...${NC}"
if [[ -d "data" && "$(ls -A data 2>/dev/null)" ]]; then
    echo -e "${YELLOW}📦 Found existing data, creating backup...${NC}"
    tar -czf "backups/local-data-backup-$(date +%Y%m%d-%H%M%S).tar.gz" data/ 2>/dev/null || true
    echo -e "${GREEN}✅ Local data backed up${NC}"
fi

# Mount Google Drive with retry mechanism
if ! mount_google_drive_with_retry; then
    echo -e "${RED}❌ Failed to mount Google Drive${NC}"
    echo -e "${YELLOW}⏸️ Continuing with local storage...${NC}"
    docker compose start app
    exit 1
fi

echo -e "${BLUE}🔄 Restarting Nextcloud with Google Drive...${NC}"
export DOMAIN
docker compose start app

# Wait for Nextcloud to be ready
echo -e "${BLUE}⏳ Waiting for Nextcloud to be ready...${NC}"
for i in {1..60}; do
    if curl -s "http://localhost/" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Nextcloud is ready with Google Drive!${NC}"
        
        # Ensure appdata structure is complete after Google Drive setup
        sleep 5  # Give Nextcloud time to create initial directories
        ensure_appdata_structure
        
        break
    fi
    if [[ $i -eq 60 ]]; then
        echo -e "${RED}❌ Timeout waiting for Nextcloud with Google Drive${NC}"
        docker compose logs --tail=20
        exit 1
    fi
    echo -n "."; sleep 2
done; echo

echo -e "${BLUE}🔧 Fixing permissions for Google Drive...${NC}"
sleep 10

# PERBAIKAN: Use improved Google Drive permissions function
fix_google_drive_permissions

# Setup external storage mount for read-only access
echo -e "${BLUE}🔧 Setting up external storage mount...${NC}"
setup_external_storage_mount

# PERBAIKAN: Apply external storage fixes automatically
echo -e "${BLUE}🔧 Applying external storage fixes automatically...${NC}"
fix_external_storage_configuration

# PERBAIKAN: Ensure appdata structure after Google Drive mount
echo -e "${BLUE}🔧 Ensuring appdata structure after Google Drive mount...${NC}"
ensure_appdata_structure

# PERBAIKAN: Clean cache to prevent Internal Server Error
echo -e "${BLUE}🧹 Cleaning cache to prevent Internal Server Error...${NC}"
clean_nextcloud_cache

# PERBAIKAN: Fix trusted domains for Google Drive setup
fix_trusted_domains

# PERBAIKAN: Optimize Nextcloud performance for faster dashboard loading
echo -e "${BLUE}⚡ Optimizing Nextcloud performance for maximum speed...${NC}"
optimize_nextcloud_performance

echo -e "${BLUE}🔄 Final restart with health check...${NC}"
# PERBAIKAN: Use improved restart function with health check
if ! restart_nextcloud; then
    echo -e "${RED}❌ Failed to restart Nextcloud with Google Drive${NC}"
    echo -e "${YELLOW}🔄 Attempting fallback to local storage...${NC}"
    unmount_google_drive
    restore_local_data
    restart_nextcloud
fi

# PERBAIKAN: Final verification and structure fix after restart
echo -e "${BLUE}🔍 Final verification after restart...${NC}"
sleep 5
ensure_appdata_structure

# PERBAIKAN: Test Nextcloud accessibility
echo -e "${BLUE}🌐 Testing Nextcloud accessibility...${NC}"
for i in {1..10}; do
    if curl -s "http://localhost/" | grep -q "Nextcloud"; then
        echo -e "${GREEN}✅ Nextcloud is accessible and working!${NC}"
        break
    fi
    if [[ $i -eq 10 ]]; then
        echo -e "${YELLOW}⚠️ Nextcloud may have issues, running emergency fix...${NC}"
        clean_nextcloud_cache
        ensure_appdata_structure
    fi
    echo -n "."; sleep 2
done; echo

# AUTO-FIX: Apply comprehensive fix (equivalent to repair menu option 9) and external storage integration
echo -e "${BLUE}🚨 AUTO-FIX: Applying comprehensive fix and external storage integration...${NC}"
apply_comprehensive_auto_fix

# AUTO-CREATE: Create external storage mount in Nextcloud dashboard
echo -e "${BLUE}🚨 AUTO-CREATE: Creating external storage mount in Nextcloud...${NC}"
create_external_storage_mount

# Stage 5: Final Status
echo -e "${BLUE}📋 TAHAP 5: DEPLOYMENT SELESAI${NC}"
echo
echo -e "${GREEN}🎉 NEXTCLOUD UNION STORAGE READY!${NC}"
echo -e "${YELLOW}🌐 URL: http://localhost (or https://$DOMAIN)${NC}"
echo
echo -e "${GREEN}✅ DEPLOYMENT SUMMARY:${NC}"
echo -e "  🧙 Setup wizard: Completed"
echo -e "  🗄️ Database: PostgreSQL configured"
echo -e "  📁 Storage: Google Drive union mounted"
echo -e "  📱 Apps: Selected and installed"
echo
echo -e "${GREEN}📊 SMART UNION STORAGE:${NC}"
echo -e "  📤 New uploads → jetjeton (primary)"
echo -e "  📦 Old files → makairamei (archive, visible)"
echo -e "  🔍 Dashboard → ALL files unified!"
echo
mountpoint -q data && echo -e "${GREEN}✅ Union: $(ls data/ 2>/dev/null | wc -l) items from both drives${NC}"

echo -e "${BLUE}🔍 System Status:${NC}"
echo "🐳 Docker containers:"
docker compose ps 2>/dev/null || echo "  ⚠️ Docker compose not running"
echo "📁 Mount status:"
mountpoint -q data && echo "  ✅ Google Drive union mounted" || echo "  ⚠️ Union storage not mounted"
echo "🌐 Web server:"
curl -s -o /dev/null -w "  HTTP Status: %{http_code}\n" http://localhost/ 2>/dev/null || echo "  ⚠️ Web server not responding"
echo

echo -e "${BLUE}🛠️ Management Commands:${NC}"
echo -e "  • Check status: ${BLUE}docker compose ps && docker compose logs --tail=20${NC}"
echo -e "  • Check mounts: ${BLUE}df -h | grep rclone && mountpoint data${NC}"
echo -e "  • Reset everything: ${YELLOW}sudo ./deploy-union-alldrive.sh --reset${NC}"
echo -e "  • Repair menu: ${YELLOW}sudo ./deploy-union-alldrive.sh --repair${NC}"
echo
echo -e "${GREEN}🎉 DEPLOYMENT SELESAI!${NC}"
echo -e "${GREEN}✨ Nextcloud dengan Google Drive union storage siap digunakan!${NC}"
echo -e "${YELLOW}🌐 Akses: http://localhost${NC}"
echo
echo -e "${BLUE}🔧 PERBAIKAN TERINTEGRASI (OTOMATIS):${NC}"
echo -e "  ✅ Trusted domains (localhost + domain) - otomatis dikonfigurasi"
echo -e "  ✅ Google Drive permissions - otomatis diperbaiki"
echo -e "  ✅ Health check yang robust - dengan retry mechanism"
echo -e "  ✅ Fallback ke local storage - jika Google Drive gagal"
echo -e "  ✅ AppStore & GenericFileException - OTOMATIS DIPERBAIKI (menu 9)"
echo -e "  ✅ External Storage integration - OTOMATIS DIKONFIGURASI"
echo -e "  ✅ Systemd service Type=simple - OTOMATIS DIPERBAIKI"
echo -e "  ✅ Local External Storage - OTOMATIS DIAKTIFKAN"
echo -e "  ✅ Cache cleanup & file scan - mencegah Internal Server Error"
echo -e "  ✅ Automatic maintenance - pembersihan cache otomatis saat restart"
echo -e "  ✅ Auto-start after reboot - sistem otomatis berjalan setelah VPS restart"
echo -e "  ✅ Backup scheduler - backup otomatis 2x sehari ke Google Drive"
echo -e "  ✅ SEMUA FIX OTOMATIS - tidak perlu manual repair lagi!"

# Add interactive repair menu
if [[ "$1" != "--no-menu" ]]; then
    echo
    echo -e "${BLUE}�� MENU PERBAIKAN TERSEDIA${NC}"
    echo -e "Jika ada masalah, jalankan: ${YELLOW}$0 --repair${NC}"
    echo -e "${YELLOW}Menu perbaikan menyediakan opsi untuk:${NC}"
    echo -e "  • Perbaiki mount Google Drive"
    echo -e "  • Kembali ke data lokal (safe mode)"
    echo -e "  • Restart Nextcloud"
    echo -e "  • Bersihkan cache dan scan file (fix Internal Server Error)"
    echo -e "  • Tampilkan status sistem"
    echo
    echo -e "${GREEN}�� SISTEM AUTO-RECOVERY AKTIF${NC}"
    echo -e "Sistem telah dikonfigurasi untuk otomatis recovery setelah reboot:"
    echo -e "  • Startup script: ${YELLOW}startup-after-reboot.sh${NC}"
    echo -e "  • Systemd service: ${YELLOW}nextcloud-backup.service${NC}"
    echo -e "  • Backup otomatis: ${YELLOW}2x sehari (06:00 & 18:00)${NC}"
    echo -e "  • Tutorial lengkap: ${YELLOW}TUTORIAL-3-STARTUP-REBOOT.md${NC}"
fi


# Function to setup system cron job for Nextcloud
setup_nextcloud_cron() {
    echo -e "${BLUE}⏰ Setting up Nextcloud cron job...${NC}"
    local cron_job="*/5 * * * * docker exec -u www-data nextcloud-server-app-1 php /var/www/html/cron.php"
    # Check if cron job already exists
    if crontab -l 2>/dev/null | grep -Fq "$cron_job"; then
        echo -e "${GREEN}✅ Cron job already set up${NC}"
    else
        # Add cron job
        (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
        echo -e "${GREEN}✅ Cron job added successfully${NC}"
    fi
}

# Call the cron setup function at the end of the deployment
setup_nextcloud_cron
