#!/bin/bash

CERT_FILE="/opt/ati/config/fm_rev_proxy_cert.pem"
TMP_CERT="/tmp/fm_full_chain.pem"
FM_IP=""

show_help() {
    echo "Usage: $0 --ip <FM_IP>"
    echo ""
    echo "Fetches, verifies, and installs the reverse proxy certificate for mule_comms."
    echo ""
    echo "Options:"
    echo "  --ip <IP>       Specify the IPv4 address of the Fleet Manager."
    echo "  -h, --help      Display this help message and exit."
}

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --ip)
            FM_IP="$2"
            shift 2
            ;;
        *)
            echo "Error: Unknown parameter passed: $1"
            show_help
            exit 1
            ;;
    esac
done

# Ensure the IP argument was provided
if [ -z "${FM_IP}" ]; then
    echo "Error: The --ip argument is required."
    show_help
    exit 1
fi

BACKUP_FILE="${CERT_FILE}.bak.$(date +%Y%m%d%H%M%S)"

echo "Initiating certificate sync for FM_IP: ${FM_IP}"

# 1. Backup the current certificate
echo "Backing up existing certificate to ${BACKUP_FILE}..."
sudo cp "${CERT_FILE}" "${BACKUP_FILE}"

# 2. Fetch the certificate chain from the target IP
echo "Fetching certificate chain from ${FM_IP}:443..."
echo | openssl s_client -connect "${FM_IP}:443" -showcerts 2>/dev/null \
    | awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/' > "${TMP_CERT}"

# Verify we actually downloaded something
if [ ! -s "${TMP_CERT}" ]; then
    echo "FAILED: Downloaded certificate is empty. Check connectivity to ${FM_IP}:443."
    exit 1
fi

# 3. Verify the downloaded certificate chain
echo "Verifying the certificate chain..."
if openssl s_client -connect "${FM_IP}:443" -CAfile "${TMP_CERT}" </dev/null 2>&1 | grep -q "Verify return code: 0"; then
    
    # 4. Apply the new certificate and restart the container
    echo "Verification successful. Overwriting configuration..."
    sudo cp "${TMP_CERT}" "${CERT_FILE}"
    
    echo "Restarting mule_comms..."
    sudo docker restart mule_comms
    
    echo "OK: cert synced and mule_comms restarted"
else
    # 5. Handle verification failure
    echo "FAILED: chain didn't verify — check FM's cert manually before overwriting"
    exit 1
fi
