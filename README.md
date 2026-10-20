# SONOFF NSPanel Pro 120 stuck in Chinese "Factory Mode" (工厂模式) — fixed without flashing

How I brought a **SONOFF NSPanel Pro 120** back to life after it booted into the Chinese factory / production-test
screen (`工厂模式` — *Factory Mode*, `您的设备未激活!` — *Your device is not activated!*) and kept returning to that
same screen after every 5× power-cycle recovery.

No firmware image, no flashing tool and no vendor RMA were needed. The panel app was still on the device the whole
time — it just never got to run.

> **Tested on:** SONOFF NSPanel Pro 120 (NSPanel120P), 480×480, Rockchip PX30 (`px30_evb`), Android 8.1,
> factory base build `3.4.1`, panel app `com.eWeLinkControlPanel` version `2024081601`.
> The healthy sibling unit in the same house runs firmware `4.8.0`.

![Factory mode screen](images/01-factory-mode.jpg)

---

## Symptoms

Search terms people actually type when they hit this — that is why they are listed here:

- NSPanel Pro 120 shows a **black screen** or **Chinese menu** instead of the eWeLink UI after an update or reboot
- Screen shows **工厂模式** and **您的设备未激活!**
- A **QR code** and a line like **chipId: df61b1dea26c37c8**
- Two buttons: **产测功能** and **激活设备**
- Tapping **激活设备** briefly shows a **pairing spinner for ~10 seconds**, then drops back to the same Chinese screen
- The **5× power cycle** recovery (`unplug at the animated Sonoff logo`) finishes, reboots — and lands on the exact
  same factory screen again
- **ADB is "not available"**: the device shows up in Windows Explorer as `px30_evb` (MTP) but `adb devices` stays empty

## What the screen actually says

| Chinese | Meaning |
|---|---|
| 工厂模式 | Factory Mode |
| 您的设备未激活! | Your device is not activated! |
| chipId: … | Chip / device id of this unit |
| 产测功能 | Production test functions |
| 激活设备 | Activate device |

This is not a hardware fault and not a corrupt bootloader. It is the **factory test firmware** running, with the
production-test app in the foreground because there is no usable launcher/home activity.

## Why the 5× power-cycle makes it worse

Every 5× power-cycle boots the recovery partition, and on this model the recovery carries a **full factory OTA**
(`/smatekback/update.zip`, 687 MB, `system` + `vendor` + `oem` + `boot` + `uboot` + `trust`). Recovery re-applies it,
so you end up back on the factory build. Infinite loop, and every attempt wipes your data.

**Do not keep doing the 5× reset.** It is not a repair, it is a factory restore.

## Root cause

On my unit, `/system` contained the *factory* Android build (`ro.build.display.id=3.4.1`, dated 2024-08-16) with the
production test app:

```
/system/app/factoryApp/factoryApp.apk   -> package com.eWeLinkNSPro.dev   (the Chinese screen)
/system/app/kz_app/kz_app.apk           -> package com.eWeLinkControlPanel (the real eWeLink panel app, 156 MB)
```

Both were installed and working. The panel app was simply never started, because the factory app owned the
foreground and no HOME activity resolved:

```console
$ adb shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME
android/com.android.internal.app.ResolverActivity
```

So the fix is not flashing. The fix is **disabling the factory app** and **letting the panel app become Home**.

## Requirements

- A Windows/Linux/macOS PC with `adb` (Android platform-tools)
- A **USB-C data cable** (charge-only cables are the #1 reason people see nothing)
- Access to the USB-C port on the back of the module — remove the panel from its wall mount; **switch off mains
  power first**
- ~15 minutes

## Step 1 — Find the ~17 second ADB window during boot

The panel only exposes ADB for a short moment while booting. It is fully authorised during that window, because the
build is `userdebug`:

```
ro.debuggable=1
ro.adb.secure=0
```

`ro.adb.secure=0` means no RSA prompt: the device appears as `device` immediately, and `adb root` works.

Do **not** try to catch it by hand. Use the script in [`scripts/find-adb-window.ps1`](scripts/find-adb-window.ps1)
(Windows) or [`scripts/find-adb-window.sh`](scripts/find-adb-window.sh) (Linux/macOS). It polls `adb devices` every
300 ms and reacts the instant the panel shows up.

```powershell
# Windows
.\scripts\find-adb-window.ps1 -Serial H082012302031505935 -Fix
```

Leave it running and power-cycle the panel once (no 5× needed). On my unit the window was open for about 17 seconds.

## Step 2 — Disable the factory app

Once you have a shell in the window (or afterwards, as root):

```bash
adb shell pm disable-user --user 0 com.eWeLinkNSPro.dev
adb shell am force-stop    com.eWeLinkNSPro.dev
```

Optional but recommended on some units, it is a second OEM test app that can steal the screen:

```bash
adb shell pm disable-user --user 0 com.smatek.test
```

Verify:

```bash
adb shell pm list packages -d
# package:com.eWeLinkNSPro.dev
```

## Step 3 — Make the panel app the Home app

Trigger the Home chooser and pick **eWeLinkControlPanel**, with **Always**:

```bash
adb shell input keyevent 3
```

Or simply reboot the panel — after disabling the factory app it falls back to the eWeLink panel app by itself, which
is what happened on my unit: it booted straight into the eWeLink **Welcome** screen.

> If the panel app is not offered, install a minimal fallback launcher first
> ([Ultra Small Launcher](https://blakadder.com/nspanel-pro-sideload/), 7 KB) so you always have a usable Android UI:
> `adb install -r ultra-small-launcher.apk`

## Step 4 — Finish setup and update

1. Complete **Welcome** (language, Wi-Fi — **2.4 GHz only**).
2. Pair the panel in the **eWeLink app**.
3. Go to **About → Software Update** (or the app: Device Settings → Firmware Update) and let it update from the
   factory base (`3.4.1`) to the current release (`4.8.0`).

If the Chinese factory screen ever comes back after an update, the factory app has been re-enabled. Re-run Step 2 —
it is a 5 second fix once you know where to look.

---

## What I found on the device (for the curious)

The panel is a **Rockchip PX30** board running Android 8.1 with `ro.build.type=userdebug`, `ro.build.tags=test-keys`
and `androidboot.veritymode=enforcing`. Kernel cmdline carries `smatekrepair=1`.

Recovery (`adb devices` shows it as `rockchipplatform`) has **BusyBox 1.22.1** and almost nothing else — no `ls`,
no `getprop`, no `toybox`. Use `busybox ls`, `busybox cat`, `busybox mount`.

Partition layout (`/dev/block/by-name`, eMMC `mmcblk1`):

| Partition | Node | Size |
|---|---|---|
| uboot | p1 | 2 MB |
| trust | p2 | 2 MB |
| misc | p3 | 2 MB |
| resource | p4 | 8 MB |
| kernel | p5 | 16 MB |
| boot | p6 | 16 MB |
| recovery | p7 | 32 MB |
| backup | p8 | 56 MB |
| security | p9 | 2 MB |
| cache | p10 | 192 MB |
| **system** | **p11** | **768 MB** |
| metadata | p12 | 8 MB |
| vendor | p13 | 192 MB |
| oem | p14 | 128 MB |
| frp | p15 | 256 KB |
| smatek | p16 | 8 MB |
| keypart | p17 | 128 KB |
| STSN | p18 | 128 KB |
| **stback** | **p19** | **512 MB — holds `update.zip` (factory restore)** |
| userdata | p20 | ~1.8 GB |

The OEM partition still carries the bundled installer:

```
/oem/bundled_persist-app/CoolKit_4.7_24070816/CoolKit_4.7_24070816.apk   (9.8 MB -> com.smatek.test)
```

That one is a dead end: installing it does not restore the panel. The panel app that matters is `kz_app` on
`/system`.

There is **no public full firmware image** for this device. The OTA zips served by the eWeLink CDN are incremental and
cannot be applied over an arbitrary build, and `fastboot flash system …` advice you find on forums does not apply:
no such images exist publicly. If your case is worse than mine (e.g. `/system` was wiped and `kz_app` is gone), the
only route left is a support ticket with ITEAD/SONOFF — include the **chipId** from the factory screen and the serial
number from the label.

## Troubleshooting

**`adb devices` stays empty on USB**
Windows should list the panel as an MTP device named `px30_evb` (`USB\VID_2207&PID_0001`). If Explorer shows it but
ADB does not, that is normal outside the boot window — nothing is wrong with your driver.

**The window is too short / I miss it**
Keep the polling script running before you power-cycle. Each normal boot gives you another window. No need for the
5× reset.

**`pm disable-user` says "not installed for user 0" or fails**
Run `adb root` first — the build is userdebug, so root is available in the window.

**Chinese screen returns after a firmware update**
Re-run Step 2. The package may have been re-enabled by the update.

**Panel app opens then drops back to the factory screen**
The factory app is still enabled, or was restarted. `am force-stop` + `pm disable-user` both, then Home.

## What did *not* work

- The **5× power cycle** — restores the factory OTA, back to square one
- **Tapping “Activate device”** — 10 s pairing spinner, then back to factory mode
- **Factory “Wi-Fi test”** in 产测功能 — a hardware test, not a provisioning screen; no keyboard, nothing to select
- **Installing the OEM `CoolKit_4.7` APK** — installs `com.smatek.test`, does not bring back the panel UI
- **Waiting for ADB over the network** — in factory mode the panel never joins Wi-Fi, so port 5555 stays closed
- **Looking for a full firmware image** — none is published

## Photo credits / what goes where

| File | Should show |
|---|---|
| `images/01-factory-mode.jpg` | The Chinese factory screen with QR code and chipId |
| `images/02-partitions.png` | `busybox ls -l /dev/block/by-name` in recovery |
| `images/03-system-apps.png` | `ls /system/app` showing `factoryApp` and `kz_app` |
| `images/04-adb-window.png` | The script catching the device in the boot window |
| `images/05-welcome.jpg` | The eWeLink Welcome screen after the fix |
| `images/06-usb-port.jpg` | Where the USB-C port is on the back of the 120 |

## Disclaimer

Everything here is what worked on one specific unit. Disabling system packages, running `adb root` and poking at
partitions can brick your panel, void your warranty, and — on a mains-powered wall device — is a genuine electrical
safety risk. Switch off the breaker before you take the panel off the wall. Use at your own risk.

## License

MIT — see [LICENSE](LICENSE).
