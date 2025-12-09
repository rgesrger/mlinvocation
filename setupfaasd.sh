#!/usr/bin/env bash
set -e

#############################
# Config
#############################
FUNC_NAME="hello-ubuntu2404"
LANGUAGE="python3"
OPENFAAS_URL="http://127.0.0.1:8080"
USER_NAME=$(whoami)

#############################
# Step 0: Locale fix
#############################
echo "[+] Configuring locale"
sudo apt-get update -y
sudo apt-get install -y locales curl git ca-certificates gnupg lsb-release uidmap

sudo locale-gen en_US.UTF-8
sudo update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

#############################
# Step 1: Clean any broken Docker
#############################
echo "[+] Removing any existing Docker"
sudo systemctl stop docker 2>/dev/null || true
sudo systemctl disable docker 2>/dev/null || true
sudo systemctl unmask docker 2>/dev/null || true

sudo apt-get remove -y docker docker-engine docker.io containerd runc || true
sudo apt-get purge -y docker docker-engine docker.io containerd runc || true

sudo rm -rf /var/lib/docker
sudo rm -rf /var/lib/containerd
sudo rm -rf /etc/docker
sudo rm -rf /etc/systemd/system/docker.service.d
sudo rm -f /etc/init.d/docker

sudo systemctl daemon-reload

#############################
# Step 2: Install Docker (official)
#############################
echo "[+] Installing Docker"

curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
rm -f get-docker.sh

sudo systemctl enable docker
sudo systemctl start docker

echo "[+] Waiting for Docker..."
for i in {1..60}; do
  if sudo docker info >/dev/null 2>&1; then
    echo "[+] Docker is ready"
    break
  fi
  sleep 2
done

if ! sudo docker info >/dev/null 2>&1; then
  echo "[!] Docker failed to start:"
  sudo journalctl -u docker --no-pager | tail -100
  exit 1
fi

#############################
# Step 3: Install faasd
#############################
echo "[+] Installing faasd"

cd "$HOME"
rm -rf faasd
git clone https://github.com/openfaas/faasd.git
cd faasd

sudo ./hack/install.sh

#############################
# Step 4: Wait for faasd gateway
#############################
echo "[+] Waiting for OpenFaaS gateway..."

for i in {1..120}; do
  if curl -fs http://127.0.0.1:8080/system/functions >/dev/null 2>&1; then
    echo "[+] Gateway ready"
    break
  fi
  sleep 2
done

if ! curl -fs http://127.0.0.1:8080/system/functions >/dev/null 2>&1; then
  echo "[!] OpenFaaS gateway failed to come up"
  sudo journalctl -u faasd --no-pager | tail -100
  exit 1
fi

#############################
# Step 5: Install faas-cli
#############################
echo "[+] Installing faas-cli"

if ! command -v faas-cli >/dev/null 2>&1; then
  curl -sSL https://cli.openfaas.com | sudo sh
fi

#############################
# Step 6: Login to OpenFaaS
#############################
echo "[+] Logging into OpenFaaS"

PASSWORD=$(sudo cat /var/lib/faasd/secrets/basic-auth-password)

echo "$PASSWORD" | faas-cli login \
  --gateway "$OPENFAAS_URL" \
  --username admin \
  --password-stdin

#############################
# Step 7: Create function
#############################
cd "$HOME"

if [ ! -f "$FUNC_NAME.yml" ]; then
  faas-cli new "$FUNC_NAME" --lang "$LANGUAGE"
fi

#############################
# Step 8: Write handler
#############################
cat > "$HOME/$FUNC_NAME/handler.py" <<'EOF'
def handle(req):
    return f"Hello from faasd on Ubuntu 24.04!\nYou said:\n{req}\n"
EOF

#############################
# Step 9: Build & deploy
#############################
faas-cli build -f "$FUNC_NAME.yml"
faas-cli deploy -f "$FUNC_NAME.yml"

#############################
# Step 10: Test
#############################
echo "[+] Testing function..."
curl -s -X POST "$OPENFAAS_URL/function/$FUNC_NAME" -d "test input"
echo

echo "[+] Done"
echo "[+] UI: $OPENFAAS_URL/ui"
