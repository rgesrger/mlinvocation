#!/usr/bin/env bash
set -e

#========================
# Config
#========================
FUNC_NAME="hello-ubuntu2404"
LANG="python3"
OPENFAAS_URL="http://127.0.0.1:8080"

#========================
# Step 1: System prep
#========================
echo "[+] Updating system"
sudo apt update -y
sudo apt install -y curl git ca-certificates gnupg

#========================
# Step 2: Install Docker
#========================
if ! command -v docker &> /dev/null; then
  echo "[+] Installing Docker"
  curl -fsSL https://get.docker.com | sudo sh
fi

sudo systemctl enable docker
sudo systemctl start docker

sudo usermod -aG docker "$USER" || true
echo "[!] You may need to log out and back in for docker group changes to apply."

#========================
# Step 3: Install faasd
#========================
if [ ! -d "$HOME/faasd" ]; then
  echo "[+] Cloning faasd"
  git clone https://github.com/openfaas/faasd.git "$HOME/faasd"
fi

cd "$HOME/faasd"

echo "[+] Installing faasd"
./hack/install.sh

# Wait for faasd to be ready
echo "[+] Waiting for faasd gateway"
sleep 10

#========================
# Step 4: Install faas-cli
#========================
if ! command -v faas-cli &> /dev/null; then
  echo "[+] Installing faas-cli"
  curl -sSL https://cli.openfaas.com | sudo sh
fi

#========================
# Step 5: Login
#========================
echo "[+] Getting OpenFaaS password"
PASS=$(sudo cat /var/lib/faasd/secrets/basic-auth-password)

export OPENFAAS_URL="$OPENFAAS_URL"

echo "[+] Logging into OpenFaaS"
echo "$PASS" | faas-cli login \
  --username admin \
  --password-stdin

#========================
# Step 6: Create function
#========================
cd "$HOME"

if [ ! -f "$FUNC_NAME.yml" ]; then
  echo "[+] Creating function: $FUNC_NAME"
  faas-cli new "$FUNC_NAME" --lang "$LANG"
fi

#========================
# Step 7: Write handler
#========================
echo "[+] Writing function handler"
cat > "$HOME/$FUNC_NAME/handler.py" <<'EOF'
def handle(req):
    return f"Hello from faasd on Ubuntu 24.04!\nYou said:\n{req}\n"
EOF

#========================
# Step 8: Build & deploy
#========================
echo "[+] Building function"
faas-cli build -f "$FUNC_NAME.yml"

echo "[+] Deploying function"
faas-cli deploy -f "$FUNC_NAME.yml"

#========================
# Step 9: Test function
#========================
echo "[+] Invoking function"
curl -s -X POST \
  "$OPENFAAS_URL/function/$FUNC_NAME" \
  -d "CloudLab test input"

echo
echo "[+] Setup complete!"
echo "[+] OpenFaaS UI: $OPENFAAS_URL/ui"
