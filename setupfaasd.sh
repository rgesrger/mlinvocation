#!/bin/bash
set -e

# 1. Install Dependencies
apt-get update
apt-get install -y curl git bridge-utils runc containerd

# 2. Configure Kernel Networking (Required for containers to talk to internet)
echo "net.ipv4.ip_forward = 1" | tee -a /etc/sysctl.conf
echo "net.bridge.bridge-nf-call-iptables = 1" | tee -a /etc/sysctl.conf
sysctl -p

# 3. Install CNI Network Plugins
mkdir -p /opt/cni/bin
curl -sSL "https://github.com/containernetworking/plugins/releases/download/v1.3.0/cni-plugins-linux-amd64-v1.3.0.tgz" | tar -xz -C /opt/cni/bin

# 4. Download faasd binaries (Latest)
mkdir -p /var/lib/faasd/secrets
VERSION=$(curl -s "https://api.github.com/repos/openfaas/faasd/releases/latest" | grep '"tag_name":' | cut -d '"' -f 4)

curl -fSL "https://github.com/openfaas/faasd/releases/download/$VERSION/faasd" -o "/usr/local/bin/faasd"
curl -fSL "https://github.com/openfaas/faasd/releases/download/$VERSION/faasd-provider" -o "/usr/local/bin/faasd-provider"
chmod +x /usr/local/bin/faasd /usr/local/bin/faasd-provider

# 5. Install Services & CLI
git clone https://github.com/openfaas/faasd.git
cd faasd && ./hack/install.sh && cd .. && rm -rf faasd
curl -sL https://cli.openfaas.com | sh

# 6. Print Password
echo "Waiting for password generation..."
sleep 15
echo "Setup Done. Your Password:"
cat /var/lib/faasd/secrets/basic-auth-password
echo ""