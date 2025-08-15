#!/bin/bash
# Network Restrictions Setup Script
# Configures iptables rules to restrict network access to specified domains

set -e

# Configuration file path
CONFIG_FILE="${NETWORK_RESTRICTIONS_CONFIG:-/workspace/.devcontainer/config/allowed-networks.json}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root"
   exit 1
fi

# Check for required tools
for tool in iptables ipset jq dig curl; do
    if ! command -v $tool &> /dev/null; then
        log_error "Required tool '$tool' is not installed"
        exit 1
    fi
done

# Parse configuration
CONFIG=$(cat "$CONFIG_FILE")
ALLOWED_DOMAINS=$(echo "$CONFIG" | jq -r '.allowed_domains[]' 2>/dev/null || echo "")
ALLOWED_NETWORKS=$(echo "$CONFIG" | jq -r '.allowed_networks[]' 2>/dev/null || echo "")
ALLOW_DNS=$(echo "$CONFIG" | jq -r '.allow_dns // true')
ALLOW_SSH=$(echo "$CONFIG" | jq -r '.allow_ssh // true')
ALLOW_LOCALHOST=$(echo "$CONFIG" | jq -r '.allow_localhost // true')
ALLOW_HOST_NETWORK=$(echo "$CONFIG" | jq -r '.allow_host_network // true')

log_info "Starting network restrictions setup..."

# Preserve Docker's internal DNS configuration
log_info "Preserving Docker DNS configuration..."
DOCKER_DNS_CONFIG=$(iptables-save | grep -E "DOCKER|127\.0\.0\.11" || true)

# Reset firewall rules
log_info "Resetting firewall rules..."
for table in filter nat mangle; do
    iptables -t $table -F 2>/dev/null || true
    iptables -t $table -X 2>/dev/null || true
done

# Clean up existing ipset
ipset destroy network-whitelist 2>/dev/null || true

# Restore Docker DNS if found
if [[ -n "$DOCKER_DNS_CONFIG" ]]; then
    log_info "Restoring Docker DNS configuration..."
    echo "$DOCKER_DNS_CONFIG" | while read -r rule; do
        if [[ $rule =~ ^-A ]]; then
            # Extract table from context
            table=$(echo "$rule" | grep -oP '^\*\K[a-z]+' || echo "filter")
            iptables -t ${table:-filter} $rule 2>/dev/null || true
        fi
    done
fi

# Create new ipset for allowed networks
log_info "Creating network whitelist..."
ipset create network-whitelist hash:net family inet

# Set up basic allowed traffic
if [[ "$ALLOW_LOCALHOST" == "true" ]]; then
    log_info "Allowing localhost traffic..."
    iptables -I INPUT -i lo -j ACCEPT
    iptables -I OUTPUT -o lo -j ACCEPT
fi

if [[ "$ALLOW_DNS" == "true" ]]; then
    log_info "Allowing DNS traffic..."
    iptables -I OUTPUT -p udp --dport 53 -j ACCEPT
    iptables -I OUTPUT -p tcp --dport 53 -j ACCEPT
    iptables -I INPUT -p udp --sport 53 -j ACCEPT
    iptables -I INPUT -p tcp --sport 53 -j ACCEPT
fi

if [[ "$ALLOW_SSH" == "true" ]]; then
    log_info "Allowing SSH traffic..."
    iptables -I OUTPUT -p tcp --dport 22 -j ACCEPT
    iptables -I INPUT -p tcp --sport 22 -m conntrack --ctstate ESTABLISHED -j ACCEPT
fi

# Allow established connections
log_info "Allowing established connections..."
iptables -I INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -I OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT


# Add allowed networks from config
if [[ -n "$ALLOWED_NETWORKS" ]]; then
    echo "$ALLOWED_NETWORKS" | while read -r network; do
        if [[ -n "$network" ]]; then
            log_info "Adding configured network: $network"
            ipset add network-whitelist "$network" 2>/dev/null || log_warn "Failed to add $network"
        fi
    done
fi

# Resolve and add allowed domains
if [[ -n "$ALLOWED_DOMAINS" ]]; then
    echo "$ALLOWED_DOMAINS" | while read -r domain; do
        if [[ -n "$domain" ]]; then
            log_info "Resolving domain: $domain"
            
            # Resolve IPv4 addresses
            IP_LIST=$(dig +short A "$domain" 2>/dev/null | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' || echo "")
            
            if [[ -n "$IP_LIST" ]]; then
                echo "$IP_LIST" | while read -r ip; do
                    log_info "  Adding IP: $ip"
                    ipset add network-whitelist "$ip/32" 2>/dev/null || log_warn "  Failed to add $ip"
                done
            else
                log_warn "  No IPs resolved for $domain"
            fi
        fi
    done
fi

# Handle host network access
if [[ "$ALLOW_HOST_NETWORK" == "true" ]]; then
    log_info "Detecting host network..."
    
    # Try multiple methods to detect host network
    HOST_IP=""
    
    # Method 1: Default route
    HOST_IP=$(ip route show default 2>/dev/null | grep -oP 'via \K[0-9.]+' | head -1 || echo "")
    
    # Method 2: Docker host gateway
    if [[ -z "$HOST_IP" ]]; then
        HOST_IP=$(getent hosts host.docker.internal 2>/dev/null | awk '{print $1}' | head -1 || echo "")
    fi
    
    if [[ -n "$HOST_IP" ]]; then
        # Allow host gateway
        log_info "Allowing host gateway: $HOST_IP"
        iptables -I OUTPUT -d "$HOST_IP" -j ACCEPT
        iptables -I INPUT -s "$HOST_IP" -j ACCEPT
        
        # Allow host subnet (assuming /24)
        HOST_SUBNET=$(echo "$HOST_IP" | sed 's/\.[0-9]*$/.0\/24/')
        log_info "Allowing host subnet: $HOST_SUBNET"
        ipset add network-whitelist "$HOST_SUBNET" 2>/dev/null || true
    else
        log_warn "Could not detect host network"
    fi
fi

# Apply whitelist rules
log_info "Applying network whitelist rules..."
iptables -A OUTPUT -m set --match-set network-whitelist dst -j ACCEPT
iptables -A INPUT -m set --match-set network-whitelist src -j ACCEPT

# Set default policies
log_info "Setting default policies to DROP..."
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# Verification
log_info "Verifying configuration..."

# Test blocked domain
if curl --connect-timeout 5 -s https://example.com >/dev/null 2>&1; then
    log_warn "Verification warning: Can reach example.com (should be blocked)"
else
    log_info "Verification passed: Cannot reach example.com (blocked)"
fi

# Test allowed domain (if GitHub is in the list)
if echo "$ALLOWED_DOMAINS" | grep -q "github.com"; then
    if curl --connect-timeout 5 -s https://api.github.com/zen >/dev/null 2>&1; then
        log_info "Verification passed: Can reach api.github.com (allowed)"
    else
        log_warn "Verification warning: Cannot reach api.github.com (should be allowed)"
    fi
fi

log_info "Network restrictions setup complete!"
log_info "Configuration file: $CONFIG_FILE"

# Show summary
echo ""
log_info "Summary:"
echo "  - Allowed domains: $(echo "$ALLOWED_DOMAINS" | wc -l)"
echo "  - Allowed networks: $(echo "$ALLOWED_NETWORKS" | grep -v '^$' | wc -l)"
echo "  - Total whitelist entries: $(ipset list network-whitelist | grep -c '^[0-9]' || echo 0)"
