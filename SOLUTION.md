# 🚨 SOLUSI UNTUK DEPLOY SCRIPT YANG HANG

## Root Cause Analysis

Script `deploy-union-alldrive.sh` hang pada bagian **"🔧 Setting up external storage mount..."** karena beberapa masalah:

### 1. **Infinite Wait Loops Tanpa Timeout**
```bash
# Problematic code di line 490-503:
while [[ $wait_count -lt 30 ]]; do
    if mountpoint -q external-storage/alldrive; then
        # Mount berhasil
        return 0
    fi
    sleep 2
    ((wait_count++))
done
```
**Masalah**: Loop ini bisa jalan forever jika mount tidak pernah berhasil.

### 2. **Docker Commands Tanpa Timeout**
```bash
# Problematic code di line 1204:
docker exec --user www-data $CONTAINER_ID php occ files_external:list
```
**Masalah**: Command ini bisa hang jika container sedang busy atau bermasalah.

### 3. **Race Conditions**
Script mencoba setup external storage sementara container Nextcloud mungkin belum fully ready.

### 4. **Systemd Service Issues**
Service `nextcloud-external-storage` mungkin fail start tapi script tetap wait.

## 🔧 IMMEDIATE FIX (Untuk Situation Sekarang)

### Step 1: Kill Hanging Process
```bash
# Kill semua proses yang mungkin hang
sudo pkill -f "rclone mount" 2>/dev/null || true
sudo pkill -f "occ files_external" 2>/dev/null || true
sudo pkill -f "deploy-union-alldrive" 2>/dev/null || true
```

### Step 2: Reset Services
```bash
# Stop problematic services
sudo systemctl stop nextcloud-external-storage 2>/dev/null || true
sudo systemctl disable nextcloud-external-storage 2>/dev/null || true

# Unmount stuck mounts
sudo fusermount -u data 2>/dev/null || true
sudo fusermount -u external-storage/alldrive 2>/dev/null || true
```

### Step 3: Restart Nextcloud
```bash
# Navigate ke directory Nextcloud (adjust path jika berbeda)
cd /home/paperspace/nextcloud-server

# Restart containers
docker compose down
sleep 5
docker compose up -d

# Wait dan test
sleep 30
curl -I http://localhost/
```

## 🛠️ PERMANENT FIXES

### Fix 1: Replace `setup_external_storage_mount()` Function

Ganti function di script dengan versi yang ada timeout:

```bash
setup_external_storage_mount() {
    echo -e "${BLUE}🔧 Setting up external storage mount...${NC}"
    
    # FIXED: Stop existing service first with timeout
    timeout 10 sudo systemctl stop nextcloud-external-storage 2>/dev/null || true
    
    # FIXED: Wait with proper timeout (max 60 seconds)
    local wait_count=0
    local max_wait=30  # 60 seconds total
    
    while [[ $wait_count -lt $max_wait ]]; do
        if sudo systemctl is-active --quiet nextcloud-external-storage; then
            if mountpoint -q external-storage/alldrive 2>/dev/null; then
                echo -e "${GREEN}✅ External storage mounted successfully!${NC}"
                return 0
            fi
        else
            echo -e "${YELLOW}⚠️ Service failed, breaking loop${NC}"
            break
        fi
        
        echo -n "."
        sleep 2
        ((wait_count++))
    done
    
    echo -e "${RED}❌ External storage mount failed or timed out${NC}"
    return 1
}
```

### Fix 2: Replace `create_external_storage_mount()` Function

```bash
create_external_storage_mount() {
    echo -e "${BLUE}🔧 Creating external storage mount in Nextcloud...${NC}"
    
    # FIXED: Add timeout to docker commands
    CONTAINER_ID=$(timeout 10 docker compose ps -q app 2>/dev/null)
    
    if [[ -z "$CONTAINER_ID" ]]; then
        echo -e "${RED}❌ Could not find container within timeout${NC}"
        return 1
    fi
    
    # FIXED: Check existing with timeout
    if timeout 15 docker exec --user www-data $CONTAINER_ID php occ files_external:list 2>/dev/null | grep -q "AllDrive"; then
        echo -e "${YELLOW}⚠️ External storage already exists${NC}"
        return 0
    fi
    
    # FIXED: Create with timeout
    MOUNT_RESULT=$(timeout 30 docker exec --user www-data $CONTAINER_ID php occ files_external:create AllDrive local null::null -c datadir="/external-storage/alldrive" 2>&1)
    
    if [[ $? -eq 124 ]]; then
        echo -e "${RED}❌ Creation timed out${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✅ External storage setup completed${NC}"
}
```

### Fix 3: Add Emergency Recovery Function

```bash
emergency_recovery() {
    echo -e "${RED}🚨 EMERGENCY RECOVERY${NC}"
    
    # Kill all related processes
    sudo pkill -f "rclone mount" 2>/dev/null || true
    sudo pkill -f "occ files_external" 2>/dev/null || true
    
    # Unmount everything
    sudo fusermount -u data 2>/dev/null || true
    sudo fusermount -u external-storage/alldrive 2>/dev/null || true
    
    # Restart containers
    docker compose down && sleep 5 && docker compose up -d
    
    # Wait for recovery
    for i in {1..30}; do
        if curl -s http://localhost/ | grep -q "Nextcloud"; then
            echo -e "${GREEN}✅ Recovery successful${NC}"
            return 0
        fi
        sleep 2
    done
}
```

## 📋 STEP-BY-STEP RECOVERY GUIDE

### 1. **Immediate Recovery** (Untuk sekarang)
```bash
# Run emergency fix
chmod +x immediate-fix.sh
./immediate-fix.sh
```

### 2. **Test Nextcloud Access**
```bash
# Check if web interface working
curl -I http://localhost/
# atau buka di browser: http://your-domain/
```

### 3. **Apply Permanent Fixes**
```bash
# Backup original script
cp deploy-union-alldrive.sh deploy-union-alldrive.sh.backup

# Apply the fixes manually atau gunakan fixed script
# File: deploy-union-alldrive-fixed.sh sudah tersedia
```

### 4. **Re-run Deployment** (Optional)
```bash
# Jika ingin setup Google Drive lagi
./deploy-union-alldrive-fixed.sh
```

## 🔍 TROUBLESHOOTING

### Jika masih Internal Server Error:
```bash
# Check container logs
docker compose logs app

# Check Nextcloud logs
docker exec -it nextcloud-server-app-1 tail -f /var/www/html/data/nextcloud.log

# Reset cache
docker exec --user www-data nextcloud-server-app-1 php occ maintenance:repair
```

### Jika Google Drive mount bermasalah:
```bash
# Check rclone config
rclone config show

# Test manual mount
rclone mount alldrive: /tmp/test --daemon
```

## ✅ VERIFICATION

Setelah fix, pastikan:
1. ✅ Nextcloud web interface accessible
2. ✅ No hanging processes (`ps aux | grep rclone`)
3. ✅ No error logs in Docker (`docker compose logs`)
4. ✅ Internal Server Error resolved

## 🎯 KESIMPULAN

**Root cause**: Script hang karena infinite loops tanpa timeout di external storage setup.

**Solution**: 
1. Kill hanging processes (immediate)
2. Add timeouts ke semua Docker commands
3. Improve error handling dan recovery mechanisms
4. Add emergency recovery functions

Script yang sudah diperbaiki ada di: `deploy-union-alldrive-fixed.sh`