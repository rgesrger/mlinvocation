#!/usr/bin/env bash
set -e

#############################
# Config
#############################
FUNC_NAME="hello-test"
FUNC_IMAGE="hello-test:latest"
OPENFAAS_URL="http://127.0.0.1:8080"

#############################
# Step 0: Install Docker
#############################
echo "[+] Installing Docker"
sudo apt-get update -y
sudo apt-get install -y \
    ca-certificates curl gnupg lsb-release

sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

sudo systemctl enable docker
sudo systemctl start docker

echo "[+] Docker installed and running"

#############################
# Step 1: Ensure faasd is running
#############################
echo "[+] Waiting for faasd gateway..."
until curl -s "$OPENFAAS_URL/healthz" | grep -q "OK"; do
  sleep 2
done
echo "[+] OpenFaaS gateway is up"

#############################
# Step 2: Prepare function folder
#############################
echo "[+] Creating function folder"
mkdir -p "$HOME/$FUNC_NAME"
cat > "$HOME/$FUNC_NAME/handler.py" <<'EOF'
def handle(req):
    return f"Hello from faasd via REST API!\nYou said:\n{req}\n"
EOF

cat > "$HOME/$FUNC_NAME/Dockerfile" <<'EOF'
FROM python:3.11-slim
WORKDIR /function
COPY handler.py .
ENV fprocess="python3 handler.py"
CMD ["python3", "handler.py"]
EOF

#############################
# Step 3: Build Docker image
#############################
echo "[+] Building Docker image"
docker build -t "$FUNC_IMAGE" "$HOME/$FUNC_NAME"

#############################
# Step 4: Deploy function via REST API
#############################
PASSWORD=$(sudo cat /var/lib/faasd/secrets/basic-auth-password)

echo "[+] Deploying function via REST API"
curl -s -X POST "$OPENFAAS_URL/system/functions" \
    -u admin:"$PASSWORD" \
    -H "Content-Type: application/json" \
    -d "{
        \"service\": \"$FUNC_NAME\",
        \"image\": \"$FUNC_IMAGE\",
        \"envProcess\": \"python3 handler.py\",
        \"network\": \"func_functions\"
    }"

#############################
# Step 5: Test function
#############################
echo "[+] Invoking function"
curl -s -X POST "$OPENFAAS_URL/function/$FUNC_NAME" -d "Hello REST API"
echo
