#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Config
CONFIG_FILE="/usr/local/etc/xray/config.json"
SERVICE_NAME="xray"
USE_IPV6=false
IPV6_AVAILABLE=false

# Check IPv6 availability
check_ipv6() {
    if ip -6 addr show | grep -q global; then
        IPV6_AVAILABLE=true
    fi
}

select_ip_version() {
    # check IPv6
    check_ipv6
    
    if [[ "$1" == "install" ]]; then
        echo -e "\n${YELLOW}Select IP version:${NC}"
        echo "1. IPv4 (default)"
        
        # Show IPv6 if available
        if $IPV6_AVAILABLE; then
            echo "2. IPv6"
            max_choice=2
        else
            max_choice=1
        fi
        
        while true; do
            read -p "Your choice [1-$max_choice]: " choice
            case $choice in
                1|"")
                    USE_IPV6=false
                    echo -e "${GREEN}Selected IPv4${NC}"
                    break
                    ;;
                2)
                    if $IPV6_AVAILABLE; then
                        USE_IPV6=true
                        echo -e "${GREEN}Selected IPv6${NC}"
                        break
                    else
                        echo -e "${RED}IPv6 not available on this server!${NC}"
                    fi
                    ;;
                *)
                    echo -e "${RED}Invalid choice! Please enter 1 or ${max_choice}${NC}"
                    ;;
            esac
        done
    else
        # Reconfig mode
        if $IPV6_AVAILABLE; then
            current_version="IPv$( [[ "$USE_IPV6" == true ]] && echo "6" || echo "4")"
            echo -e "\n${YELLOW}Current IP version: $current_version${NC}"
            read -p "Switch to IPv6? [y/N]: " switch
            if [[ "$switch" =~ [yY] ]]; then
                USE_IPV6=true
                echo -e "${GREEN}Switched to IPv6${NC}"
            else
                USE_IPV6=false
                echo -e "${GREEN}Keeping IPv4${NC}"
            fi
        else
            USE_IPV6=false
            echo -e "${YELLOW}IPv6 not available, using IPv4${NC}"
        fi
    fi
    
    # logs
    echo -e "${BLUE}Using IPv$( [[ "$USE_IPV6" == true ]] && echo "6" || echo "4") configuration${NC}"
}

# Get current server IP
get_current_ip() {
    if $USE_IPV6; then
        ip -6 addr show | awk '/global/{print $2}' | cut -d'/' -f1 | head -n1
    else
        ip -4 addr show | awk '/global/{print $2}' | cut -d'/' -f1 | head -n1
    fi
}

# Check if Xray is installed
check_xray_installed() {
    if [[ -f "/usr/local/bin/xray" ]]; then
        return 0
    else
        return 1
    fi
}

# Update Xray config for IP version
update_config_ip_version() {
    local config_file="$1"
    local ipv6only="$2"
    
    jq --argjson ipv6only "$ipv6only" \
       '.inbounds[0].ipv6only = $ipv6only |
        .outbounds[0].settings.domainStrategy = (if $ipv6only then "UseIPv6" else "UseIP" end)' \
       "$config_file" > tmp.json && mv tmp.json "$config_file"
}

# Uninstall Xray
uninstall_xray() {
    echo -e "${YELLOW}Uninstalling Xray...${NC}"
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove
    echo -e "${GREEN}Xray has been uninstalled!${NC}"
    exit 0
}

# Function firewall configuration
configure_firewall() {
    # Check installed firewall
    if command -v ufw &> /dev/null; then
        echo -e "${YELLOW}Configuration UFW...${NC}"
        
        # Check status
        if ! ufw status | grep -q "Status: active"; then
            echo -e "${YELLOW}Activate UFW...${NC}"
            ufw --force enable
        fi
        
        # Check port SSH
        SSH_PORT=$(ss -tlnp | grep sshd | awk '{print $4}' | cut -d':' -f2 | head -n1)
        if [ -z "$SSH_PORT" ]; then
            SSH_PORT=22
        fi
        
        # Add rules
        echo -e "${YELLOW}Open port $SSH_PORT (SSH)...${NC}"
        ufw allow $SSH_PORT/tcp
        
        echo -e "${YELLOW}Open port 443 (Xray)...${NC}"
        ufw allow 443/tcp
        
        # Check rules
        echo -e "${GREEN}Current rules UFW:${NC}"
        ufw status numbered

    elif command -v iptables &> /dev/null; then
        echo -e "${YELLOW}Configuration iptables...${NC}"
        
        # Check port SSH
        SSH_PORT=$(ss -tlnp | grep sshd | awk '{print $4}' | cut -d':' -f2 | head -n1)
        if [ -z "$SSH_PORT" ]; then
            SSH_PORT=22
        fi
        
        # Add rules
        echo -e "${YELLOW}Open port $SSH_PORT (SSH)...${NC}"
        iptables -A INPUT -p tcp --dport $SSH_PORT -j ACCEPT
        
        echo -e "${YELLOW}Open port 443 (Xray)...${NC}"
        iptables -A INPUT -p tcp --dport 443 -j ACCEPT
        
        # Save rules for reboot
        if [ -f /etc/iptables/rules.v4 ]; then
            iptables-save > /etc/iptables/rules.v4
        elif [ -d /etc/sysconfig ]; then
            iptables-save > /etc/sysconfig/iptables
        fi

        # Check rules
        echo -e "${GREEN}Current rules iptables:${NC}"
        iptables -L -n --line-numbers

    else
        echo -e "${YELLOW}Firewall not found, installing UFW...${NC}"
        
        # Instal UFW
        if command -v apt &> /dev/null; then
            apt update && apt install -y ufw
        elif command -v yum &> /dev/null; then
            yum install -y ufw
        elif command -v dnf &> /dev/null; then
            dnf install -y ufw
        else
            echo -e "${RED}Installig firewall failed!${NC}"
            return 1
        fi
        
        # Call function recursive for configuration
        configure_firewall
        return $?
    fi
    
    echo -e "${GREEN}Firewall configuration finished!${NC}"
}

# Function to check opened ports
check_ports() {
    echo -e "${YELLOW}Check opened ports...${NC}"
    
    # Check port 443
    if ss -tln | grep -q ':443 '; then
        echo -e "${GREEN}Port 443 opened${NC}"
    else
        echo -e "${RED}Port 443 closed!${NC}"
        return 1
    fi
    
    # Check port SSH
    SSH_PORT=$(ss -tlnp | grep sshd | awk '{print $4}' | cut -d':' -f2 | head -n1)
    if [ -z "$SSH_PORT" ]; then
        SSH_PORT=22
    fi
    
    if ss -tln | grep -q ":${SSH_PORT} "; then
        echo -e "${GREEN}SSH port $SSH_PORT opened${NC}"
    else
        echo -e "${RED}SSH port $SSH_PORT closed!${NC}"
        return 1
    fi
    
    return 0
}

check_write_permissions() {
    local dir="/usr/local/etc/xray"
    
    # Создать директорию если не существует
    if [ ! -d "$dir" ]; then
        echo -e "${YELLOW}Dir xray config creation $dir${NC}"
        mkdir -p "$dir" || {
            echo -e "${RED}error: Failed dir creation $dir${NC}"
            return 1
        }
    fi
    
    # Проверить права
    if [ ! -w "$dir" ]; then
        echo -e "${YELLOW}Trying change rights on $dir${NC}"
        chown -R root:root "$dir"
        chmod -R 755 "$dir"
        
        if [ ! -w "$dir" ]; then
            echo -e "${RED}Error: No rights to write $dir${NC}"
            echo -e "${YELLOW}Try to use manually: sudo chown -R $(whoami) $dir${NC}"
            return 1
        fi
    fi
    
    return 0
}

#Install xray
install_xray() {
    check_ipv6
    select_ip_version "install"

    echo -e "${YELLOW}Installing dependencies (jq, qrencode, openssl)...${NC}"
    
    if command -v apt &> /dev/null; then
        sudo apt update
        sudo apt install -y jq qrencode openssl curl
    elif command -v yum &> /dev/null; then
        sudo yum install -y epel-release
        sudo yum install -y jq qrencode openssl curl
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y jq qrencode openssl curl
    else
        echo -e "${RED}Could not detect package manager! Install dependencies manually.${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}Installing Xray...${NC}"
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --version 25.8.3
    
    # Fix systemd service file
    sudo sed -i 's/User=nobody/User=root/' /etc/systemd/system/xray.service
    sudo sed -i 's/DynamicUser=yes/DynamicUser=no/' /etc/systemd/system/xray.service
    
    systemctl daemon-reload
    systemctl enable $SERVICE_NAME
    
    # Firewall config
    configure_firewall
    
    echo -e "${GREEN}Xray installed successfully!${NC}"
}

# Generate UUID
generate_uuid() {
    UUID=$(xray uuid)
    echo -e "${GREEN}UUID: $UUID${NC}"
}

# Generate x25519 keys
generate_keys() {
    KEYS=$(xray x25519)
    PRIVATE_KEY=$(echo "$KEYS" | grep 'Private key:' | awk '{print $3}')
    PUBLIC_KEY=$(echo "$KEYS" | grep 'Public key:' | awk '{print $3}')
    echo -e "${GREEN}Private Key: $PRIVATE_KEY${NC}"
    echo -e "${GREEN}Public Key: $PUBLIC_KEY${NC}"
}

# Check domain for TLS 1.3
check_tls1_3() {
    while true; do
        read -p "Enter domain to check (e.g., example.com): " DOMAIN
        echo -e "${YELLOW}Checking $DOMAIN for TLS 1.3 support...${NC}"
        
        RESPONSE=$(curl -4 -sI --tlsv1.3 "https://$DOMAIN" 2>&1)
        if [[ $RESPONSE == *"HTTP/"* ]]; then
            echo -e "${GREEN}$DOMAIN supports TLS 1.3!${NC}"
            break
        else
            echo -e "${RED}$DOMAIN does NOT support TLS 1.3!${NC}"
            read -p "Try another domain? (y/n): " CHOICE
            [[ "$CHOICE" != "y" ]] && exit 1
        fi
    done
}

# Create initial config
create_config() {
    check_tls1_3 || return 1
    generate_uuid || return 1
    generate_keys || return 1
    generate_short_ids || return 1
    check_write_permissions || return 1

    local temp_file=$(mktemp)

    
    cat > "$temp_file" <<EOF
{
    "log": {
        "loglevel": "debug"
    },
    "inbounds": [
        {
            "port": 443,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "$UUID",
                        "flow": "xtls-rprx-vision"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "dest": "$DOMAIN:443",
                    "serverNames": ["$DOMAIN"],
                    "privateKey": "$PRIVATE_KEY",
                    "publicKey": "$PUBLIC_KEY",
                    "shortIds": $(printf '%s\n' "${SHORT_IDS[@]}" | jq -R . | jq -s .)
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls", "quic"],
                "routeOnly": true
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "tag": "direct",
            "settings": {}
        }
    ]
}
EOF

    # Add IP version settings
    jq --argjson ipv6only "$USE_IPV6" \
       '.inbounds[0].ipv6only = $ipv6only |
        .outbounds[0].settings.domainStrategy = (if $ipv6only then "UseIPv6" else "UseIP" end)' \
       "$temp_file" > "$CONFIG_FILE"

    # Check file exists
    if [ ! -s "$CONFIG_FILE" ]; then
        echo -e "${RED}Error: Failed to create configuration file${NC}"
        return 1
    fi

    # Validate JSON
    if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
        echo -e "${RED}Error: Invalid JSON configuration${NC}"
        return 1
    fi

    echo -e "${GREEN}Configuration successfully created at $CONFIG_FILE${NC}"
    systemctl restart "$SERVICE_NAME"
    rm -f "$temp_file"
    return 0
}

# Load existing config
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        UUID=$(jq -r '.inbounds[0].settings.clients[0].id' $CONFIG_FILE 2>/dev/null)
        PRIVATE_KEY=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' $CONFIG_FILE 2>/dev/null)
        PUBLIC_KEY=$(jq -r '.inbounds[0].streamSettings.realitySettings.publicKey' $CONFIG_FILE 2>/dev/null)
        DOMAIN=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' $CONFIG_FILE 2>/dev/null)
        SHORT_IDS=($(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[]' $CONFIG_FILE 2>/dev/null))
    fi
}

# Generate shortIds
generate_short_ids() {
    read -p "How many shortIds to generate? (default: 3): " COUNT
    COUNT=${COUNT:-3}
    SHORT_IDS=()
    for ((i=0; i<$COUNT; i++)); do
        SHORT_ID=$(openssl rand -hex 2)
        SHORT_IDS+=("$SHORT_ID")
    done
    echo -e "${GREEN}Generated shortIds: ${SHORT_IDS[@]}${NC}"
}

# Add shortId
add_short_id() {
    NEW_SHORT=$(openssl rand -hex 2)
    echo -e "${GREEN}Generated new shortId: $NEW_SHORT${NC}"
    
    CURRENT_SHORTS=$(jq '.inbounds[0].streamSettings.realitySettings.shortIds' $CONFIG_FILE)
    NEW_SHORTS=$(echo "$CURRENT_SHORTS" | jq ". += [\"$NEW_SHORT\"]")
    
    jq --argjson new_shorts "$NEW_SHORTS" \
       '.inbounds[0].streamSettings.realitySettings.shortIds = $new_shorts' \
       $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
    
    systemctl restart $SERVICE_NAME
    echo -e "${GREEN}ShortId added successfully!${NC}"
}

# Remove shortId
remove_short_id() {
    CURRENT_SHORTS=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[]' $CONFIG_FILE)
    if [[ -z "$CURRENT_SHORTS" ]]; then
        echo -e "${RED}No shortIds found in config!${NC}"
        return
    fi

    echo "Current shortIds:"
    i=1
    while read -r id; do
        echo "$i. $id"
        ((i++))
    done <<< "$CURRENT_SHORTS"

    read -p "Select shortId to remove (1-$((i-1))): " SELECTION
    if [[ $SELECTION -ge 1 && $SELECTION -lt $i ]]; then
        jq "del(.inbounds[0].streamSettings.realitySettings.shortIds[$((SELECTION-1))])" \
           $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
        systemctl restart $SERVICE_NAME
        echo -e "${GREEN}ShortId removed successfully!${NC}"
    else
        echo -e "${RED}Invalid selection!${NC}"
    fi
}

# Generate client config
generate_client_config() {
    load_config
    
    if [[ -z "$UUID" || -z "$PUBLIC_KEY" || -z "$DOMAIN" || ${#SHORT_IDS[@]} -eq 0 ]]; then
        echo -e "${RED}Error: Missing required configuration parameters!${NC}"
        return
    fi

    CURRENT_IP=$(get_current_ip)
    [[ -z "$CURRENT_IP" ]] && CURRENT_IP=$(hostname -I | awk '{print $1}')

    # Show list available shortIds
    echo -e "${YELLOW}Available shortIds:${NC}"
    for i in "${!SHORT_IDS[@]}"; do
        echo "$((i+1)). ${SHORT_IDS[$i]}"
    done

    # Select shortId
    read -p "Select shortId to use (1-${#SHORT_IDS[@]}): " SELECTION
    if [[ $SELECTION -lt 1 || $SELECTION -gt ${#SHORT_IDS[@]} ]]; then
        echo -e "${RED}Invalid selection! Using first shortId.${NC}"
        SELECTED_SHORT_ID="${SHORT_IDS[0]}"
    else
        SELECTED_SHORT_ID="${SHORT_IDS[$((SELECTION-1))]}"
    fi

    # Remove quotes
    SELECTED_SHORT_ID=$(echo "$SELECTED_SHORT_ID" | tr -d '"')

    # Gen link vless://
    VLESS_LINK="vless://${UUID}@${CURRENT_IP}:443?security=reality&encryption=none&pbk=${PUBLIC_KEY}&host=${DOMAIN}&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sid=${SELECTED_SHORT_ID}#xray-reality-${SELECTED_SHORT_ID}"

    echo -e "\n${YELLOW}Client configuration:${NC}"
    echo -e "${GREEN}${VLESS_LINK}${NC}"
    echo ""
    
    # Gen QR-code
    echo "$VLESS_LINK" | qrencode -t ANSIUTF8
    echo -e "${GREEN}Scan this QR code with v2rayNG!${NC}"
    
    # Save link to file
    echo "$VLESS_LINK" > "xray_${SELECTED_SHORT_ID}.txt"
    echo -e "${YELLOW}Link saved to xray_reality_${SELECTED_SHORT_ID}.txt${NC}"
}

# Function to switch IP version
switch_ip_version() {
    check_ipv6
    select_ip_version
    
    # Update config
    update_config_ip_version "$CONFIG_FILE" "$USE_IPV6"
    
    # Restart service
    systemctl restart "$SERVICE_NAME"
    
    echo -e "${GREEN}IP version switched to ${USE_IPV6:-false}${NC}"
    echo -e "${YELLOW}Current server IP: $(get_current_ip)${NC}"
}

# Main menu
main_menu() {
    if ! check_xray_installed; then
        echo -e "${YELLOW}Xray not found. Installing...${NC}"
        install_xray
        create_config
        generate_client_config
    else
        load_config
        
        while true; do
            echo -e "\n${GREEN}Xray Management Menu${NC}"
            echo "1. Generate new UUID"
            echo "2. Generate new x25519 keys"
            echo "3. Change domain"
            echo "4. Add client (shortId)"
            echo "5. Remove client (shortId)"
            echo "6. Show client config (QR)"
            echo "7. Change IP v4 or v6"
            echo "8. Check Firewall"
            echo "9. Uninstall Xray"
            echo "10. Exit"
            read -p "Choose option: " OPTION

            case $OPTION in
                1)
                    generate_uuid
                    jq --arg uuid "$UUID" '.inbounds[0].settings.clients[0].id = $uuid' $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
                    systemctl restart $SERVICE_NAME
                    ;;
                2)
                    generate_keys
                    jq --arg priv "$PRIVATE_KEY" '.inbounds[0].streamSettings.realitySettings.privateKey = $priv' $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
                    jq --arg pub "$PUBLIC_KEY" '.inbounds[0].streamSettings.realitySettings.publicKey = $pub' $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
                    systemctl restart $SERVICE_NAME
                    ;;
                3)
                    check_tls1_3
                    jq --arg domain "$DOMAIN" '.inbounds[0].streamSettings.realitySettings.dest = ($domain + ":443") | .inbounds[0].streamSettings.realitySettings.serverNames = [$domain]' $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
                    systemctl restart $SERVICE_NAME
                    ;;
                4)
		    add_short_id
                    ;;
                5)
                    remove_short_id
                    ;;
                6)
                    generate_client_config
                    ;;
                7)
                    switch_ip_version
                    ;;
                8)
                    configure_firewall
                    check_ports
                    ;;
		9)
    		    uninstall_xray
    		    ;;
		10)
    		    exit 0
    		    ;;
                *)
                    echo -e "${RED}Invalid option!${NC}"
                    ;;
            esac
        done
    fi
}

# Start script
main_menu