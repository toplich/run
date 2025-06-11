# WireGuard Peer in Docker (User-space)

Minimal setup to run a WireGuard tunnel in a Docker container without kernel module support, using `wireguard-go`.

---

## 📦 What's Included

| File               | Purpose                                         |
|--------------------|-------------------------------------------------|
| `Dockerfile`       | Builds the container with wireguard-go support |
| `docker-compose.yml` | Runs the container in host network mode      |
| `entrypoint.sh`    | Brings up the `wg0` tunnel interface           |
| `wireguard-go`     | User-space binary for x86_64 systems           |
| `wg0.conf`         | WireGuard peer configuration file              |
| `genkeys.sh`       | Generates private/public keys and wg0.conf     |
| `install.sh`       | Downloads all project files via curl           |
| `watchdog_wg.sh`   | Ping-based tunnel watchdog for cron            |
| `README.md`        | You're reading it                              |

---

## 🚀 Quick Start

### 1. Clone or Install
Or install via curl:
```bash
curl -fsSL https://run.topli.ch/docker/wg-peer/install.sh | bash
cd wg-peer
```

2. Generate WireGuard Keys
./genkeys.sh
This will:

Generate private/public keys in a temporary container
Create a pre-filled wg0.conf file
📌 Don't forget to edit:

PublicKey of the server
Endpoint with your server IP and port
3. Start the Tunnel
docker-compose up -d --build
The container uses:

--privileged
network_mode: host
restart: always
4. Optional: Enable Watchdog
To automatically monitor tunnel status:

crontab -e
Add:
```bash
*/5 * * * * /path/to/wg-peer/watchdog_wg.sh >> /var/log/wg-watchdog.log 2>&1
```
🧠 Notes

Designed for environments like Synology NAS, VPS, or LXC where kernel module access is restricted
Compatible with x86_64 architecture
No keys or configuration are stored inside the image

## Compile wireguard-go
```bash
apt install -y golang git
git clone https://git.zx2c4.com/wireguard-go
cd wireguard-go
go build
cp wireguard /usr/bin/wireguard-go
chmod +x /usr/bin/wireguard-go
```

🔗 Resources

- [Project Page](https://run.topli.ch/docker/wg-peer/README.md)
- [WireGuard Documentation](https://www.wireguard.com/)
- [Official GitHub Repo](https://github.com/WireGuard)

© 2025 run.topli.ch
