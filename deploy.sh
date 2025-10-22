#!/bin/bash
# DevOps Stage 1 Task – Automated Deployment Script
# Author: deeexo
# Description: Clones a repo, connects to a remote server via SSH,
# installs Docker + Nginx, deploys app container, and configures proxy.

set -euo pipefail

#==============================#
#          LOGGING             #
#==============================#
LOG_FILE="deploy_$(date +%Y%m%d_%H%M%S).log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

trap 'log "❌ ERROR: Deployment failed at line $LINENO."' ERR

log "🚀 Starting DevOps Stage 1 Deployment Script"

#==============================#
#      USER INPUT SECTION      #
#==============================#
read -p "Enter Git repository URL: " GIT_REPO
read -p "Enter Personal Access Token (PAT): " PAT
read -p "Enter branch name (default: main): " BRANCH
BRANCH=${BRANCH:-main}
read -p "Enter SSH username: " SSH_USER
read -p "Enter remote server IP: " REMOTE_IP
read -p "Enter SSH key path (default: ~/.ssh/id_rsa): " SSH_KEY
SSH_KEY=${SSH_KEY:-~/.ssh/id_rsa}
read -p "Enter internal app port (e.g., 8080): " APP_PORT

log "✅ Input collection complete"

#==============================#
#       GIT CLONE STAGE        #
#==============================#
if [ -d "app" ]; then
  log "📁 Existing app directory found. Removing..."
  rm -rf app
fi

log "📦 Cloning repository..."
git clone -b "$BRANCH" "https://${PAT}@${GIT_REPO#https://}" app >>"$LOG_FILE" 2>&1
log "✅ Repository cloned successfully"

#==============================#
#       SSH CONNECTION         #
#==============================#
log "🔐 Checking SSH connection..."
if ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=10 "$SSH_USER@$REMOTE_IP" "echo connected" >/dev/null 2>&1; then
  log "✅ SSH connection successful"
else
  log "❌ SSH connection failed"
  exit 1
fi

#==============================#
#     REMOTE SERVER SETUP      #
#==============================#
log "⚙️  Preparing remote server..."

ssh -i "$SSH_KEY" "$SSH_USER@$REMOTE_IP" bash -s <<EOF
set -euo pipefail

echo "🔄 Updating packages..."
sudo apt-get update -y

echo "🐳 Installing Docker..."
if ! command -v docker &>/dev/null; then
  sudo apt-get install -y ca-certificates curl gnupg lsb-release
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io
fi

echo "🧰 Installing Nginx..."
if ! command -v nginx &>/dev/null; then
  sudo apt-get install -y nginx
fi

sudo systemctl enable docker
sudo systemctl enable nginx
sudo systemctl start docker
sudo systemctl start nginx
EOF

log "✅ Server setup complete"

#==============================#
#     DEPLOYMENT STAGE         #
#==============================#
log "📦 Deploying application container..."

# Copy files to server
scp -i "$SSH_KEY" -r app "$SSH_USER@$REMOTE_IP":~/app >>"$LOG_FILE" 2>&1

ssh -i "$SSH_KEY" "$SSH_USER@$REMOTE_IP" bash -s <<EOF
set -euo pipefail
cd ~/app

echo "🛠️  Building Docker image..."
sudo docker build -t stage1-app .

echo "🧹 Removing old container if exists..."
sudo docker rm -f stage1-container || true

echo "🚀 Running container on port $APP_PORT..."
sudo docker run -d -p $APP_PORT:80 --name stage1-container stage1-app

echo "⚙️  Configuring Nginx as reverse proxy..."
sudo tee /etc/nginx/sites-available/stage1 > /dev/null <<NGINX
server {
    listen 80;
    location / {
        proxy_pass http://localhost:$APP_PORT;
    }
}
NGINX

sudo ln -sf /etc/nginx/sites-available/stage1 /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
EOF

log "✅ Application deployed and Nginx configured"

#==============================#
#     VALIDATION STAGE         #
#==============================#
log "🔎 Validating deployment..."
ssh -i "$SSH_KEY" "$SSH_USER@$REMOTE_IP" "
sudo docker ps | grep stage1-container && echo '✅ Docker container is running';
sudo systemctl status nginx | grep active
"

log "🎯 Deployment complete!"
echo "Access your app at: http://$REMOTE_IP"
