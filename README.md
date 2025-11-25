# Custom Proxmox PVE Helper Scripts

This repository contains helper scripts for provisioning containers on Proxmox VE. The `lancache-oci-host.sh` script builds a Debian 13 (trixie) LXC tailored for running the Lancache stack with Docker.

## How to use
1. Copy the scripts to your Proxmox host (e.g., via `scp`), or clone/pull the repository directly onto the host.
2. Run the Lancache helper script from the Proxmox shell:
   ```bash
   bash lancache-oci-host.sh
   ```
   You will be prompted for the container ID, CPU/RAM/disk sizing, and which mounted Proxmox storage should hold Lancache data and logs.
3. After the script finishes, the container will have Docker installed and a Lancache stack running on ports 53 (TCP/UDP), 80, and 443.

If you want to publish your changes on GitHub, push this repository (including your edits) to your own GitHub remote. Otherwise, you can simply copy the scripts to any Proxmox host and run them locally—no GitHub upload is required.
