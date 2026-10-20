# SONOFF NSPanel Pro 120 stuck in Chinese "Factory Mode" (工厂模式) — fixed without flashing

How I brought a **SONOFF NSPanel Pro 120** back to life after it booted into the Chinese factory / production-test
screen (`工厂模式` — *Factory Mode*, `您的设备未激活!` — *Your device is not activated!*) and kept returning to that
same screen after every 5× power-cycle recovery.

No firmware image, no flashing tool and no vendor RMA were needed. The panel app was still on the device the whole
time — it just never got to run.

> **Tested on:** SONOFF NSPanel Pro 120 (NSPanel120P), 750×1334 at 240 dpi, Rockchip PX30 (`px30_evb`),
> Android 8.1, factory base build `3.4.1`, panel app `com.eWeLinkControlPanel` version `2024081601`.
> After the repair it OTA'd itself through `4.0.12` → `4.4.0` → `4.9.0` (panel app `4.9.3`), all without a PC.
> The healthy sibling unit in the same house runs firmware `4.8.0`.

*Screenshots are not committed yet — [`images/README.md`](images/README.md) lists the exact shots this write-up
expects. The factory screen is easy to recognise: black background, `工厂模式` on top, a QR code, `chipId: …`, and the
two buttons `产测功能` / `激活设备`.*

---

## Symptoms

Search terms people actually type when they hit this — that is why they are listed here:

- NSPanel Pro 120 shows a **black screen** or **Chinese menu** instead of the eWeLink UI after an update or reboot
- Screen shows **工厂模式** and **您的设备未激活!**
- A **QR code** and a line like **chipId: 1a2b3c4d5e6f7890**
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
so you end up back on the factory build. On my unit that matched exactly: `/system` carried the same `3.4.1` build
(2024-08-16) that the `update.zip` contains. Infinite loop, and every attempt wipes your data.

**Do not keep doing the 5× reset.** It is not a repair, it is a factory restore.

## Root cause

On my unit, `/system` contained the *factory* Android build (`ro.build.display.id=3.4.1`, dated 2024-08-16) with the
production test app:

```
/system/app/factoryApp/factoryApp.apk   -> package com.eWeLinkNSPro.dev   (the Chinese screen)
/system/app/kz_app/kz_app.apk           -> package com.eWeLinkControlPanel (the real eWeLink panel app, 156 MB)
```

Both were installed and working. No default HOME app was configured, so the device came up on the factory screen and
the panel app was never started:

```console
$ adb shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME
android/com.android.internal.app.ResolverActivity
```

`ResolverActivity` is the Home chooser — in other words, nothing had been chosen as default.

So the fix is not flashing. The fix is **disabling the factory app**, after which the panel app becomes the only
sensible Home candidate and starts on the next boot.

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
.\scripts\find-adb-window.ps1 -Serial <YOUR-SERIAL> -Fix
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

### Verified result

Straight from the boot window on my unit, after running the commands above:

```console
disable factory : Package com.eWeLinkNSPro.dev new state: disabled-user
disable smatek  : Package com.smatek.test new state: disabled-user
disabled list   : package:com.eWeLinkNSPro.dev package:com.smatek.test
foreground      : mResumedActivity: ActivityRecord{... com.eWeLinkControlPanel/.MainActivity t35}
crash buffer    : (empty)
```

No crash, no reboot loop — the panel app simply stays in front and boots into its own Welcome flow.

## Step 4 — Finish setup and update

1. Complete **Welcome** (language, Wi-Fi — **2.4 GHz only**).
2. Pair the panel in the **eWeLink app**.
3. Let it update from the factory base (`3.4.1`) to the current release. On `3.4.1` you can still use **About →
   Software Update**; from `4.x` the panel offers a full-screen *New Firmware Available* dialog a few seconds after
   boot instead (see below). Tap **Installeren / Install** when it is offered — the download completes on its own,
   but the install step needs that tap.

If the Chinese factory screen ever comes back after an update, the factory app has been re-enabled. Re-run Step 2 —
it is a 5 second fix once you know where to look.

> Updates are staged, so expect several rounds: my unit went `3.4.1` → **`4.0.12`** (a ~865 MB OTA applied in recovery)
> → **`4.4.0`** (applied by recovery on the following boot) → **`4.9.0`** + panel app **`4.9.3`**. Each firmware round
> is a full reboot into recovery; budget 5–12 minutes per round and do not cut the power.

### Where the update prompt lives in 4.x

In `4.4.0` and later the in-app **About → Software update** page is gone. Tapping **Over** in *Settings* opens the AOSP
**Settings** app, and the **Advanced Settings** row does not respond at all. What you get instead is a full-screen
`OtaStrongReminderActivity` — *New Firmware Available, v4.9-493-490-200* with **dicht / Update** — that appears a few
seconds after boot. That version string means panel app `4.9.3` on top of `4.9.0`.

The dialog is drawn by that activity, and synthetic `adb shell input tap` events were sometimes ignored on it; the tap
landed on the second attempt and the update ran ~10 seconds later. Do not assume it did nothing.

### Applying a staged update by hand (what the app actually does)

Once the app has downloaded the packages into `/data/data/com.eWeLinkControlPanel/files/ota/`, its recipe can be
replicated. Check the digest from `plain_config.xml` (`OTA_INFO_ROM`) first:

```bash
adb root
adb shell md5sum /data/data/com.eWeLinkControlPanel/files/ota/rom_4.9.0.zip
# d90844de85fe418e2c402800c76d6d23  rom_4.9.0.zip   <- matches OTA_INFO_ROM.digest

adb shell 'cp /data/data/com.eWeLinkControlPanel/files/ota/rom_4.9.0.zip /data/media/0/update.zip'
adb shell 'uncrypt /data/media/0/update.zip /cache/recovery/block.map'
adb shell 'echo --update_package=@/cache/recovery/block.map > /cache/recovery/command'
adb shell 'echo --locale=en-US >> /cache/recovery/command'
adb shell 'reboot recovery'
```

`uncrypt` turns a package that lives on `/data` into a ~90 byte block map, and recovery is started exactly the way the
app starts it: `--update_package=@/cache/recovery/block.map --locale=en-US` (visible in `/cache/recovery/last_log`).
For the `4.4.0` → `4.9.0` round (`CK_4.4.0_4.9.0V228-diff.zip`, 196,455,904 bytes, md5 `d90844de…`) `last_install`
ended with:

```console
@/cache/recovery/block.map
1
time_total: 672
retry: 0
target_build: 093351
source_build: 141952
bytes_written_system: 1553985536
bytes_written_vendor: 379752448
bytes_written_oem: 69906432
temperature_max: 42900
```

After the reboot `ro.build.display.id` was `4.9.0`, and the pending app update (`4.9.3`) installed itself on the next
launch. Unlike the earlier rounds, this one **kept** the default-Home choice.

### After the update: the Home app is unset again

The `4.0.12` and `4.4.0` rounds wiped the default-Home choice on my unit, so the panel came back on the
`ResolverActivity` chooser. The class name also changed in `4.0.12` (from `com.eWeLinkControlPanel.MainActivity` to
`com.coolkit.nspanelpro.ui.activity.MainActivity`). Set it again from ADB:

```bash
adb shell cmd package set-home-activity \
  com.eWeLinkControlPanel/com.coolkit.nspanelpro.ui.activity.MainActivity
adb shell input keyevent 3
```

The `disabled-user` state of the factory app survives the update — no need to re-run Step 2 unless the Chinese
screen actually appears.

## Step 5 — If it still cannot log in: the missing device licence

Disabling the factory app was only half of the repair on my unit. Afterwards the panel app started, showed the
**eWeLink login / QR screen**, and then either hung or came back with a `400`. Nothing was wrong with the network,
DNS, TLS, clock or WebView — the panel simply had **no identity**:

```console
X-CK-Deviceid: undefined
model=undefined_undefined
HTTP 400 {"error":400,"message":"\"x-ck-deviceid\" length must be 10 characters long"}
```

mDNS advertised the panel as `eWeLink_undefined._ewelink._tcp.local.` instead of `eWeLink_<10 chars>`.

That is the same reason the factory screen said **您的设备未激活!** (*your device is not activated!*): the licence
was never programmed at the factory. `getDeviceId()` returns `null`, so every request goes out with
`X-CK-Deviceid: undefined` and the cloud rejects it.

### Where the identity lives

Rockchip keeps it in the raw **vendor storage** partition, `/dev/vendor_storage`, as two items:

| Item | Content |
|---|---|
| 7 | licence string, space separated: `Y <licenceid> <uuid> <mac> <mac> <model> <uiid>` |
| 8 | product id, e.g. `24024300000000` |

| idx in item 7 | field | used as |
|---|---|---|
| 0 | `Y` | vendor tag |
| 1 | licence id (10 chars) | licence id |
| 2 | UUID | device key |
| 3 | MAC | secondary MAC |
| 4 | MAC | primary MAC (chip id) |
| 5 | `SN-RK3326S-NSPP-01` | model |
| 6 | `228` | uiid of the NSPanel Pro 120 |

Read and write it through the vendor `libioctrl.so`: `Ioctrl.read(7)`, `Ioctrl.read(8)`, and
`Ioctrl.write(7, …)` / `Ioctrl.write(8, …)`.

### The easy route: let the factory app provision it

The factory app (`com.eWeLinkNSPro.dev`) still contains the full activation flow. Re-enable it, run its
`ActiveActivity`, and it asks SONOFF's servers for the licence that belongs to this board and writes it into
vendor storage itself:

```bash
adb root
adb shell chmod 666 /dev/vendor_storage          # Ioctrl.changeMode() normally does this via su
adb shell pm enable com.eWeLinkNSPro.dev
adb shell am start -n com.eWeLinkNSPro.dev/.ActiveActivity
```

Two gotchas I hit:

- **It insists on a Wi-Fi test first.** `connectWifiTask` must succeed before it will talk to the servers. It wants
  the SSID `sonoff-nsp-pd` with password `094FAFE8` (hard-coded). With `connectWifiTask` skipped it silently does
  nothing.
- **`su` does not work from an `adb shell`.** `Ioctrl.changeMode()` runs `su` + `chmod 0666 /dev/vendor_storage`, which
  fails outside the boot window. Start `ActiveActivity` during the window where `adb root` still applies (see
  [Step 1](#step-1--find-the-17-second-adb-window-during-boot)), or `chmod` the node yourself first.

When it works the screen shows **设备已激活** (*device activated*) and a QR code, and vendor storage now holds the
licence:

```console
# before
item 7: (empty)
item 8: (empty)

# after
item 7: Y 1002abcd12 aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee aa:bb:cc:dd:ee:01 aa:bb:cc:dd:ee:02 SN-RK3326S-NSPP-01 228
item 8: 24024300000000
```

Then disable the factory app again (Step 2), restart the panel app, and the login works. mDNS now advertises
`eWeLink_1002ffff99._ewelink._tcp.local.` and `About` shows a real **Device ID** instead of nothing.

### What the factory app actually asks the servers (for reference)

If `ActiveActivity` is not usable, the same data can be fetched by hand. Everything is keyed on the **CPU serial**
(`ro.serialno` / the chip id on the factory screen), so no invoice or work number is needed:

1. **Look up the work order** (signed request; `appid`, `ts`, `sign`, secret `vhUqCz^nnGTNA77yVcEs!1OZ%XnJ4u&R`):
   `GET https://snchipidupload-api.coolkit.cn/prod/chipId/SNId_<cpu-serial>?appid=kFHobAQVLZJeakkx&ts=<ms>`
   → `{"error":0,"data":{"workId":"WW123456"}}`
2. **Download the licence**:
   `GET https://test-pdmg.sonoff.co/IdentifierManagement/License/Download?worknumber=WW123456&mac=<cpu-serial>`
   with `X-CK-Appid: nryla4dw0p6ycmvh87jrsoh8iv47c1wy` and a fixed `Authorization` token
   → `{"model":"NSPanel120PW","licenseid":"…","licensestring":"Y … 228"}`
3. **Download the product id**:
   `POST https://test-pdmg.sonoff.co/IdentifierManagement/ProductId/Download`
   with `{licenseid, mac, model, worknumber}` → `{"productid":"…"}`
4. Write both into vendor storage (`Ioctrl.write(7, licensestring)`, then `Ioctrl.write(8, productid)`).

One oddity that turned out to be harmless: the id the panel advertises over mDNS (`eWeLink_1002ffff99`) is **not**
the same 10-character id as the licence (`1002abcd12`). Login and OTA both work regardless.

---

## Step 6 — Turn it into a Home Assistant wall panel (optional)

The panel is a locked-down Android 8.1, so the HA front end is simply a kiosk browser. This is what worked here:

1. Install [Fully Kiosk Browser](https://www.fully-kiosk.com/) — `adb install -r Fully-Kiosk-Browser-v1.61.4.apk`.
2. **Fully Kiosk does not register a `CATEGORY_HOME` activity**, so `cmd package set-home-activity` cannot select it
   (`cmd package query-activities -a android.intent.action.MAIN -c android.intent.category.HOME` lists only the panel
   app and the AOSP fallback). Use the panel app instead: **Apps → Home App → Fully Kiosk Browser**. The panel app then
   starts it on every Home press and on boot, which also survived a reboot test.
3. In Fully Kiosk: **Start URL** `http://<ha-host>:8123/?kiosk`, **Launch on Boot** on, **Keep Screen On** on and
   **Restart Fully After Crash** on. Under *Web Zoom and Scaling* switch **Enable Zoom** and **Use Wide Viewport** off:
   with both on, the HA dashboard is laid out wider than the 750 px screen and the right-hand cards are cut off.
4. The panel app's own **Local Web Portal** remains reachable at `http://<panel-ip>/` (port 80, build `4.9.0.5`).
   Its routes include `/screen`, `/matter`, `/device-management` and `/home-assistant/config`, which is handy when the
   panel is showing the dashboard and you need to change something.

### Free vs. PLUS

Fully Kiosk's **Kiosk Mode**, **Screensaver**, **Motion Detection** and **Remote Administration** are all PLUS (paid,
one-time per device). Without it the panel still boots into the dashboard, keeps the screen on and restarts itself
after a crash — but the Home button can leave the dashboard. Everything below is free.

### Remove what you do not need — this is where the speed is

After two OTAs my unit sat at **load 3.3** on four cores, with three avoidable hogs:

| Package / process | Cost | What it is |
|---|---|---|
| `org.fdroid.fdroid` | 161% CPU, 86 MB | Bundled system app at `/oem/bundled_persist-app/F-Droid/F-Droid.apk`. A WorkManager job restarts it to refresh repositories, so `force-stop` does not stick |
| `com.termux` + `com.termux.boot` | ~115 MB | The panel app installs Termux for its Zigbee "cube" (`bridge-cube` + mosquitto on `127.0.0.1:1884`). Only needed if the panel *is* your Zigbee coordinator |
| `com.eWeLinkControlPanel:matterbridge` | 35–92 MB | Matter bridge; turn it off in the panel app if you do not use Matter |

```bash
adb shell pm disable-user --user 0 org.fdroid.fdroid
adb shell pm disable-user --user 0 com.termux.boot
adb shell pm disable-user --user 0 com.termux
```

All of these are reversible with `pm enable` and they survive an OTA. After this the same unit measured **load 0.6–0.8**, no
ANRs, 348 MB free and a dashboard that reacts immediately. The remaining cost is the WebView rendering the HA
dashboard (25–40% of one core, it is a card-heavy dashboard with an energy graph) plus the panel app's own cloud/Hue
sync (~10–15%).

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

**The panel reboots into recovery again after the update and says `system image corrupted, attempting to recover…`**
Leave it alone. On my unit that was not a failure: recovery was writing the next stage (`last_install` ended with
`success`, `bytes_written_system: 1557966848`, 12 minutes). When it finishes, `/cache/recovery/command` is gone and
normal reboots go back to Android. Cutting the power there is the one way to actually brick it.

**`NSPanelPro isn't responding` / `Context.startForegroundService() did not then call Service.startForeground()`**
That is an ANR from CPU starvation, not corruption. After a big update the panel is busy while it migrates data, and
anything that keeps the CPU at 100% (on my unit: F-Droid's *Updating repositories*, plus the app's Hue bridge polling)
pushes the panel app over the 5 second limit. Dismiss with **Wait**, then:

```bash
adb shell am force-stop org.fdroid.fdroid      # or whichever app is pinning the CPU
adb shell top -n 1 -m 10 -s 3
```

Do not tap **Close app** and do not keep rebooting — the app recovers on its own once the CPU frees up.

**`uiautomator dump` fails with "could not get idle state"**
The panel UI animates almost constantly, so the idle detector never fires. Do not fight it: take a screenshot instead
(`adb shell screencap -p /sdcard/x.png` + `adb pull`) and read the pixels. `input tap` still works while the dump
fails.

**`top -m` / `top -o` / `free` are useless for a quick answer**
On this build `top -m` and `top -o` are not supported, and `free` counts page cache as used. Use
`ps -A -o PID,NAME,%CPU | sort -k3 -rn | head`, `cat /proc/loadavg`, and `dumpsys meminfo` (the panel app itself
reports `sysUsedMb` and `appTotalMb` in its own log).

## What did *not* work

- The **5× power cycle** — restores the factory OTA, back to square one
- **Tapping “Activate device”** — 10 s pairing spinner, then back to factory mode
- **Factory “Wi-Fi test”** in 产测功能 — a hardware test, not a provisioning screen; no keyboard, nothing to select
- **Installing the OEM `CoolKit_4.7` APK** — installs `com.smatek.test`, does not bring back the panel UI
- **Waiting for ADB over the network** — in factory mode the panel never joins Wi-Fi, so port 5555 stays closed
- **Looking for a full firmware image** — none is published

## Photo credits / what goes where

The screenshots are **not in this repository yet** — the table lists exactly what each file should show. Drop them
into `images/` with these names and `images/README.md` explains the framing and file-size rules.

| File | Should show |
|---|---|
| `images/01-factory-mode.jpg` | The Chinese factory screen with QR code and chipId |
| `images/02-partitions.png` | `busybox ls -l /dev/block/by-name` in recovery |
| `images/03-system-apps.png` | `ls /system/app` showing `factoryApp` and `kz_app` |
| `images/04-adb-window.png` | The script catching the device in the boot window |
| `images/05-welcome.jpg` | The eWeLink Welcome screen after the fix |
| `images/06-usb-port.jpg` | Where the USB-C port is on the back of the 120 |
| `images/07-home-chooser.jpg` | The Home chooser with `eWeLinkControlPanel` selected as **Always** |
| `images/08-about-device-id.jpg` | About page with a real **Device ID** (after the licence repair) |
| `images/09-activation.jpg` | The factory app showing **设备已激活** (device activated) |

## Disclaimer

Everything here is what worked on one specific unit. Disabling system packages, running `adb root` and poking at
partitions can brick your panel, void your warranty, and — on a mains-powered wall device — is a genuine electrical
safety risk. Switch off the breaker before you take the panel off the wall. Use at your own risk.

## License

MIT — see [LICENSE](LICENSE).
