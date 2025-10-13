<p align="center">
  <img src="logo.png" width="150" alt="run.topli.ch Logo" />
</p>

<p align="center">
  <strong>A curated collection of automation and admin scripts</strong><br>
  written in <code>Bash</code>, <code>PowerShell</code>, <code>Python</code>, <code>JavaScript</code> and <code>Docker</code>.
</p>

<p align="center">
  Hosted with GitHub Pages and accessible via clean URLs:<br>
  <a href="https://run.topli.ch" target="_blank">https://run.topli.ch</a>
</p>

---

## 📁 Directory Structure

| Folder | Language / Purpose |
|:--------|:-------------------|
| 🐳 `docker/` | Dockerfiles and containerized tool configurations |
| ⚙️ `js/` | Node.js / JavaScript helpers for automation and network tasks |
| 💻 `ps/` | PowerShell scripts for Windows Server, AD, and backup management |
| 🐍 `py/` | Python utilities for APIs, data parsing, and system reporting |
| 🐚 `sh/` | Bash scripts for Linux automation, monitoring, backups |

---

## 🚀 Quick Usage

You can run or download scripts directly using a simple command:

### 🐧 Linux / macOS (Bash)
▶️ Run a script directly
```bash
curl -s https://run.topli.ch/sh/hello.sh | bash
```
or
```bash
curl -s https://raw.githubusercontent.com/toplich/run.topli.ch/main/sh/hello.sh | bash
```
---
💾 Download a single script
```bash
curl -O https://run.topli.ch/sh/hello.sh
```
or
```bash
wget https://run.topli.ch/py/hello.py
```
---
Review a script before executing:
```bash
curl -s https://run.topli.ch/sh/hello.sh | less
```
---
### 🪟 Windows (PowerShell)
▶️ Run a script directly
```powershell
irm https://run.topli.ch/ps/hello.ps1 | iex
```
💾 Download a single script
```powershell
iwr https://run.topli.ch/ps/hello.ps1 -OutFile .\hello.ps1
```

---

## 📄 Notes

- All scripts are lightweight, portable, and easy to use
- Hosted via [GitHub Pages](https://pages.github.com)
- Custom domain: [run.topli.ch](https://run.topli.ch)
- Maintained by [Vitalii Stepchuk](https://blog.topli.ch)

---

## ⚠️ Disclaimer

Always review scripts before running them — even if they come from trusted sources.

