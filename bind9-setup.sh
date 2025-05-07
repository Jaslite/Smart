#!/bin/bash
# BIND9 Automated Setup Script
# Tested on debian-12.10.0-amd64-DVD-1

set -euo pipefail

# ========= CONFIGURABLE SECTION =========
DNS_DOMAIN="testcluster.local"  # Your cluster base domain e.g. ite.local
CLUSTER_NAME="kuanyong-ocp"                 # Your cluster name e.g. my-ocp
DNS_FORWARDERS=("48.64.208.22" "8.8.8.8" "8.8.4.4") # List of DNS forwarders, separated by space
DNS_SERVER_HOSTNAME="kuanyong-test-dns"         # Your DNS server hostname
JUMPHOST_IP="48.64.210.22"                    # IP of your DNS server (i.e jumphost)
API_VIP="48.64.210.23"                        # API VIP
APPS_VIP="48.64.210.24"                       # APPS VIP
NETWORK_CIDR="48.64.210.0/25"                 # Main subnet
REVERSE_ZONE="210.64.48.in-addr.arpa"          # Reverse zone name (i.e reverse the first 3 octets of your jumphost's IP address and append .in-addr.arpa)
# =========================================

# ========= LOGGING SETUP =========
LOG_FILE="/tmp/bind9-setup.log"
ERROR_LOG_FILE="/tmp/bind9-setup-error.log"
rm -f "$LOG_FILE" "$ERROR_LOG_FILE"
trap 'catch_error $LINENO' ERR

catch_error() {
    echo "[ERROR] Script failed at line $1. Check $ERROR_LOG_FILE for details."
    exit 1
}

exec > >(tee -a "$LOG_FILE") 2> >(tee -a "$ERROR_LOG_FILE" >&2)
echo "[INFO] [Step 0] Starting BIND9 Setup..."
# ==================================

# ========= HOSTS MAPPING =========
declare -A HOSTS
HOSTS=(
  ["api.${CLUSTER_NAME}"]="$API_VIP"
  ["api-int.${CLUSTER_NAME}"]="$API_VIP"
  ["${DNS_SERVER_HOSTNAME}"]="$JUMPHOST_IP"
  ["*.apps.${CLUSTER_NAME}"]="$APPS_VIP"
)

# Sorted list of hostnames
SORTED_HOSTNAMES=($(printf "%s\n" "${!HOSTS[@]}" | sort))
# ==================================

# Generate SERIAL number based on date (best practice)
SERIAL="$(date +%Y%m%d01)"

# STEP 1: Update system packages
echo "[INFO] [Step 1] Updating package index..."
sudo apt update -y || true

# STEP 2: Install BIND9
echo "[INFO] [Step 2] Installing bind9 and dnsutils..."
sudo apt install -y bind9 bind9utils bind9-doc dnsutils || true

# STEP 3: Configure Global Options
echo "[INFO] [Step 3] Configuring BIND9 global options..."
sudo bash -c "cat > /etc/bind/named.conf.options" <<EOF
acl "trusted" {
    ${NETWORK_CIDR};
    localhost;
    localnets;
};
options {
    directory "/var/cache/bind";
    recursion yes;
    allow-recursion { trusted; };
    allow-query { any; };
    forwarders {
$(for ip in "${DNS_FORWARDERS[@]}"; do echo "        $ip;"; done)
    };
    listen-on { any; };
    listen-on-v6 { none; };
    dnssec-validation no;
};
EOF

# STEP 4: Create zones directory
echo "[INFO] [Step 4] Creating zones directory if not exists..."
if [ ! -d "/etc/bind/zones" ]; then
    sudo mkdir -p /etc/bind/zones
fi

# STEP 5: Create Forward Zone File
echo "[INFO] [Step 5] Creating forward zone file for $DNS_DOMAIN..."
sudo bash -c "cat > /etc/bind/zones/db.${DNS_DOMAIN}" <<EOF
\$TTL    86400
@       IN      SOA     ${DNS_SERVER_HOSTNAME}.${DNS_DOMAIN}. root.${DNS_DOMAIN}. (
                     ${SERIAL}         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      ${DNS_SERVER_HOSTNAME}.${DNS_DOMAIN}.
EOF

for hostname in "${SORTED_HOSTNAMES[@]}"; do
    echo "$hostname    IN    A    ${HOSTS[$hostname]}" | sudo tee -a /etc/bind/zones/db.${DNS_DOMAIN}
done

# STEP 6: Create Reverse Zone File
echo "[INFO] [Step 6] Creating reverse zone file for $NETWORK_CIDR..."
sudo bash -c "cat > /etc/bind/zones/db.${REVERSE_ZONE}" <<EOF
\$TTL    86400
@       IN      SOA     ${DNS_SERVER_HOSTNAME}.${DNS_DOMAIN}. root.${DNS_DOMAIN}. (
                     ${SERIAL}         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      ${DNS_SERVER_HOSTNAME}.${DNS_DOMAIN}.
EOF

for hostname in "${SORTED_HOSTNAMES[@]}"; do
    # if [[ "$hostname" == "api-int.${CLUSTER_NAME}" ]]; then
    #     continue
    # fi
    IP="${HOSTS[$hostname]}"
    LAST_OCTET=$(echo "$IP" | awk -F '.' '{print $4}')

    CLEAN_HOSTNAME="$hostname"
    if [[ "$hostname" == \*.* ]]; then
        CLEAN_HOSTNAME="${hostname#*.}"
    fi

    echo "$LAST_OCTET    IN    PTR    $CLEAN_HOSTNAME.${DNS_DOMAIN}." | sudo tee -a /etc/bind/zones/db.${REVERSE_ZONE}
done


# STEP 7: Update named.conf.local
echo "[INFO] [Step 7] Updating named.conf.local to declare zones..."
sudo bash -c "cat > /etc/bind/named.conf.local" <<EOF
zone "${DNS_DOMAIN}" {
    type master;
    file "/etc/bind/zones/db.${DNS_DOMAIN}";
};

zone "${REVERSE_ZONE}" {
    type master;
    file "/etc/bind/zones/db.${REVERSE_ZONE}";
};
EOF

# STEP 8: Restart and Enable named.service
echo "[INFO] [Step 8] Restarting and enabling named service..."
sudo systemctl restart named
sudo systemctl enable named

# STEP 9: Script Success
echo "[SUCCESS] [Step 9] BIND9 DNS server is ready for OpenShift IPI installation!"
echo "[INFO] [Step 9] Logs saved at: $LOG_FILE"
echo "[INFO] [Step 9] Errors saved at: $ERROR_LOG_FILE"