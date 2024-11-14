#!/bin/bash

# Step 1: Gather User Input
read -p "Enter your domain name (e.g., example.com): " DOMAIN
read -p "Enter your preferred SSH port (default is 22): " SSH_PORT
SSH_PORT=${SSH_PORT:-22}

# Ask for additional components
read -p "Do you want to install Fail2Ban for security? (y/n): " INSTALL_FAIL2BAN
read -p "Do you want to install Docker and Docker Compose? (y/n): " INSTALL_DOCKER
read -p "Do you want to install Portainer for container management? (y/n): " INSTALL_PORTAINER
read -p "Do you want to install NGINX for reverse proxy? (y/n): " INSTALL_NGINX
read -p "Do you want to enable SSL certificates with Let's Encrypt? (y/n): " INSTALL_CERTBOT

# Step 2: Update and Upgrade Packages
echo "Updating and upgrading packages..."
sudo apt update && sudo apt upgrade -y

# Step 3: Create a New Sudo User
read -p "Enter a username for the new sudo user: " USERNAME
sudo adduser $USERNAME
sudo usermod -aG sudo $USERNAME

# Step 4: Configure SSH Key-Based Authentication
echo "Setting up SSH key-based authentication..."
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -q -N ""
cat ~/.ssh/id_rsa.pub | sudo tee /home/$USERNAME/.ssh/authorized_keys
sudo chmod 600 /home/$USERNAME/.ssh/authorized_keys
sudo chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh

# Step 5: Configure SSH Daemon
echo "Configuring SSH daemon..."
sudo sed -i "s/#Port 22/Port $SSH_PORT/" /etc/ssh/sshd_config
sudo sed -i "s/PermitRootLogin yes/PermitRootLogin no/" /etc/ssh/sshd_config
sudo sed -i "s/#PasswordAuthentication yes/PasswordAuthentication no/" /etc/ssh/sshd_config
sudo systemctl restart ssh

# Step 6: Set up UFW Firewall
echo "Setting up UFW firewall..."
sudo ufw allow $SSH_PORT/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable

# Step 7: Install Fail2Ban (if selected)
if [[ $INSTALL_FAIL2BAN == "y" ]]; then
    echo "Installing Fail2Ban..."
    sudo apt install fail2ban -y
    sudo systemctl enable fail2ban
    sudo systemctl start fail2ban
fi

# Step 8: Install Docker and Docker Compose (if selected)
if [[ $INSTALL_DOCKER == "y" ]]; then
    echo "Installing Docker and Docker Compose..."
    sudo apt install apt-transport-https ca-certificates curl software-properties-common -y
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update
    sudo apt install docker-ce docker-ce-cli containerd.io -y
    sudo usermod -aG docker $USERNAME
    newgrp docker

    # Install Docker Compose
    DOCKER_COMPOSE_VERSION="2.6.0"
    sudo curl -L "https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
fi

# Step 9: Install Portainer (if selected)
if [[ $INSTALL_PORTAINER == "y" ]]; then
    echo "Installing Portainer..."
    docker volume create portainer_data
    docker run -d -p 9000:9000 -p 8000:8000 --name=portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce
fi

# Step 10: Install NGINX (if selected)
if [[ $INSTALL_NGINX == "y" ]]; then
    echo "Installing NGINX..."
    sudo apt install nginx -y
    sudo systemctl enable nginx
    sudo systemctl start nginx

    # Set up NGINX configuration for reverse proxy
    echo "Configuring NGINX reverse proxy..."
    for app in vikunja wordpress mautic; do
      sudo tee /etc/nginx/sites-available/$app.conf > /dev/null <<EOF
server {
    listen 80;s
    server_name $app.$DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:8000;  # Change port based on app requirements
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
      sudo ln -s /etc/nginx/sites-available/$app.conf /etc/nginx/sites-enabled/
    done
    sudo nginx -t && sudo systemctl reload nginx
fi

# Step 11: Install Certbot and Configure SSL Certificates (if selected)
if [[ $INSTALL_CERTBOT == "y" && $INSTALL_NGINX == "y" ]]; then
    echo "Installing Certbot for SSL certificate management..."
    sudo apt install certbot python3-certbot-nginx -y
    for app in vikunja wordpress mautic; do
      sudo certbot --nginx -d $app.$DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN --redirect
    done
fi

echo "Setup complete! Please verify all configurations and DNS settings."
