#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo: sudo ./scripts/install-lab.sh"
  exit 1
fi

echo "[1/5] Installing prerequisites and Docker..."
apt-get update
apt-get install -y ca-certificates curl gnupg git
install -m 0755 -d /etc/apt/keyrings
if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
fi
. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

echo "[2/5] Installing single-node K3s..."
if ! command -v k3s >/dev/null 2>&1; then
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server" sh -
fi
systemctl enable --now k3s
until kubectl get nodes >/dev/null 2>&1; do sleep 3; done

echo "[3/5] Preparing kubeconfig for Jenkins..."
mkdir -p /opt/jenkins
cp /etc/rancher/k3s/k3s.yaml /opt/jenkins/kubeconfig
chmod 644 /opt/jenkins/kubeconfig
# Jenkins uses host networking, so 127.0.0.1 reaches the host K3s API.
sed -i 's/127.0.0.1/127.0.0.1/' /opt/jenkins/kubeconfig

echo "[4/5] Building Jenkins image..."
cd "$(dirname "$0")/.."
docker build -f scripts/jenkins.Dockerfile -t jenkins-k8s-lab:latest .

echo "[5/5] Starting Jenkins..."
docker volume create jenkins_home >/dev/null
docker rm -f jenkins >/dev/null 2>&1 || true
docker run -d \
  --name jenkins \
  --restart unless-stopped \
  --network host \
  -u root \
  -v jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /opt/jenkins/kubeconfig:/var/jenkins_home/kubeconfig:ro \
  -e KUBECONFIG=/var/jenkins_home/kubeconfig \
  jenkins-k8s-lab:latest

echo
echo "Jenkins is starting. Wait 1-3 minutes, then retrieve the initial password:"
echo "docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword"
echo "Open http://<EC2_PUBLIC_IP>:8080"
echo
echo "K3s status:"
kubectl get nodes -o wide
