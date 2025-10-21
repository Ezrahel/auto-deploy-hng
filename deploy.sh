#!/bin/bash

#############################################################################
# DevOps Automated Deployment Script
# Description: Automates deployment of Dockerized applications with Nginx
# Author: DevOps Intern
# Version: 1.0.0
#############################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log file with timestamp
LOG_FILE="deploy_$(date +%Y%m%d_%H%M%S).log"
CLEANUP_MODE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --cleanup)
            CLEANUP_MODE=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

#############################################################################
# UTILITY FUNCTIONS
#############################################################################

log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $@"
    log "INFO" "$@"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $@"
    log "SUCCESS" "$@"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $@"
    log "WARNING" "$@"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $@"
    log "ERROR" "$@"
}

error_exit() {
    log_error "$1"
    exit "${2:-1}"
}

# Trap errors
trap 'error_exit "Script failed at line $LINENO with exit code $?" $?' ERR

#############################################################################
# STEP 1: COLLECT PARAMETERS FROM USER
#############################################################################

collect_parameters() {
    log_info "=== Step 1: Collecting Deployment Parameters ==="
    
    # Git Repository URL
    read -p "Enter Git Repository URL: " GIT_REPO_URL
    [[ -z "$GIT_REPO_URL" ]] && error_exit "Git repository URL cannot be empty" 10
    
    # Personal Access Token
    read -sp "Enter Personal Access Token (PAT): " GIT_PAT
    echo
    [[ -z "$GIT_PAT" ]] && error_exit "Personal Access Token cannot be empty" 11
    
    # Branch name
    read -p "Enter branch name (default: main): " GIT_BRANCH
    GIT_BRANCH=${GIT_BRANCH:-main}
    
    # SSH Username
    read -p "Enter SSH username: " SSH_USER
    [[ -z "$SSH_USER" ]] && error_exit "SSH username cannot be empty" 12
    
    # Server IP
    read -p "Enter server IP address: " SERVER_IP
    [[ -z "$SERVER_IP" ]] && error_exit "Server IP cannot be empty" 13
    
    # Validate IP format
    if ! [[ "$SERVER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        error_exit "Invalid IP address format" 14
    fi
    
    # SSH Key Path
    read -p "Enter SSH key path (default: ~/.ssh/id_rsa): " SSH_KEY_PATH
    SSH_KEY_PATH=${SSH_KEY_PATH:-~/.ssh/id_rsa}
    SSH_KEY_PATH="${SSH_KEY_PATH/#\~/$HOME}"
    
    if [[ ! -f "$SSH_KEY_PATH" ]]; then
        error_exit "SSH key not found at $SSH_KEY_PATH" 15
    fi
    
    # Application Port
    read -p "Enter application port (e.g., 80): " APP_PORT
    [[ -z "$APP_PORT" ]] && error_exit "Application port cannot be empty" 16
    
    if ! [[ "$APP_PORT" =~ ^[0-9]+$ ]] || [ "$APP_PORT" -lt 1 ] || [ "$APP_PORT" -gt 65535 ]; then
        error_exit "Invalid port number. Must be between 1 and 65535" 17
    fi
    
    # Extract repo name from URL
    REPO_NAME=$(basename "$GIT_REPO_URL" .git)
    
    log_success "All parameters collected successfully"
    log_info "Repository: $GIT_REPO_URL"
    log_info "Branch: $GIT_BRANCH"
    log_info "Server: $SSH_USER@$SERVER_IP"
    log_info "Application Port: $APP_PORT"
}

#############################################################################
# STEP 2: CLONE REPOSITORY
#############################################################################

clone_repository() {
    log_info "=== Step 2: Cloning Repository ==="
    
    # Prepare authenticated URL
    local auth_url=$(echo "$GIT_REPO_URL" | sed "s|https://|https://${GIT_PAT}@|")
    
    if [[ -d "$REPO_NAME" ]]; then
        log_warning "Repository directory already exists. Pulling latest changes..."
        cd "$REPO_NAME" || error_exit "Failed to navigate to repository directory" 20
        
        git fetch origin || error_exit "Failed to fetch from remote" 21
        git checkout "$GIT_BRANCH" || error_exit "Failed to checkout branch $GIT_BRANCH" 22
        git pull origin "$GIT_BRANCH" || error_exit "Failed to pull latest changes" 23
        
        log_success "Repository updated successfully"
    else
        log_info "Cloning repository..."
        git clone -b "$GIT_BRANCH" "$auth_url" "$REPO_NAME" || error_exit "Failed to clone repository" 24
        cd "$REPO_NAME" || error_exit "Failed to navigate to repository directory" 25
        log_success "Repository cloned successfully"
    fi
}

#############################################################################
# STEP 3: VERIFY DOCKER FILES
#############################################################################

verify_docker_files() {
    log_info "=== Step 3: Verifying Docker Configuration Files ==="
    
    if [[ -f "Dockerfile" ]]; then
        log_success "Dockerfile found"
        USE_COMPOSE=false
    elif [[ -f "docker-compose.yml" ]] || [[ -f "docker-compose.yaml" ]]; then
        log_success "docker-compose.yml found"
        USE_COMPOSE=true
    else
        error_exit "No Dockerfile or docker-compose.yml found in repository" 30
    fi
    
    PROJECT_DIR=$(pwd)
    log_info "Project directory: $PROJECT_DIR"
}

#############################################################################
# STEP 4: TEST SSH CONNECTION
#############################################################################

test_ssh_connection() {
    log_info "=== Step 4: Testing SSH Connection ==="
    
    log_info "Testing connectivity to $SERVER_IP..."
    
    if ping -c 2 -W 5 "$SERVER_IP" &> /dev/null; then
        log_success "Server is reachable via ping"
    else
        log_warning "Server did not respond to ping (may be blocked)"
    fi
    
    log_info "Testing SSH connection..."
    if ssh -o BatchMode=yes -o ConnectTimeout=10 -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" "echo 'SSH connection successful'" &> /dev/null; then
        log_success "SSH connection established successfully"
    else
        error_exit "Failed to establish SSH connection. Please check credentials and SSH key" 40
    fi
}

#############################################################################
# STEP 5: PREPARE REMOTE ENVIRONMENT
#############################################################################

prepare_remote_environment() {
    log_info "=== Step 5: Preparing Remote Environment ==="
    
    log_info "Updating system packages..."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" bash << 'ENDSSH' || error_exit "Failed to update packages" 50
        sudo apt-get update -y
ENDSSH
    
    log_info "Installing Docker..."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" bash << 'ENDSSH' || error_exit "Failed to install Docker" 51
        if ! command -v docker &> /dev/null; then
            curl -fsSL https://get.docker.com -o get-docker.sh
            sudo sh get-docker.sh
            rm get-docker.sh
            echo "Docker installed successfully"
        else
            echo "Docker is already installed"
        fi
ENDSSH
    
    log_info "Installing Docker Compose..."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" bash << 'ENDSSH' || error_exit "Failed to install Docker Compose" 52
        if ! command -v docker-compose &> /dev/null; then
            sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose
            echo "Docker Compose installed successfully"
        else
            echo "Docker Compose is already installed"
        fi
ENDSSH
    
    log_info "Installing Nginx..."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" bash << 'ENDSSH' || error_exit "Failed to install Nginx" 53
        if ! command -v nginx &> /dev/null; then
            sudo apt-get install -y nginx
            echo "Nginx installed successfully"
        else
            echo "Nginx is already installed"
        fi
ENDSSH
    
    log_info "Configuring Docker permissions..."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" bash << ENDSSH || error_exit "Failed to configure Docker permissions" 54
        sudo usermod -aG docker $SSH_USER || true
        sudo systemctl enable docker
        sudo systemctl start docker
        sudo systemctl enable nginx
        sudo systemctl start nginx
ENDSSH
    
    log_info "Verifying installations..."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" bash << 'ENDSSH' || error_exit "Failed to verify installations" 55
        echo "Docker version:"
        docker --version
        echo "Docker Compose version:"
        docker-compose --version
        echo "Nginx version:"
        nginx -v
ENDSSH
    
    log_success "Remote environment prepared successfully"
}

#############################################################################
# STEP 6: DEPLOY DOCKERIZED APPLICATION
#############################################################################

deploy_application() {
    log_info "=== Step 6: Deploying Dockerized Application ==="
    
    local remote_dir="/home/$SSH_USER/$REPO_NAME"
    
    log_info "Creating remote directory..."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" "mkdir -p $remote_dir" || error_exit "Failed to create remote directory" 60
    
    log_info "Transferring project files to remote server..."
    rsync -avz -e "ssh -i $SSH_KEY_PATH" --exclude '.git' --exclude 'node_modules' --exclude '.env' "$PROJECT_DIR/" "$SSH_USER@$SERVER_IP:$remote_dir/" || error_exit "Failed to transfer files" 61
    
    log_success "Files transferred successfully"
    
    log_info "Stopping existing containers (if any)..."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" bash << ENDSSH || true
        cd $remote_dir
        docker-compose down 2>/dev/null || docker stop \$(docker ps -q --filter "ancestor=$REPO_NAME") 2>/dev/null || true
        docker rm \$(docker ps -aq --filter "ancestor=$REPO_NAME") 2>/dev/null || true
ENDSSH
    
    if [[ "$USE_COMPOSE" == true ]]; then
        log_info "Building and starting containers with Docker Compose..."
        ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" bash << ENDSSH || error_exit "Failed to deploy with Docker Compose" 62
            cd $remote_dir
            docker-compose build
            docker-compose up -d
            sleep 5
            docker-compose ps
ENDSSH
    else
        log_info "Building Docker image..."
        ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" bash << ENDSSH || error_exit "Failed to build Docker image" 63
            cd $remote_dir
            docker build -t $REPO_NAME:latest .
ENDSSH
        
        log_info "Running Docker container..."
        ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" bash << ENDSSH || error_exit "Failed to run Docker container" 64
            docker run -d --name $REPO_NAME -p $APP_PORT:$APP_PORT $REPO_NAME:latest
            sleep 5
            docker ps -a --filter "name=$REPO_NAME"
ENDSSH
    fi
    
    log_info "Checking container logs..."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" bash << ENDSSH
        cd $remote_dir
        if [[ "$USE_COMPOSE" == "true" ]]; then
            docker-compose logs --tail=20
        else
            docker logs $REPO_NAME --tail=20
        fi
ENDSSH
    
    log_success "Application deployed successfully"
}

#############################################################################
# STEP 7: CONFIGURE NGINX REVERSE PROXY
#############################################################################

configure_nginx() {
    log_info "=== Step 7: Configuring Nginx Reverse Proxy ==="
    
    local nginx_config="/etc/nginx/sites-available/$REPO_NAME"
    local nginx_enabled="/etc/nginx/sites-enabled/$REPO_NAME"
    
    log_info "Creating Nginx configuration..."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" bash << ENDSSH || error_exit "Failed to configure Nginx" 70
        sudo tee $nginx_config > /dev/null << 'EOF'
server {
    listen 80;
    server_name $SERVER_IP _;

    location / {
        proxy_pass http://localhost:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

        sudo rm -f $nginx_enabled
        sudo ln -s $nginx_config $nginx_enabled
        
        echo "Testing Nginx configuration..."
        sudo nginx -t
        
        echo "Reloading Nginx..."
        sudo systemctl reload nginx
ENDSSH
    
    log_success "Nginx configured successfully"
}

#############################################################################
# STEP 8: VALIDATE DEPLOYMENT
#############################################################################

validate_deployment() {
    log_info "=== Step 8: Validating Deployment ==="
    
    log_info "Checking Docker service status..."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" bash << 'ENDSSH' || error_exit "Docker service is not running" 80
        if ! sudo systemctl is-active --quiet docker; then
            echo "Docker service is not running"
            exit 1
        fi
        echo "Docker service is running"
ENDSSH
    
    log_info "Checking container status..."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" bash << ENDSSH || error_exit "Container is not running" 81
        if [[ "$USE_COMPOSE" == "true" ]]; then
            if ! docker-compose -f /home/$SSH_USER/$REPO_NAME/docker-compose.yml ps | grep -q "Up"; then
                echo "No containers are running"
                exit 1
            fi
        else
            if ! docker ps | grep -q "$REPO_NAME"; then
                echo "Container $REPO_NAME is not running"
                exit 1
            fi
        fi
        echo "Container is running"
ENDSSH
    
    log_info "Checking Nginx status..."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" bash << 'ENDSSH' || error_exit "Nginx is not running" 82
        if ! sudo systemctl is-active --quiet nginx; then
            echo "Nginx is not running"
            exit 1
        fi
        echo "Nginx is running"
ENDSSH
    
    log_info "Testing application endpoint locally on server..."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" bash << ENDSSH
        echo "Testing http://localhost:$APP_PORT"
        curl -f -s -o /dev/null -w "%{http_code}" http://localhost:$APP_PORT || echo "Direct port test failed"
        
        echo "Testing http://localhost (Nginx proxy)"
        curl -f -s -o /dev/null -w "%{http_code}" http://localhost || echo "Nginx proxy test failed"
ENDSSH
    
    log_info "Testing application endpoint remotely..."
    if curl -f -s -o /dev/null -w "%{http_code}" "http://$SERVER_IP" 2>/dev/null; then
        log_success "Application is accessible at http://$SERVER_IP"
    else
        log_warning "Could not reach application remotely. Check firewall settings."
    fi
    
    log_success "Deployment validation completed"
}

#############################################################################
# CLEANUP FUNCTION
#############################################################################

cleanup_deployment() {
    log_info "=== Cleanup Mode: Removing Deployed Resources ==="
    
    if [[ "$CLEANUP_MODE" != true ]]; then
        return
    fi
    
    local remote_dir="/home/$SSH_USER/$REPO_NAME"
    
    log_info "Stopping and removing containers..."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" bash << ENDSSH || true
        cd $remote_dir
        if [[ -f "docker-compose.yml" ]] || [[ -f "docker-compose.yaml" ]]; then
            docker-compose down -v
        else
            docker stop $REPO_NAME 2>/dev/null || true
            docker rm $REPO_NAME 2>/dev/null || true
        fi
        docker rmi $REPO_NAME:latest 2>/dev/null || true
ENDSSH
    
    log_info "Removing Nginx configuration..."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" bash << ENDSSH || true
        sudo rm -f /etc/nginx/sites-enabled/$REPO_NAME
        sudo rm -f /etc/nginx/sites-available/$REPO_NAME
        sudo nginx -t && sudo systemctl reload nginx
ENDSSH
    
    log_info "Removing project directory..."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" "rm -rf $remote_dir" || true
    
    log_success "Cleanup completed successfully"
    exit 0
}

#############################################################################
# MAIN EXECUTION
#############################################################################

main() {
    log_info "=========================================="
    log_info "DevOps Automated Deployment Script"
    log_info "Started at: $(date)"
    log_info "=========================================="
    
    collect_parameters
    
    if [[ "$CLEANUP_MODE" == true ]]; then
        cleanup_deployment
    fi
    
    clone_repository
    verify_docker_files
    test_ssh_connection
    prepare_remote_environment
    deploy_application
    configure_nginx
    validate_deployment
    
    log_success "=========================================="
    log_success "Deployment completed successfully!"
    log_success "Application URL: http://$SERVER_IP"
    log_success "Log file: $LOG_FILE"
    log_success "=========================================="
    
    exit 0
}

# Run main function
main