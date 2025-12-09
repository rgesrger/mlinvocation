#!/bin/bash

# ============================================================
# CloudLab Setup: OpenFaaS (faasd) on Ubuntu 24.04
# ============================================================

set -e

# 1. Root Check
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo ./setup_node.sh)"
  exit
fi

echo ">>> [1/7] Updating system and installing dependencies..."
apt-get update -y -q
apt-get install -y -q curl git runc bridge-utils build-essential jq

# 2. Kernel Networking
echo ">>> [2/7] Configuring kernel forwarding..."
cat <<EOF | tee /etc/sysctl.d/99-openfaas.conf
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sysctl --system

# 3. Install containerd
if ! command -v containerd &> /dev/null; then
    echo ">>> [3/7] Installing containerd..."
    apt-get install -y -q containerd
else
    echo ">>> [3/7] containerd already installed."
fi

# 4. Install CNI Plugins
echo ">>> [4/7] Installing CNI networking plugins..."
CNI_VERSION="v1.3.0"
mkdir -p /opt/cni/bin
curl -sSL "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-amd64-${CNI_VERSION}.tgz" | tar -xz -C /opt/cni/bin

# 5. Install faasd
echo ">>> [5/7] Installing faasd..."
mkdir -p /var/lib/faasd/secrets

# Get latest version tag
FAASD_VERSION=$(curl -s "https://api.github.com/repos/openfaas/faasd/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

# Download binaries
curl -fSLs "https://github.com/openfaas/faasd/releases/download/${FAASD_VERSION}/faasd" -o "/usr/local/bin/faasd"
chmod +x "/usr/local/bin/faasd"

curl -fSLs "https://github.com/openfaas/faasd/releases/download/${FAASD_VERSION}/faasd-provider" -o "/usr/local/bin/faasd-provider"
chmod +x "/usr/local/bin/faasd-provider"

# Setup Systemd via hack script
if [ -d "faasd" ]; then rm -rf faasd; fi
git clone https://github.com/openfaas/faasd.git
cd faasd
./hack/install.sh
cd ..
rm -rf faasd

# Install faas-cli for convenience
curl -sL https://cli.openfaas.com | sh

# 6. Generate REST API Helper Script
# This creates a tool in your directory to make API calls easier
echo ">>> [6/7] Generating REST API helper script (invoke.sh)..."
cat << 'EOF' > invoke.sh
#!/bin/bash
# Helper to invoke OpenFaaS functions via REST
FUNCTION=$1
PAYLOAD=$2
SECRET="/var/lib/faasd/secrets/basic-auth-password"

if [ -z "$FUNCTION" ]; then echo "Usage: ./invoke.sh <function_name> [payload]"; exit 1; fi
if [ -z "$PAYLOAD" ] && [ -p /dev/stdin ]; then PAYLOAD=$(cat); fi

PASSWORD=$(sudo cat $SECRET)
echo "Invoking $FUNCTION..."
curl -s -u "admin:$PASSWORD" -d "$PAYLOAD" "http://127.0.0.1:8080/function/$FUNCTION"
echo "" # Newline
EOF

chmod +x invoke.sh

# 7. Wait and Display Info
echo ">>> [7/7] Installation done. Waiting for startup (15s)..."
sleep 15

if [ -f /var/lib/faasd/secrets/basic-auth-password ]; then
    PASSWORD=$(cat /var/lib/faasd/secrets/basic-auth-password)
    IP=$(hostname -I | cut -d' ' -f1)
    
    echo "=========================================================="
    echo "              Setup Complete"
    echo "=========================================================="
    echo "URL:       http://$IP:8080"
    echo "Username:  admin"
    echo "Password:  $PASSWORD"
    echo ""
    echo "How to use the REST API Helper:"
    echo "  ./invoke.sh <function-name> \"<payload>\""
    echo "=========================================================="
else
    echo "Warning: Password file not found yet. Check service logs."
fi