#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${RED}🚨 EMERGENCY FIX FOR HANGING DEPLOY SCRIPT${NC}"
echo -e "${BLUE}This script will resolve the stuck deployment at 'Setting up external storage mount...'${NC}"
echo

# Step 1: Kill hanging processes
echo -e "${BLUE}Step 1: Killing hanging processes...${NC}"
sudo pkill -f "rclone mount" 2>/dev/null || true
sudo pkill -f "occ files_external" 2>/dev/null || true
echo -e "${GREEN}✅ Processes killed${NC}"

# Step 2: Stop problematic services
echo -e "${BLUE}Step 2: Stopping problematic services...${NC}"
sudo systemctl stop nextcloud-external-storage 2>/dev/null || true
sudo systemctl disable nextcloud-external-storage 2>/dev/null || true
echo -e "${GREEN}✅ Services stopped${NC}"

# Step 3: Unmount any stuck mounts
echo -e "${BLUE}Step 3: Unmounting stuck mounts...${NC}"
cd /home/paperspace/nextcloud-server 2>/dev/null || cd /workspace
sudo fusermount -u data 2>/dev/null || true
sudo fusermount -u external-storage/alldrive 2>/dev/null || true
sudo umount data 2>/dev/null || true
sudo umount external-storage/alldrive 2>/dev/null || true
echo -e "${GREEN}✅ Mounts cleaned${NC}"

# Step 4: Restart Docker Compose
echo -e "${BLUE}Step 4: Restarting Nextcloud containers...${NC}"
docker compose down 2>/dev/null || true
sleep 5
docker compose up -d 2>/dev/null || true
echo -e "${GREEN}✅ Containers restarted${NC}"

# Step 5: Wait for Nextcloud to be ready
echo -e "${BLUE}Step 5: Waiting for Nextcloud to be ready...${NC}"
for i in {1..30}; do
    if curl -s http://localhost/ 2>/dev/null | grep -q "Nextcloud"; then
        echo -e "${GREEN}✅ Nextcloud is ready!${NC}"
        break
    fi
    if [[ $i -eq 30 ]]; then
        echo -e "${YELLOW}⚠️ Nextcloud may still be starting...${NC}"
    fi
    echo -n "."
    sleep 2
done
echo

# Step 6: Test access
echo -e "${BLUE}Step 6: Testing Nextcloud access...${NC}"
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/ 2>/dev/null || echo "000")
if [[ "$HTTP_STATUS" == "200" ]] || [[ "$HTTP_STATUS" == "302" ]]; then
    echo -e "${GREEN}✅ Nextcloud is accessible! (HTTP $HTTP_STATUS)${NC}"
    echo -e "${BLUE}🌐 Your Nextcloud should now be working without the Google Drive mount${NC}"
else
    echo -e "${YELLOW}⚠️ Nextcloud might still be starting (HTTP $HTTP_STATUS)${NC}"
fi

echo
echo -e "${BLUE}📋 NEXT STEPS:${NC}"
echo -e "1. Check if your Nextcloud web interface is working"
echo -e "2. If working, you can try to re-run the deploy script with the fixed version"
echo -e "3. Or manually set up Google Drive mount later using the repair menu"
echo
echo -e "${YELLOW}⚠️ IMPORTANT: The hanging was caused by:${NC}"
echo -e "   • Docker commands without timeouts"
echo -e "   • Infinite wait loops in external storage setup"
echo -e "   • Race conditions between services"
echo
echo -e "${GREEN}✅ Emergency fix completed!${NC}"