# Automated Deployment Bash Script

A production-grade Bash script for automated deployment of Dockerized applications with Nginx reverse proxy configuration on remote Linux servers.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Usage](#usage)
- [Script Workflow](#script-workflow)
- [Configuration](#configuration)
- [Cleanup](#cleanup)
- [Troubleshooting](#troubleshooting)
- [Log Files](#log-files)
- [Security Considerations](#security-considerations)
- [Contributing](#contributing)

## Overview

This script automates the entire deployment pipeline for Dockerized applications, including:
- Repository cloning and management
- Remote server environment setup
- Docker container deployment
- Nginx reverse proxy configuration
- Deployment validation and health checks

## Features

- ✅ **Interactive Parameter Collection**: Secure input prompts with validation
- ✅ **Git Integration**: Automated repository cloning with PAT authentication
- ✅ **SSH Automation**: Remote server management via SSH
- ✅ **Docker Support**: Both Dockerfile and docker-compose.yml workflows
- ✅ **Nginx Configuration**: Automatic reverse proxy setup
- ✅ **Comprehensive Logging**: Timestamped logs for all operations
- ✅ **Error Handling**: Robust error detection with meaningful exit codes
- ✅ **Idempotent Operations**: Safe to run multiple times
- ✅ **Cleanup Mode**: Optional resource removal
- ✅ **Health Validation**: Automated deployment verification

## Prerequisites

### Local Machine Requirements
- Bash 4.0 or higher
- Git
- SSH client
- rsync

### Remote Server Requirements
- Ubuntu/Debian-based Linux distribution
- SSH access with key-based authentication
- Sudo privileges for the SSH user
- Open ports: 22 (SSH), 80 (HTTP), and your application port

## 🔧 Installation

1. Clone this repository:
```bash
git clone https://github.com/ezrahel/devops-deployment-script.git
cd devops-deployment-script
```

2. Make the script executable:
```bash
chmod +x deploy.sh
```

3. Ensure your SSH key is properly set up:
```bash
# Generate SSH key if you don't have one
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"

# Copy SSH key to remote server
ssh-copy-id -i ~/.ssh/id_rsa.pub user@server_ip
```

## Usage

### Basic Deployment

Run the script and follow the interactive prompts:

```bash
./deploy.sh
```

You'll be prompted for:
- **Git Repository URL**: `https://github.com/username/repository.git`
- **Personal Access Token (PAT)**: Your GitHub/GitLab PAT (hidden input)
- **Branch name**: `main` (default) or specify another branch
- **SSH Username**: Username for remote server access
- **Server IP Address**: `192.168.1.100` or your server IP
- **SSH Key Path**: `~/.ssh/id_rsa` (default) or custom path
- **Application Port**: `80` (or your app's internal port)

### Cleanup Mode

To remove all deployed resources:

```bash
./deploy.sh --cleanup
```

This will:
- Stop and remove Docker containers
- Remove Docker images
- Delete Nginx configuration
- Remove project directory from remote server

## Script Workflow

The deployment process follows these steps:

### 1. Parameter Collection
- Collects and validates all required deployment parameters
- Validates IP address format and port ranges
- Verifies SSH key existence

### 2. Repository Management
- Clones repository using authenticated URL
- Pulls latest changes if repository exists
- Switches to specified branch

### 3. Docker File Verification
- Checks for Dockerfile or docker-compose.yml
- Determines deployment method

### 4. SSH Connection Testing
- Tests server connectivity via ping
- Validates SSH authentication
- Establishes secure connection

### 5. Environment Preparation
- Updates system packages
- Installs Docker and Docker Compose
- Installs and configures Nginx
- Sets up user permissions
- Enables required services

### 6. Application Deployment
- Transfers project files via rsync
- Stops existing containers (idempotent)
- Builds Docker image/compose stack
- Starts containers with proper configuration
- Validates container health

### 7. Nginx Configuration
- Creates reverse proxy configuration
- Routes port 80 traffic to application
- Sets up proxy headers
- Tests and reloads Nginx

### 8. Deployment Validation
- Verifies Docker service status
- Checks container health
- Tests Nginx proxy functionality
- Validates local and remote accessibility

## Configuration

### Environment Variables (Optional)

You can set default values using environment variables:

```bash
export GIT_REPO_URL="https://github.com/username/repo.git"
export GIT_BRANCH="main"
export SSH_USER="ubuntu"
export SERVER_IP="192.168.1.100"
export SSH_KEY_PATH="~/.ssh/id_rsa"
export APP_PORT="80"
```

### Nginx Customization

The script creates a basic Nginx configuration. To customize:

1. After deployment, edit the config on the remote server:
```bash
ssh user@server_ip
sudo nano /etc/nginx/sites-available/your-repo-name
```

2. Add SSL/TLS support with Let's Encrypt:
```bash
sudo apt-get install certbot python3-certbot-nginx
sudo certbot --nginx -d yourdomain.com
```

## Cleanup

The cleanup mode removes all deployed resources while preserving system packages (Docker, Nginx, etc.).

```bash
./deploy.sh --cleanup
```

**Warning**: This will:
- ⚠️ Stop and remove all containers
- ⚠️ Delete Docker images for this project
- ⚠️ Remove Nginx configuration
- ⚠️ Delete project files from remote server

## Troubleshooting

### SSH Connection Issues

```bash
# Test SSH connection manually
ssh -vvv -i ~/.ssh/id_rsa user@server_ip

# Check SSH key permissions (should be 600)
chmod 600 ~/.ssh/id_rsa
```

### Docker Permission Issues

If you encounter Docker permission errors:

```bash
# On remote server, add user to docker group
sudo usermod -aG docker $USER

# Log out and back in, or run:
newgrp docker
```

### Port Already in Use

```bash
# Check what's using the port
sudo lsof -i :PORT_NUMBER

# Kill the process
sudo kill -9 PID
```

### Nginx Configuration Errors

```bash
# Test Nginx configuration
sudo nginx -t

# Check Nginx logs
sudo tail -f /var/log/nginx/error.log
```

### Container Health Issues

```bash
# View container logs
docker logs CONTAINER_NAME

# Inspect container
docker inspect CONTAINER_NAME

# Execute commands inside container
docker exec -it CONTAINER_NAME bash
```

## Log Files

Each deployment creates a timestamped log file:

```
deploy_YYYYMMDD_HHMMSS.log
```

Example:
```
deploy_20241021_143022.log
```

Logs include:
- All script actions and outputs
- Error messages with context
- Timestamps for each operation
- Command results from remote server

## Security Considerations

1. **Personal Access Token**: Never commit PATs to version control
2. **SSH Keys**: Use strong keys (4096-bit RSA or ED25519)
3. **Key Permissions**: Ensure SSH keys have 600 permissions
4. **Firewall**: Configure UFW or iptables appropriately
5. **SSL/TLS**: Add HTTPS support for production deployments
6. **Secrets**: Use environment files (.env) for sensitive data, never in Dockerfile
7. **Updates**: Regularly update Docker, Nginx, and system packages

### Recommended Firewall Setup

```bash
# On remote server
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow http
sudo ufw allow https
sudo ufw enable
```

## Exit Codes

The script uses specific exit codes for troubleshooting:

- `0`: Success
- `10-17`: Parameter validation errors
- `20-25`: Repository operations errors
- `30`: Docker file verification error
- `40`: SSH connection error
- `50-55`: Environment preparation errors
- `60-64`: Deployment errors
- `70`: Nginx configuration error
- `80-82`: Validation errors

## HNG Submission Checklist

Before submitting to the #stage-1-devops channel:

- ✅ Script is executable (`chmod +x deploy.sh`)
- ✅ README.md is complete and clear
- ✅ Repository is pushed to GitHub
- ✅ Server is accessible and working
- ✅ Deployment tested successfully
- ✅ All logs are reviewed for errors
- ✅ No hardcoded credentials in code

### Submission Command

In the #stage-1-devops channel:

```
/stage-one-devops
```

Then provide:
- Your full name
- GitHub repository URL: `https://github.com/username/repo`

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License.

## Author

DevOps Intern - HNG Internship Stage 1

## Acknowledgments

- HNG Internship Program
- Cool Keeds DevOps Track
- Docker Community
- Nginx Team

---

**Need Help?** 
- Check the troubleshooting section
- Review the log files
- Test each component manually
- Reach out in the #track-devops Slack channel

Good luck with your deployment!