#!/usr/bin/env bash

set -euo pipefail

# --- CONFIGURATION ---
ISO_NAME="elysium-os"
ARCHISO_REPO="https://gitlab.archlinux.org/archlinux/archiso.git"
ARCHISO_DIR="archiso"
WORK_DIR="$ISO_NAME"
OUT_DIR="out"
SCREENSHOT_DIR="screenshots"
QEMU_RAM="4096"
SCREENSHOT_INTERVAL="30" # seconds

echo "🟢 [1/8] Installing build dependencies..."
sudo pacman -Sy --noconfirm archiso git python python-pip imagemagick xorg-server-xvfb qemu-base base-devel fastfetch rofi picom tmux zsh fzf ripgrep btop feh xclip

# --- Clean previous build artifacts ---
rm -rf "$ARCHISO_DIR" "$WORK_DIR" "$OUT_DIR" "$SCREENSHOT_DIR"
mkdir -p "$SCREENSHOT_DIR"

echo "🟣 [2/8] Cloning ArchISO template..."
git clone --quiet "$ARCHISO_REPO"
cp -r "$ARCHISO_DIR/configs/releng" "$WORK_DIR"
cd "$WORK_DIR"

echo "🟡 [3/8] Customizing packages and system..."
cat <<EOL >> packages.x86_64

# Desktop Environment, Window Management & Visual Effects
plasma-meta sddm xorg kdeplasma-addons bismuth-git krohnkite-git
wmctrl xdotool tmux rofi picom kvantum-qt5 kvantum-theme-sweet qt5ct qt6ct
orchis-theme sweet-gtk-theme-git papirus-icon-theme pywal variety feh btop fastfetch
networkmanager nano zsh fzf ripgrep xclip flameshot

# AI / Automation
python python-pip python-openai git

# Multimedia Support
pipewire pipewire-alsa pipewire-pulse

EOL

# --- Setup systemd for autologin ---
mkdir -p airootfs/etc/systemd/system/getty@tty1.service.d/
cat <<EOL > airootfs/etc/systemd/system/getty@tty1.service.d/autologin.conf
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin root --noclear %I \$TERM
EOL

# --- Desktop autostart for demo ---
mkdir -p airootfs/root/.config/autostart
mkdir -p airootfs/root/scripts
cat <<EOL > airootfs/root/.config/autostart/elysium-demo.desktop
[Desktop Entry]
Type=Application
Exec=/root/scripts/elysium-demo.sh
Hidden=false
X-GNOME-Autostart-enabled=true
Name=Elysium Demo Startup
Comment=Runs demo UI for screenshot workflow
EOL

# --- Demo script: opens apps, sets wallpaper, and triggers UI for screenshots ---
cat <<'EOL' > airootfs/root/scripts/elysium-demo.sh
#!/usr/bin/env bash
export DISPLAY=:0
sleep 8
feh --bg-scale /usr/share/backgrounds/archlinux/archlinux-simplyblack.jpg || true
# Start picom for blur, transparency, and rounded corners
picom --config /root/.config/picom.conf &
sleep 3
# Launch a terminal (konsole) running fastfetch demo & hold so screenshot catches it
konsole --hold -e "fastfetch; echo 'Elysium OS Demo!'; sleep 12" &
sleep 2
# Launch rofi as a sample application launcher
rofi -show drun -theme Sweet &
# Run system monitoring dashboard
btop &
sleep 2
# Start a tmux session to simulate tiling window management
tmux new-session -d -s demo 'htop'
sleep 2
# Allow time for the UI to stabilize before screenshots are taken
sleep 40
poweroff
EOL
chmod +x airootfs/root/scripts/elysium-demo.sh

# --- Picom configuration (blur, transparency, rounded corners) ---
mkdir -p airootfs/root/.config
cat <<'EOL' > airootfs/root/.config/picom.conf
backend = "glx";
vsync = true;
corner-radius = 18;
shadow = true;
shadow-radius = 14;
shadow-opacity = 0.24;
blur-method = "dual_kawase";
blur-strength = 7;
opacity-rule = [
  "85:class_g = 'Rofi'",
  "80:class_g = 'Konsole'",
  "90:class_g = 'Plasma'"
];
EOL

# --- KDE/Plasma theming ---
mkdir -p airootfs/root/.config
cat <<'EOL' > airootfs/root/.config/kdeglobals
[General]
ColorScheme=Sweet
[WM]
activeBackground=232,162,232
inactiveBackground=200,200,220
[Icons]
Theme=Papirus
[Theme]
name=Sweet
EOL

# --- KWin configuration for window effects ---
mkdir -p airootfs/root/.config
cat <<'EOL' > airootfs/root/.config/kwinrc
[Plugins]
blurEnabled=true
backgroundContrastEnabled=true
[Effect-Blur]
BlurStrength=10
[Effect-BackgroundContrast]
Contrast=0.5
Intensity=0.45
Saturation=0.5
[Effect-WindowCorner]
CornerRadius=18
EOL

# --- Kvantum configuration for scalable UI elements ---
mkdir -p airootfs/root/.config/Kvantum
cat <<'EOL' > airootfs/root/.config/Kvantum/kvantum.kvconfig
[General]
theme=Sweet
EOL

# --- AI Assistant Script ---
cat <<'EOL' > airootfs/root/scripts/ai_assistant.py
#!/usr/bin/env python3
import openai, os, sys
openai.api_key = os.getenv("OPENAI_API_KEY", "")
prompt = sys.argv[1] if len(sys.argv) > 1 else "How can I improve my workspace?"
resp = openai.ChatCompletion.create(
  model="gpt-4",
  messages=[{"role": "user", "content": prompt}]
)
print("Elysium AI Suggestion:", resp['choices'][0]['message']['content'])
EOL
chmod +x airootfs/root/scripts/ai_assistant.py

# --- Build ISO ---
echo "🔵 [4/8] Building ISO..."
mkarchiso -v -o "../$OUT_DIR" .
cd ..

# --- QEMU + Xvfb: Boot ISO and capture screenshots ---
ISO_PATH="$(ls $OUT_DIR/*.iso | head -1)"

echo "🟠 [5/8] Starting QEMU headless for screenshotting..."
Xvfb :99 -screen 0 1280x720x24 &
XVFB_PID=$!
sleep 3

qemu-system-x86_64 \
  -m $QEMU_RAM \
  -cdrom "$ISO_PATH" \
  -boot d \
  -enable-kvm \
  -smp 2 \
  -vga std \
  -display :99 \
  -no-reboot \
  -serial mon:stdio \
  -net nic -net user \
  -rtc base=utc \
  -usb -device usb-tablet &
QEMU_PID=$!

# Allow time for the demo session to load and run
sleep 15
for i in {1..4}; do
  import -display :99 -window root "$SCREENSHOT_DIR/elysium-desktop-$i.png"
  sleep $SCREENSHOT_INTERVAL
done

kill $QEMU_PID || true
kill $XVFB_PID || true

echo "🟢 [6/8] All done! ISO and screenshots are in $OUT_DIR and $SCREENSHOT_DIR"