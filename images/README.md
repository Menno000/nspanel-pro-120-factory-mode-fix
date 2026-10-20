# Images

Drop the photos in this folder with exactly these names so the README picks them up.

| File | What it should show | Why it matters |
|---|---|---|
| `01-factory-mode.jpg` | The Chinese factory screen: 工厂模式, 您的设备未激活!, the QR code, `chipId: …`, and both buttons (产测功能 / 激活设备) | It is the image people recognise when they search |
| `02-partitions.png` | Recovery shell output of `busybox ls -l /dev/block/by-name` | Shows `stback` (the factory restore partition) |
| `03-system-apps.png` | `ls /system/app` showing `factoryApp` **and** `kz_app` | Proves the panel app is still on the device |
| `04-adb-window.png` | `scripts/find-adb-window.ps1` catching the panel during boot | Shows the timing trick |
| `05-welcome.jpg` | The eWeLink Welcome screen after the fix | The "after" picture |
| `06-usb-port.jpg` | Where the USB-C port is on the back of the 120 | People cannot find it |
| `07-home-chooser.jpg` | The Home app chooser with eWeLinkControlPanel / Launcher | Step 3 |
| `08-about-device-id.jpg` | About page showing a real **Device ID** (not blank) | Proof the licence landed |
| `09-activation.jpg` | The factory app after activation: **设备已激活** + QR | Step 5 |

Tips:

- Crop out reflections and background clutter; the screen should fill most of the frame.
- Blur or crop the QR code / chipId if you do not want that unit identifiable.
- Keep files under ~500 KB (JPEG quality 80, max 1200 px wide) so the repo stays light.
