#!/bin/bash

# Script untuk konfigurasi server dengan root privileges
# Script ini akan menggunakan sudo untuk setiap perintah yang memerlukan root privileges


echo "=== Starting server configuration ==="

# Install nano
echo "Installing nano..."
sudo dnf install nano -y

echo "=== Configuring SELinux ==="
# Disable SELinux
sudo setenforce 0
sudo sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
echo "SELinux configuration:"
grep ^SELINUX= /etc/selinux/config

echo "=== Configuring SSH ==="
# Remove cloud-init SSH config
echo "Removing cloud-init SSH config..."
sudo rm -rf /etc/ssh/sshd_config.d/50-cloud-init.conf
echo "SSH config directory contents:"
ls -la /etc/ssh/sshd_config.d/

# Configure SSH settings
echo "Configuring SSH settings..."

# Enable PubkeyAuthentication and disable PasswordAuthentication
sudo sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config

# Add the settings if they don't exist
if ! grep -q "^PubkeyAuthentication" /etc/ssh/sshd_config; then
    echo "PubkeyAuthentication yes" | sudo tee -a /etc/ssh/sshd_config
fi

if ! grep -q "^PasswordAuthentication" /etc/ssh/sshd_config; then
    echo "PasswordAuthentication no" | sudo tee -a /etc/ssh/sshd_config
fi

echo "SSH configuration updated."

echo "=== Stopping Cloud-Init and Cockpit services ==="
# Stop services
sudo systemctl stop cloud-config.service \
  cloud-final.service \
  cloud-init-hotplugd.service \
  cloud-init-local.service \
  cloud-init.service \
  cloud-init-hotplugd.socket \
  cloud-config.target \
  cloud-init.target \
  cockpit 2>/dev/null || echo "Some services may not exist, continuing..."

# Disable services
sudo systemctl disable cloud-config.service \
  cloud-final.service \
  cloud-init-hotplugd.service \
  cloud-init-local.service \
  cloud-init.service \
  cloud-init-hotplugd.socket \
  cloud-config.target \
  cloud-init.target \
  cockpit 2>/dev/null || echo "Some services may not exist, continuing..."

# Mask services
sudo systemctl mask cloud-config.service \
  cloud-final.service \
  cloud-init-hotplugd.service \
  cloud-init-local.service \
  cloud-init.service \
  cloud-init-hotplugd.socket \
  cloud-config.target \
  cloud-init.target \
  cockpit.socket \
  cockpit.service 2>/dev/null || echo "Some services may not exist, continuing..."

echo "=== Removing Cloud-Init and Cockpit packages ==="
# Remove packages
sudo dnf remove cloud* cockpit* -y
sudo dnf autoremove -y

echo "=== Cleaning up Cloud-Init and Cockpit files ==="
# Remove directories and files
sudo rm -rf /etc/cloud
sudo rm -rf /var/lib/cloud
sudo rm -rf /var/log/cloud-init.log /var/log/cloud-init-output.log
sudo rm -rf /etc/cockpit
sudo rm -rf /run/cockpit
sudo rm -rf /var/lib/cockpit
sudo rm -rf /var/log/cockpit
sudo rm -rf /usr/share/cockpit
sudo rm -rf /etc/issue.d/cockpit.issue
sudo rm -rf /etc/motd.d/cockpit
sudo rm -rf /usr/lib/tmpfiles.d/cockpit-ws.conf

echo "=== Cleaning up Network Configuration files ==="
# Remove all files in NetworkManager system-connections directory
echo "Removing NetworkManager system connections..."
sudo rm -rf /etc/NetworkManager/system-connections/*

# Remove all files in network-scripts directory
echo "Removing network scripts..."
sudo rm -rf /etc/sysconfig/network-scripts/*
echo "Network configuration files cleaned up."

echo "=== Creating new network interface configuration files ==="
# Get network interfaces (skip loopback)
INTERFACES=($(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | head -3))

echo "Detected interfaces: ${INTERFACES[@]}"

# Create ifcfg for second interface (index 1) - DHCP
if [ "${INTERFACES[1]}" ]; then
    INTERFACE2="${INTERFACES[1]}"
    MAC2=$(ip link show $INTERFACE2 | awk '/ether/ {print $2}')
    
    echo "Creating ifcfg-$INTERFACE2 (DHCP) with MAC: $MAC2"
    sudo tee /etc/sysconfig/network-scripts/ifcfg-$INTERFACE2 > /dev/null <<EOF
TYPE=Ethernet
HWADDR=$MAC2
PROXY_METHOD=none
BROWSER_ONLY=no
BOOTPROTO=dhcp
DEFROUTE=yes
IPV4_FAILURE_FATAL=yes
IPV6_DISABLED=yes
IPV6INIT=no
IPV6_DEFROUTE=no
IPV6_FAILURE_FATAL=no
NAME=$INTERFACE2
DEVICE=$INTERFACE2
ONBOOT=yes
PEERDNS=no
DNS1=1.1.1.1
DNS2=1.0.0.1
DNS3=8.8.8.8
DNS4=8.8.4.4
METRIC=100
AUTOCONNECT_PRIORITY=120
EOF
    echo "Created ifcfg-$INTERFACE2 with MAC: $MAC2"
fi

# Create ifcfg for third interface (index 2) - Static IP
if [ "${INTERFACES[2]}" ]; then
    INTERFACE3="${INTERFACES[2]}"
    MAC3=$(ip link show $INTERFACE3 | awk '/ether/ {print $2}')
    
    echo "Creating ifcfg-$INTERFACE3 (Static IP)..."
    sudo tee /etc/sysconfig/network-scripts/ifcfg-$INTERFACE3 > /dev/null <<EOF
TYPE=Ethernet
HWADDR=$MAC3
PROXY_METHOD=none
BROWSER_ONLY=no
BOOTPROTO=none
IPADDR=172.30.20.10
PREFIX=24
DEFROUTE=no
IPV4_FAILURE_FATAL=yes
IPV6_DISABLED=yes
IPV6INIT=no
IPV6_DEFROUTE=no
IPV6_FAILURE_FATAL=no
NAME=$INTERFACE3
DEVICE=$INTERFACE3
ONBOOT=yes
PEERDNS=no
METRIC=200
AUTOCONNECT_PRIORITY=120
EOF
    echo "Created ifcfg-$INTERFACE3 with MAC: $MAC3"
fi

echo "Network interface configuration files created."

echo "=== Configuring /etc/hosts file ==="
# Add cluster nodes to hosts file
echo "Adding cluster nodes to /etc/hosts..."
sudo tee -a /etc/hosts > /dev/null <<EOF

# Kubernetes Cluster Nodes
172.30.20.10    node-master-1
172.30.20.11    node-master-2
172.30.20.12    node-master-3
172.30.20.20    node-worker-1
172.30.20.21    node-worker-2
172.30.20.22    node-worker-3
EOF

echo "/etc/hosts file updated with cluster nodes."
echo "Current /etc/hosts content:"
cat /etc/hosts

echo "=== Adding package exclusion to DNF ==="
# Add exclusion to DNF config
echo "exclude=cockpit* cloud-init*" | tee -a /etc/dnf/dnf.conf

echo "=== Setting Timezone ==="
# Set timezone to Asia/Jakarta
sudo timedatectl set-timezone Asia/Jakarta
sudo timedatectl set-ntp on

echo "=== Configuration completed successfully ==="
echo "Current timezone:"
timedatectl status
