# Dynamically enable Global Secure Access (GSA) – PowerShell 🚀

This solution **dynamically enables Microsoft Global Secure Access tunnelling depending on location**
(**on-site vs off-site**). When the device is considered **off-site**, the script **starts the GSA services**.
When the device is **on-site**, it can optionally **stop** the services. ✅

The location decision is made by:
- **Ping test** (required) 📶
- **DNS resolve test** (optional; can be skipped) 🌐

---

## Files 📁

- `dynamically_enable_global_secure_access.script.ps1` – main script ⚙️  
- `dynamically_enable_global_secure_access.config.json` – JSON config (environment-specific values) 🧩

---

## How it works (high level) 🧠

1. Verifies the GSA client is installed (checks for `GlobalSecureAccessClientManagerService.exe`). 🔎  
2. Loads configuration from the JSON file (default: same folder, same base name). 🗂️  
3. Checks prerequisites:
   - GSA service **StartType must be `Manual`** (Microsoft defaults to auto-start; this script expects manual). 🛠️  
   - Optional: `BurntToast` module for end-user toast notifications. 🍞  
4. Determines location:
   - Waits for network availability (Ethernet/Wi-Fi up) ⏳
   - Runs ping test 📡
   - Runs DNS test (unless skipped) 🧪
5. Applies desired state:
   - **Off-site** → starts GSA services 🟢
   - **On-site** → does nothing, or stops services if `-disableIfAlreadyRunning` is used 🔴  
6. Outputs a console message and (optionally) a toast. Language is chosen based on UI culture (DE/EN) and can be forced to English. 🗣️

---

## Requirements ✅

### Client / OS 💻
- Windows device with **Global Secure Access client installed**.
  - The script exits successfully if the client isn’t installed. 👍
  - The script was tested with the GSA client in version 2.24.117

### GSA services must be Manual ⚠️
The following services are used - these are the ones used with the GSA client in version 2.24.117:
- `GlobalSecureAccessEngineService`
- `GlobalSecureAccessForwardingProfileService`
- `GlobalSecureAccessTunnelingService`

**Important:** Their `StartType` must be `Manual`, otherwise the script exits with error. 🧯

### Optional: BurntToast (highly recommended) 🍞✨
If the `BurntToast` module is available, the script shows toast notifications (optionally with an image).
Get it from here: https://github.com/Windos/BurntToast

### Execution context 👤
The script is designed to run in **user context** ➡️ no admin privileges needed to run it, this reflects the GSA client being enabled / disabled from the GUI by the user.

---

## Configuration (`.config.json`) 🧩

The config file contains environment-specific values:

| Key | Description |
|---|---|
| `_comment` | Human note (ignored by the script logic). |
| `imagePath` | Local path to an image used in BurntToast toasts (optional; toast still works without image). 🖼️ |
| `fqdnToResolve` | FQDN to resolve against your on-prem DNS server. 🌐 |
| `expectedIp` | Expected A-record IP if the client is on-site. 🎯 |
| `dnsServerIp` | DNS server IP to query (used for the on-site DNS check). 📡 |
| `pingHostIp` | Host IP used for the ping test (on-site reachability). 📶 |

### Default config file location 📍
If you don’t pass `-configFilePath`, the script expects the config next to the script with the same name as the script, but ending in `.config.json`.

---

## Script parameters 🧰

| Parameter | What it does |
|---|---|
| `-skipDns` | Skips DNS resolution; relies on ping only. |
| `-simulateOffSiteLocation` | Forces off-site result (debug/testing). 🧪 |
| `-simulateOnSiteLocation` | Forces on-site result (debug/testing). 🧪 |
| `-disableIfAlreadyRunning` | If on-site, stops GSA services when they’re already running. 🔴 |
| `-forceEnglishToasts` | Forces BurntToast notifications to English text even on a German PC. 🇬🇧 |
| `-configFilePath <path>` | Use a custom config path (overrides default). |

> Note: `-simulateOffSiteLocation` and `-simulateOnSiteLocation` are mutually exclusive; using both exits with error. 🚫

---

## Usage examples ▶️

Run with default config in the same folder:
```powershell
.\dynamically_enable_global_secure_access.script.ps1
````

Use a custom config path:

```powershell
.\dynamically_enable_global_secure_access.script.ps1 -configFilePath "C:\Scripts\gsa\my.config.json"
```

Ping-only mode:

```powershell
.\dynamically_enable_global_secure_access.script.ps1 -skipDns
```

Test behavior without actually being off-site:

```powershell
.\dynamically_enable_global_secure_access.script.ps1 -simulateOffSiteLocation
```

Disable GSA when you're on-site, but GSA is enabled:

```powershell
.\dynamically_enable_global_secure_access.script.ps1 -disableIfAlreadyRunning
```

---

## Deployment ideas (Intune-friendly) 🏢

* **Scheduled task** (recommended): run periodically (e.g. every 5–15 minutes) and/or at logon ⏱️
* **Proactive Remediations**: detection checks “desired state”, remediation runs this script 🩺
* **Win32 app**: deploy scripts + config to a fixed location, then register task 📦

---

## Notes / troubleshooting 🧯

* If the script exits with error, first check:

  * GSA services are set to **Manual** 🛠️
  * Config file path is correct and readable 📄
  * Your ping/DNS targets are reachable from on-site networks 📶🌐

---

## Disclaimer ⚖️

Use at your own risk. Test in a pilot group before broad rollout. 🧪✅

```
