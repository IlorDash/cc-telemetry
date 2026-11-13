#!/bin/bash
# Installs Docker Engine + compose plugin inside WSL2 Ubuntu, for Windows versions without Docker Desktop.
# Needs systemd=true in /etc/wsl.conf. Normally called by setup-server.ps1.
# Manual run from Windows:  wsl -d Ubuntu -u root -- bash ./wsl/install-docker.sh <linux-user>
set -euo pipefail
USER_NAME="${1:-${SUDO_USER:-}}"

apt-get update
apt-get install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME:-$VERSION_CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker
[ -n "$USER_NAME" ] && usermod -aG docker "$USER_NAME"
docker version --format 'docker {{.Server.Version}}'
docker compose version
echo "OK. Run 'wsl --terminate Ubuntu' once so the docker group applies."
