#!/bin/bash
# Generate htpasswd hash for Traefik basic auth
# Usage: ./generate-htpasswd.sh username password

set -e

USERNAME="${1:-admin}"
PASSWORD="${2:-}"

if [ -z "$PASSWORD" ]; then
    echo "Usage: $0 <username> <password>"
    echo "Example: $0 admin mysecretpassword"
    exit 1
fi

# Check if htpasswd is available
if command -v htpasswd &> /dev/null; then
    HASH=$(htpasswd -nbB "$USERNAME" "$PASSWORD")
elif command -v openssl &> /dev/null; then
    # Fallback to openssl for apr1 hash
    HASH=$(openssl passwd -apr1 "$PASSWORD")
    HASH="${USERNAME}:${HASH}"
else
    echo "Error: Neither htpasswd nor openssl found."
    echo "Install apache2-utils (Debian/Ubuntu) or httpd-tools (RHEL/CentOS)"
    exit 1
fi

echo ""
echo "Generated credentials for Traefik basic auth:"
echo "=============================================="
echo ""
echo "For .env file (escape \$ as \$\$):"
echo "USERNAME=${USERNAME}"
echo "HASHED_PASSWORD='$(echo "$HASH" | cut -d: -f2 | sed "s/\\$/\\$\\$/g")'"
echo ""
echo "Full hash string:"
echo "$HASH"
echo ""
echo "For docker-compose.yml label (with \$\$ escaping):"
echo "$(echo "$HASH" | sed "s/\\$/\\$\\$/g")"
