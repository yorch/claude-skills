#!/bin/bash
# Check if traefik network exists and optionally create it
# Usage: ./check-network.sh [--create]

set -e

NETWORK_NAME="traefik"
CREATE_IF_MISSING=false

if [ "$1" = "--create" ] || [ "$1" = "-c" ]; then
    CREATE_IF_MISSING=true
fi

echo "Checking for Docker network: $NETWORK_NAME"
echo "============================================"

# Check if Docker is running
if ! docker info &> /dev/null; then
    echo "❌ Error: Docker is not running or not accessible"
    exit 1
fi

# Check if network exists
if docker network ls --format '{{.Name}}' | grep -q "^${NETWORK_NAME}$"; then
    echo "✅ Network '$NETWORK_NAME' exists"
    echo ""
    echo "Network details:"
    docker network inspect "$NETWORK_NAME" --format '
  Driver: {{.Driver}}
  Scope: {{.Scope}}
  Containers: {{len .Containers}}'
    
    # List connected containers
    CONTAINERS=$(docker network inspect "$NETWORK_NAME" --format '{{range .Containers}}{{.Name}} {{end}}')
    if [ -n "$CONTAINERS" ]; then
        echo "  Connected: $CONTAINERS"
    fi
else
    echo "⚠️  Network '$NETWORK_NAME' does not exist"
    
    if [ "$CREATE_IF_MISSING" = true ]; then
        echo ""
        echo "Creating network '$NETWORK_NAME'..."
        docker network create "$NETWORK_NAME"
        echo "✅ Network created successfully"
    else
        echo ""
        echo "To create it, run:"
        echo "  docker network create $NETWORK_NAME"
        echo ""
        echo "Or run this script with --create flag:"
        echo "  $0 --create"
        exit 1
    fi
fi

echo ""
echo "============================================"
echo "All checks passed!"
