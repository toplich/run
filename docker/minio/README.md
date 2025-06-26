# 🗃️ MinIO S3 Repository for Veeam on Synology NAS

This project automates the deployment of a secure, **S3-compatible** MinIO instance with **Object Lock** and **Versioning** enabled — perfect for integrating with **Veeam Backup & Replication** as an immutable repository.

---

## 📁 Structure

```
project/
├── docker-compose.yml    # Docker service definition for MinIO with TLS
├── deploy.sh             # Full automation: TLS, startup, user, bucket, versioning
└── .env                  # Environment configuration (IP, credentials, paths)
```

---

## ⚙️ Features

- ✅ Runs **MinIO** with HTTPS enabled using self-signed TLS
- ✅ Creates **S3 bucket** with `ObjectLockEnabled` for Veeam Immutability
- ✅ Enables **Versioning** and applies `readwrite` access policy
- ✅ Creates a dedicated Veeam user
- ✅ Verifies configuration via AWS CLI and `mc`

---

## 🚀 Quick Start

1. Edit the `.env` file with your own values (IP, host, passwords, etc.)
2. Download files
   
```bash
curl -O https://run.topli.ch/docker/minio/docker-compose.yml
curl -O https://run.topli.ch/docker/minio/deploy.sh
curl -O https://run.topli.ch/docker/minio/.env
```

3. Run the deployment script:

```bash
chmod +x deploy.sh
./deploy.sh
```

3. Access the web UI: `https://<HOST>:9001`

---

## 📌 Notes

- Requires **Docker** and **Docker Compose** installed on your Synology NAS or Linux host.
- Generates **TLS certs** with OpenSSL based on `.env` parameters.
- All operations are local — no Internet dependency.

---

## 🔒 Veeam Integration

Add as **S3-Compatible Object Repository** in Veeam using:

- Endpoint: `https://<IP>:9000`
- Bucket: `veeam-locked`
- Access Key: from `.env` (`USER`)
- Secret Key: from `.env` (`PASS`)
- Enable **Immutability** in advanced settings

---

## 🧩 Resources

- [MinIO Documentation](https://min.io/docs/)
- [Veeam Object Storage Setup](https://helpcenter.veeam.com/)
- [mc CLI Reference](https://min.io/docs/minio/linux/reference/minio-mc.html)

---

## 🛠 Author

**Vitalii Stepchuk**  
Feel free to use, extend, or contribute. Pull requests welcome.
