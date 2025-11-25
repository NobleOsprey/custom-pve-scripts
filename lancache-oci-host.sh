#!/usr/bin/env bash
source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVE/raw/branch/main/misc/build.func)
# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://lancache.net/

APP="Lancache OCI Host"
var_tags="${var_tags:-lancache oci host}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-64}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-0}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  msg_info "Updating base system"
  $STD apt-get update
  $STD apt-get -y upgrade
  msg_ok "Base system updated"

  if command -v docker >/dev/null 2>&1; then
    msg_info "Updating Docker Engine"
    $STD apt-get install --only-upgrade -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    msg_ok "Docker Engine updated"

    if [ -d /opt/lancache ]; then
      msg_info "Refreshing Lancache stack"
      (cd /opt/lancache && $STD docker compose pull && $STD docker compose up -d)
      msg_ok "Lancache stack refreshed"
    fi
  fi
  msg_ok "Updated successfully!"
  exit
}

setup_lancache_host() {
  if [[ -z "${CTID}" ]]; then
    msg_error "Container ID not found. Please rerun the script."
    exit 1
  fi

  msg_info "Ensuring ${APP} storage selection"
  STORAGE_OPTIONS=()
  while read -r name type _; do
    if [[ -d "/mnt/pve/${name}" ]]; then
      STORAGE_OPTIONS+=("${name}" "${type} storage mounted at /mnt/pve/${name}" OFF)
    fi
  done < <(pvesm status --content rootdir | awk 'NR>1 {print $1" "$2}')

  if [[ ${#STORAGE_OPTIONS[@]} -eq 0 ]]; then
    msg_error "No mounted Proxmox storages with rootdir content were found."
    exit 1
  fi

  LANCACHE_STORAGE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "LANCACHE DATA STORAGE" --radiolist "Select a storage for Lancache data (mounted under /mnt/pve):" 15 78 6 ${STORAGE_OPTIONS[@]} 3>&1 1>&2 2>&3) || exit_script

  LANCACHE_BASE="/mnt/pve/${LANCACHE_STORAGE}/lancache-oci-host"
  mkdir -p "${LANCACHE_BASE}/data" "${LANCACHE_BASE}/logs"

  if pct status "${CTID}" | grep -q running; then
    pct stop "${CTID}" >/dev/null
  fi

  pct set "${CTID}" --mp0 "${LANCACHE_BASE}/data,mp=/opt/lancache/data" --mp1 "${LANCACHE_BASE}/logs,mp=/opt/lancache/logs" >/dev/null
  pct start "${CTID}" >/dev/null
  msg_ok "Lancache data will live on ${LANCACHE_STORAGE}"

  msg_info "Installing Docker Engine and Compose in CT ${CTID}"
  pct exec "${CTID}" -- bash -c "apt-get update && apt-get install -y ca-certificates curl gnupg lsb-release"
  pct exec "${CTID}" -- bash -c "install -m 0755 -d /etc/apt/keyrings"
  pct exec "${CTID}" -- bash -c "curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc"
  pct exec "${CTID}" -- bash -c "chmod a+r /etc/apt/keyrings/docker.asc"
  pct exec "${CTID}" -- bash -c "echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \$(. /etc/os-release && echo \"\$VERSION_CODENAME\") stable\" > /etc/apt/sources.list.d/docker.list"
  pct exec "${CTID}" -- bash -c "apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
  pct exec "${CTID}" -- systemctl enable --now docker >/dev/null 2>&1
  msg_ok "Docker installed in CT ${CTID}"

  msg_info "Creating Lancache stack files"
  pct exec "${CTID}" -- bash -c "mkdir -p /opt/lancache/data /opt/lancache/logs"
  pct exec "${CTID}" -- bash -c 'LANCACHE_IP=$(hostname -I | awk '"'"'{print $1}'"'"') && cat <<EOF >/opt/lancache/.env
LANCACHE_IP=${LANCACHE_IP}
UPSTREAM_DNS=1.1.1.1 1.0.0.1
CACHE_DISK_SIZE=1000g
CACHE_MEM_SIZE=512m
CACHE_MAX_AGE=3650d
EOF'
  pct exec "${CTID}" -- bash -c "cat <<'EOF' >/opt/lancache/docker-compose.yml
version: \"3.8\"
services:
  lancache-dns:
    image: lancachenet/lancache-dns:latest
    env_file:
      - .env
    environment:
      - USE_GENERIC_CACHE=true
    ports:
      - \"53:53/udp\"
      - \"53:53/tcp\"
    restart: unless-stopped

  monolithic:
    image: lancachenet/monolithic:latest
    env_file:
      - .env
    environment:
      - CACHE_DISK_SIZE=\${CACHE_DISK_SIZE}
      - CACHE_MEM_SIZE=\${CACHE_MEM_SIZE}
      - CACHE_MAX_AGE=\${CACHE_MAX_AGE}
    volumes:
      - ./data:/data/cache
      - ./logs:/data/logs
    ports:
      - \"80:80\"
    restart: unless-stopped

  sniproxy:
    image: lancachenet/sniproxy:latest
    env_file:
      - .env
    ports:
      - \"443:443\"
    restart: unless-stopped
EOF"
  msg_ok "Lancache stack files created"

  msg_info "Starting Lancache stack"
  pct exec "${CTID}" -- bash -c "cd /opt/lancache && docker compose up -d"
  msg_ok "Lancache stack started"
}

start
build_container
setup_lancache_host
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Lancache DNS listens on UDP/TCP 53, HTTP cache on 80, and SNI proxy on 443 inside CT ${CTID}.${CL}"
