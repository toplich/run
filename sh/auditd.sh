#!/bin/bash

set -e

echo "🔧 Installing auditd and aide..."
apt update && apt install -y auditd audispd-plugins aide

echo "📋 Creating audit rules..."
cat << 'EOF' > /etc/audit/rules.d/audit-ansible.rules
# Log all executed commands (via execve syscall)
-a always,exit -F arch=b64 -S execve -k all_exec
-a always,exit -F arch=b32 -S execve -k all_exec

# Monitor package installation via apt
-w /usr/bin/apt -p x -k apt_exec

# Monitor changes in dpkg database
-w /var/lib/dpkg/ -p wa -k dpkg_change
EOF

echo "📦 Loading auditd rules..."
augenrules --load
systemctl restart auditd

echo "📂 Initializing AIDE database (this may take a few minutes)..."
aideinit

echo "💾 Replacing new AIDE database..."
cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db

echo "🛠️ Creating aide-check utility in /usr/local/bin"
cat << 'EOF' > /usr/local/bin/aide-check
#!/bin/bash
echo "🔍 Checking filesystem integrity (AIDE)..."
aide --check
EOF

chmod +x /usr/local/bin/aide-check

echo "✅ Setup complete!"
echo " - auditd is logging all commands and dpkg changes"
echo " - AIDE is ready to detect file integrity changes"
echo " - Run check manually: sudo aide-check"
echo " - Audit logs available at: /var/log/audit/audit.log"
