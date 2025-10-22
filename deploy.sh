#!/bin/bash
# deploy.sh - Automated deployment of a Dockerized app to a remote server

# Exit immediately if a command fails, treat unset variables as errors, fail on pipe errors
set -euo pipefail

# Define a timestamped log file
LOG_FILE="deploy_$(date +%Y%m%d).log"

# Function to log messages
log() {
  # Prints timestamped message to terminal and appends to log file
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Step 1 complete: Logging is set up"
# Stage 2: Collect user input
read -p "Enter Git repository URL: " GIT_REPO
read -sp "Enter Personal Access Token (PAT): " PAT
echo
read -p "Enter branch name (default: main): " BRANCH
BRANCH=${BRANCH:-main}  # default to main if empty
read -p "Enter SSH username: " SSH_USER
read -p "Enter remote server IP: " SERVER_IP
read -p "Enter SSH key path (default: ~/.ssh/id_rsa): " SSH_KEY
SSH_KEY=${SSH_KEY:-~/.ssh/id_rsa}
read -p "Enter application port (internal container port): " APP_PORT

log "Stage 2 complete: User input collected"
# -----------------------------
# Stage 3: Clone or update repo
# -----------------------------

# Extract repo name from URL (e.g., getting-started)
REPO_NAME=$(basename -s .git "$GIT_REPO")

# If folder already exists, update it; otherwise, clone it
if [ -d "$REPO_NAME" ]; then
  log "Repository already exists. Pulling latest changes..."
  cd "$REPO_NAME"
  git fetch origin "$BRANCH"
  git checkout "$BRANCH"
  git pull origin "$BRANCH"
  cd ..
  log "Stage 3 complete: Repository updated successfully."
else
  log "Cloning repository..."
  GIT_CLONE_URL="${GIT_REPO/https:\/\//https://$PAT@}"
  git clone -b "$BRANCH" "$GIT_CLONE_URL"
  log "Stage 3 complete: Repository cloned successfully."
fi
git push -u origin main
