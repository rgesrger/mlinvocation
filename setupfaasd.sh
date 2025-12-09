#!/usr/bin/env bash
set -e

#############################
# Config
#############################
FUNC_NAME="hello-ubuntu2404"
LANGUAGE="python3"
OPENFAAS_URL="http://127.0.0.1:8080"

#############################
# Step 0: Fix broken locale
#############################
echo "[+] Fixing locale"
sudo apt update -y
sudo apt install -y locales
sudo locale-gen en_US.UTF-8
sudo update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

#############################
# Step 1: Remove broken Docker
#############################
echo "[+] Removing broken Docker installs"
sudo systemctl stop docker || true
sudo apt remove -y docker docker-engine docker.io containerd runc || true
sudo rm -rf /var/lib/docker /var/lib/containerd
sudo apt autoremove -y

#############################
# Step 2: Install Docker correctly
#############################
echo "[+] Installing Docker"
curl -fsSL https://get.docker.com | sudo sh

# Enable/start Docker
sudo systemctl unmask docker || true
sudo systemctl enable docker
sudo systemctl start docker

# Wait for Docker to work
echo "[+] Waiting for Docker daemon..."
for i in {1..30}; do
  if docker info &>/dev/null; then
    echo "[+] Docker is running"
    break
  fi
  sleep 2
done

if ! docker info &>/dev/null; then
  echo "[!] Docker failed to start. Dumping logs..."
  sudo journalctl -u docker --no-pager | tail -100
  exit 1
fi

#############################
# Step 3: Allow docker without sudo
#############################
sudo usermod -aG docker "$USER" || true

#############################
# Step 4: Install faasd
#############################
if [ ! -d "$HOME/faasd" ]; then
  echo "[+] Cloning faasd"
  git clone https://github.com/openfaas/faasd.git "$HOME/faasd"
fi

cd "$HOME/faasd"

echo "[+] Installing faasd"
./hack/install.sh

#############################
# Step 5: Wait for faasd
#############################
echo "[+] Waiting for faasd service..."

sudo systemctl enable faasd
sudo systemctl start faasd

for i in {1..60}; do
  if systemctl is-active --quiet faasd; then
    echo "[+] faasd service is active"
    break
  fi
  sleep 2
done

echo "[+] Waiting for OpenFaaS API endpoint..."

for i in {1..120}; do
  if curl -s http://127.0.0.1:8080/system/functions >/dev/null; then
    echo "[+] OpenFaaS is ready"
    break
  fi

  sleep 2
done

#############################
# Step 6: Install faas-cli
#############################
if ! command -v faas-cli &> /dev/null; then
  echo "[+] Installing faas-cli"
  curl -sSL https://cli.openfaas.com | sudo sh
fi

#############################
# Step 7: Login
#############################
echo "[+] Logging into OpenFaaS"

export OPENFAAS_URL="http://127.0.0.1:8080"

sudo -E cat /var/lib/faasd/secrets/basic-auth-password | \
  faas-cli login \
    --gateway "$OPENFAAS_URL" \
    --username admin \
    --password-stdin

#############################
# Step 8: Create function
#############################
cd "$HOME"

if [ ! -f "$FUNC_NAME.yml" ]; then
  faas-cli new "$FUNC_NAME" --lang "$LANGUAGE"
fi

#############################
# Step 9: Write handler
#############################
cat > "$HOME/$FUNC_NAME/handler.py" <<'EOF'
def handle(req):
    return f"Hello from faasd on Ubuntu 24.04!\nYou said:\n{req}\n"
EOF

#############################
# Step 10: Build & deploy
#############################
faas-cli build -f "$FUNC_NAME.yml"
faas-cli deploy -f "$FUNC_NAME.yml"

#############################
# Step 11: Test function
#############################
curl -s -X POST \
  "$OPENFAAS_URL/function/$FUNC_NAME" \
  -d "CloudLab test"

echo
echo "[+] Done!"
echo "[+] UI: $OPENFAAS_URL/ui"
