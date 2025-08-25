#!/bin/bash
set -e

# 1. Update and install dependencies
sudo apt-get update
sudo apt-get install -y curl wget git make socat conntrack iptables apt-transport-https ca-certificates curl

# 2. Install Docker
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker $USER
fi

# 3. Install Go 1.23 (required for cri-dockerd)
GO_VERSION=1.23.1
if ! go version &> /dev/null || [[ "$(go version)" != *"go$GO_VERSION"* ]]; then
    sudo rm -rf /usr/local/go
    wget https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz
    sudo tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz
    rm go${GO_VERSION}.linux-amd64.tar.gz
    export PATH=$PATH:/usr/local/go/bin
    echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
fi

# 4. Install cri-dockerd
if ! command -v cri-dockerd &> /dev/null; then
    git clone https://github.com/Mirantis/cri-dockerd.git ~/cri-dockerd
    cd ~/cri-dockerd/cri-dockerd
    make clean
    make cri-dockerd
    sudo cp cri-dockerd /usr/local/bin/
    
    # Set up systemd service for cri-dockerd
    sudo cp packaging/systemd/* /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable --now cri-docker.service
    sudo systemctl enable --now cri-docker.socket
fi

# 5. Install kubectl
if ! command -v kubectl &> /dev/null; then
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
fi

# 6. Install minikube
if ! command -v minikube &> /dev/null; then
    curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    sudo install minikube-linux-amd64 /usr/local/bin/minikube
    rm minikube-linux-amd64
fi

# 7. Start minikube in none driver mode
export CHANGE_MINIKUBE_NONE_USER=true
sudo minikube delete --all --purge || true
sudo minikube start --driver=none --container-runtime=docker --cri-socket=/var/run/cri-dockerd.sock

# 8. Set up kubectl access for current user
sudo mv /root/.kube $HOME/
sudo mv /root/.minikube $HOME/
sudo chown -R $USER:$USER $HOME/.kube $HOME/.minikube
export KUBECONFIG=$HOME/.kube/config
minikube update-context

# 9. Final check
kubectl get nodes
kubectl get pods -A
