#!/bin/bash
# Installs Docker Engine + compose plugin from download.docker.com on Ubuntu or Debian (also derivatives such as Mint).
# Used for WSL2 Ubuntu by setup-server.ps1 and for native Linux by setup-server.sh. Needs systemd. Run as root.
# Manual run from Windows:  wsl -d Ubuntu -u root -- bash ./linux-server-tools/install-docker.sh <linux-user>
# Manual run on Linux:      sudo bash ./linux-server-tools/install-docker.sh <linux-user>
set -euo pipefail
USER_NAME="${1:-${SUDO_USER:-}}"

. /etc/os-release
case " ${ID:-} ${ID_LIKE:-} " in
  *" ubuntu "*) REPO=ubuntu; CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}" ;;
  *" debian "*) REPO=debian; CODENAME="${DEBIAN_CODENAME:-${VERSION_CODENAME:-}}"
    [ "${ID:-}" = debian ] && CODENAME="${VERSION_CODENAME:-}" ;;
  *) echo "Unsupported distribution '${ID:-unknown}': install Docker Engine and the compose plugin yourself (https://docs.docker.com/engine/install/)." >&2; exit 1 ;;
esac
if [ -z "$CODENAME" ]; then
  echo "Cannot determine the release codename from /etc/os-release." >&2
  exit 1
fi

apt-get update
apt-get install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL "https://download.docker.com/linux/$REPO/gpg" -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
# A derivative may report a codename Docker does not publish (for example kali-rolling): stop before writing a broken repo line.
if [ "${ID:-}" != ubuntu ] && [ "${ID:-}" != debian ]; then
  if ! curl -fsSI "https://download.docker.com/linux/$REPO/dists/$CODENAME/Release" >/dev/null 2>&1; then
    echo "download.docker.com has no packages for '$CODENAME' (${PRETTY_NAME:-${ID:-unknown}}). Install Docker Engine yourself: https://docs.docker.com/engine/install/$REPO/" >&2
    exit 1
  fi
fi
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$REPO $CODENAME stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker   # starts Docker now and at every boot
if [ -n "$USER_NAME" ] && [ "$USER_NAME" != root ]; then
  usermod -aG docker "$USER_NAME"
fi
docker version --format 'docker {{.Server.Version}}'
docker compose version
if grep -qi microsoft /proc/version 2>/dev/null; then
  echo "OK. Run 'wsl --terminate <distro>' once so the docker group applies."
else
  echo "OK. Log out and in again so the docker group applies."
fi
