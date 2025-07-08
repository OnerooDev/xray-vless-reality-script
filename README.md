📘 [English](README.md) | 📙 [Русский](README_RU.md)

# Xray Reality Server Setup Script

## 📌 Overview

This script provides automated installation and configuration of Xray server with Reality protocol on Linux systems. It handles everything from dependency installation to firewall configuration.

## 🌟 Features

- **Automatic Xray installation** – Installs the latest Xray version  
- **Secure configuration** – Generates UUID and x25519 keys  
- **Domain validation** – Checks TLS 1.3 support  
- **Firewall setup** – Configures UFW/iptables with proper rules  
- **IP version support** – Works with both IPv4 and IPv6  
- **Client config generation** – Creates VLESS links and QR codes  

## 📥 Installation

Download the script:

```bash
curl -O https://raw.githubusercontent.com/OnerooDev/xray-vless-reality-script/main/xray-reality-server.sh
```

Give run access

```bash
chmod +x xray-reality-server.sh
```

Run as root:

```bash
sudo ./xray-reality-server.sh
```

## 🛠 Usage

### First Run

The script will:

1. Install all dependencies  
2. Set up Xray with Reality protocol  
3. Configure firewall rules  
4. Generate client configuration  

### Management Menu

After installation, you'll get access to management options:

```
1. Generate new UUID  
2. Generate new x25519 keys  
3. Change domain  
4. Add shortId  
5. Remove shortId  
6. Show client config (QR)  
7. Switch IP version (IPv4/IPv6)  
8. Configure firewall  
9. Uninstall Xray  
10. Exit
```

## 🔧 Configuration Options

### IP Version Selection

The script supports both IPv4 and IPv6:

- Choose during initial setup  
- Switch later via menu option  
- Automatically detects available addresses  

### Domain Configuration

- Script verifies TLS 1.3 support  
- Allows changing domain after setup  
- Validates domain before applying changes  

### Client Setup

Generates:

- VLESS links (`vless://...`)  
- QR codes for v2rayNG  
- Text files with connection details  

## 🛡 Security Features

- Automatic firewall configuration  
- Regular security updates  
- Proper user permissions  
- Secure defaults for all protocols  

## ⚙️ Technical Details

### Requirements

- Linux OS (tested on Ubuntu/Debian/CentOS)  
- Root access  
- `curl`, `jq`, `openssl`, `qrencode`  

### Files Locations

- Config: `/usr/local/etc/xray/config.json`  
- Service: `/etc/systemd/system/xray.service`  

## 🔄 Updating

To update Xray:

```bash
sudo ./xray-reality-server.sh
```

(Select reconfiguration option when available)

## ❌ Uninstallation

From management menu:

1. Select option 9 (Uninstall Xray)  
2. Confirm removal  

## 💡 Tips

1. For best security:  
   - Change UUID & KEYs periodically  
   - Use your own domain with valid TLS  
   - Keep system updated  

2. Client apps:  
   - v2rayNG (Android)  
   - Shadowrocket (iOS)  
   - Qv2ray (Windows/macOS/Linux)  

## 📜 License

MIT License

## 🤝 Contributing

Pull requests and issues are welcome on GitHub.