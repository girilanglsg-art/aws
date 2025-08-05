#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# FIXED: Function to setup external storage mount with proper timeouts
setup_external_storage_mount() {
    echo -e "${BLUE}🔧 Setting up external storage mount...${NC}"
    
    # Create external storage directory
    mkdir -p external-storage/alldrive
    
    # Fix permissions on external-storage directory before mounting
    sudo chown -R paperspace:paperspace external-storage/
    chmod -R 755 external-storage/

    # FIXED: Stop any existing service first
    echo -e "${YELLOW}🛑 Stopping existing external storage service...${NC}"
    sudo systemctl stop nextcloud-external-storage 2>/dev/null || true
    sudo systemctl disable nextcloud-external-storage 2>/dev/null || true
    
    # FIXED: Kill any hanging rclone processes
    sudo pkill -f "rclone mount.*external-storage/alldrive" 2>/dev/null || true
    sudo fusermount -u external-storage/alldrive 2>/dev/null || true
    sleep 3

    # Create systemd service for external storage mount with FIXED timeout settings
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
Restart=on-failure
RestartSec=15
TimeoutStartSec=60
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd and start service
    sudo systemctl daemon-reload
    sudo systemctl enable nextcloud-external-storage
    sudo systemctl start nextcloud-external-storage
    
    # FIXED: Wait for mount to be ready with proper timeout and error checking
    echo -e "${BLUE}⏳ Waiting for external storage mount (max 60 seconds)...${NC}"
    local wait_count=0
    local max_wait=30  # 60 seconds total (30 * 2)
    
    while [[ $wait_count -lt $max_wait ]]; do
        # Check if service is active
        if sudo systemctl is-active --quiet nextcloud-external-storage; then
            # Check if mount point exists
            if mountpoint -q external-storage/alldrive 2>/dev/null; then
                echo -e "${GREEN}✅ External storage mounted successfully!${NC}"
                
                # Set proper permissions
                sudo chown -R paperspace:paperspace external-storage/
                chmod -R 755 external-storage/
                
                return 0
            fi
        else
            echo -e "${YELLOW}⚠️ Service failed, checking status...${NC}"
            sudo systemctl status nextcloud-external-storage --no-pager --lines=5
            break
        fi
        
        echo -n "."
        sleep 2
        ((wait_count++))
    done
    
    echo -e "${RED}❌ External storage mount failed or timed out after 60 seconds${NC}"
    echo -e "${YELLOW}🔍 Service status:${NC}"
    sudo systemctl status nextcloud-external-storage --no-pager --lines=10
    
    echo -e "${YELLOW}🔍 Last 10 lines of rclone log:${NC}"
    tail -n 10 logs/external-storage.log 2>/dev/null || echo "No log file found"
    
    return 1
}

# FIXED: Function to create external storage mount with timeout protection
create_external_storage_mount() {
    echo -e "${BLUE}🔧 Creating external storage mount in Nextcloud (with timeout protection)...${NC}"
    
    # Wait for container to be ready
    sleep 5
    
    # FIXED: Add timeout to docker commands
    CONTAINER_ID=$(timeout 10 docker compose ps -q app 2>/dev/null || timeout 10 docker ps -q --filter name=nextcloud-server-app 2>/dev/null)
    
    if [[ -z "$CONTAINER_ID" ]]; then
        echo -e "${RED}❌ Could not find Nextcloud container within timeout${NC}"
        return 1
    fi
    
    # Check if external storage already exists with timeout
    echo -e "${BLUE}    ├── Checking existing external storage...${NC}"
    if timeout 15 docker exec --user www-data $CONTAINER_ID php occ files_external:list 2>/dev/null | grep -q "AllDrive"; then
        echo -e "${YELLOW}    ⚠️ External storage 'AllDrive' already exists, skipping creation${NC}"
        return 0
    fi
    
    # Create external storage mount with timeout
    echo -e "${BLUE}    ├── Creating AllDrive external storage mount...${NC}"
    MOUNT_RESULT=$(timeout 30 docker exec --user www-data $CONTAINER_ID php occ files_external:create AllDrive local null::null -c datadir="/external-storage/alldrive" 2>&1)
    
    if [[ $? -eq 124 ]]; then
        echo -e "${RED}❌ External storage creation timed out after 30 seconds${NC}"
        return 1
    fi
    
    MOUNT_ID=$(echo "$MOUNT_RESULT" | grep -o "Storage created with id [0-9]*" | grep -o "[0-9]*")
    
    if [[ -n "$MOUNT_ID" ]]; then
        echo -e "${GREEN}    ✅ External storage created with ID: $MOUNT_ID${NC}"
        
        # Verify the mount with timeout
        echo -e "${BLUE}    ├── Verifying external storage connection...${NC}"
        VERIFY_RESULT=$(timeout 20 docker exec --user www-data $CONTAINER_ID php occ files_external:verify $MOUNT_ID 2>/dev/null)
        
        if [[ $? -eq 124 ]]; then
            echo -e "${YELLOW}    ⚠️ External storage verification timed out${NC}"
        elif echo "$VERIFY_RESULT" | grep -q "status: ok"; then
            echo -e "${GREEN}    ✅ External storage verification successful${NC}"
        else
            echo -e "${YELLOW}    ⚠️ External storage verification may have issues${NC}"
            echo "$VERIFY_RESULT"
        fi
    else
        echo -e "${YELLOW}    ⚠️ Could not create external storage mount${NC}"
        echo "Error output: $MOUNT_RESULT"
        return 1
    fi
    
    echo -e "${GREEN}✅ External storage mount creation completed!${NC}"
    return 0
}

# FIXED: Emergency recovery function
emergency_recovery() {
    echo -e "${RED}🚨 EMERGENCY RECOVERY MODE ACTIVATED${NC}"
    
    # Stop all problematic services
    sudo systemctl stop nextcloud-external-storage 2>/dev/null || true
    sudo pkill -f "rclone mount" 2>/dev/null || true
    
    # Unmount everything
    sudo fusermount -u data 2>/dev/null || true
    sudo fusermount -u external-storage/alldrive 2>/dev/null || true
    sudo umount data 2>/dev/null || true
    sudo umount external-storage/alldrive 2>/dev/null || true
    
    # Restart Docker Compose
    echo -e "${BLUE}🔄 Restarting Docker Compose...${NC}"
    docker compose down
    sleep 5
    docker compose up -d
    
    # Wait for Nextcloud to be ready
    echo -e "${BLUE}⏳ Waiting for Nextcloud to recover...${NC}"
    for i in {1..30}; do
        if curl -s http://localhost/ | grep -q "Nextcloud" 2>/dev/null; then
            echo -e "${GREEN}✅ Nextcloud recovered successfully!${NC}"
            return 0
        fi
        echo -n "."
        sleep 2
    done
    
    echo -e "${RED}❌ Recovery failed${NC}"
    return 1
}

echo -e "${BLUE}🚀 FIXED DEPLOY SCRIPT - Use these functions to replace the problematic ones${NC}"
echo -e "${YELLOW}Key improvements:${NC}"
echo -e "  • Added proper timeouts to all Docker commands"
echo -e "  • Improved error handling and logging"
echo -e "  • Added emergency recovery function"
echo -e "  • Fixed systemd service configuration"
echo -e "  • Better mount point validation"