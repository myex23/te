#!/usr/bin/env bash

set -euo pipefail

# --- CONFIG ---
ISO_NAME="elysium-os"
ARCHISO_REPO="https://gitlab.archlinux.org/archlinux/archiso.git"
ARCHISO_DIR="archiso"
WORK_DIR="$ISO_NAME"
OUT_DIR="out"
SCREENSHOT_DIR="screenshots"
QEMU_RAM="4096"
QEMU_TIMEOUT="120"
SCREENSHOT_INTERVAL="30" # seconds

echo "🟢 [1/8] Installing build dependencies..."
sudo pacman -Sy --noconfirm archiso git python python-pip imagemagick xorg-server-xvfb qemu-base base-devel neofetch rofi picom tmux zsh fzf ripgrep btop feh xclip

# --- Clean previous ---
rm -rf "$ARCHISO_DIR" "$WORK_DIR" "$OUT_DIR" "$SCREENSHOT_DIR"
mkdir -p "$SCREENSHOT_DIR"

echo "🟣 [2/8] Cloning ArchISO template..."
git clone --quiet "$ARCHISO_REPO"
cp -r "$ARCHISO_DIR/configs/releng" "$WORK_DIR"
cd "$WORK_DIR"

echo "🟡 [3/8] Customizing packages and system..."
cat <<EOL >> packages.x86_64

# Desktop, window management, effects, themes
plasma-meta sddm xorg kdeplasma-addons bismuth-git krohnkite-git
wmctrl xdotool tmux rofi picom kvantum-qt5 kvantum-theme-sweet qt5ct qt6ct
orchis-theme sweet-gtk-theme-git papirus-icon-theme pywal variety feh btop neofetch
networkmanager nano zsh fzf ripgrep xclip flameshot

# AI/automation
python python-pip python-openai git

# Media
pipewire pipewire-alsa pipewire-pulse

EOL

# --- Systemd and autostart for demo scripts ---
mkdir -p airootfs/etc/systemd/system/getty@tty1.service.d/
cat <<EOL > airootfs/etc/systemd/system/getty@tty1.service.d/autologin.conf
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin root --noclear %I \$TERM
EOL

# --- Custom desktop autoruns for demo ---
mkdir -p airootfs/root/.config/autostart
cat <<EOL > airootfs/root/.config/autostart/elysium-demo.desktop
[Desktop Entry]
Type=Application
Exec=/root/scripts/elysium-demo.sh
Hidden=false
X-GNOME-Autostart-enabled=true
Name=Elysium Demo Startup
Comment=Runs demo UI for screenshot workflow
EOL

# --- Demo script: open apps, set wallpaper, trigger screenshots ---
mkdir -p airootfs/root/scripts
cat <<'EOL' > airootfs/root/scripts/elysium-demo.sh
#!/usr/bin/env bash
export DISPLAY=:0
sleep 8
feh --bg-scale /usr/share/backgrounds/archlinux/archlinux-simplyblack.jpg || true
picom --config /root/.config/picom.conf &
sleep 3
konsole --hold -e "neofetch; echo 'Elysium OS Demo!'; sleep 12" &
sleep 2
rofi -show drun -theme Sweet &
btop &
sleep 2
tmux new-session -d -s demo 'htop'
sleep 2
# Wait for Xvfb screenshot service to do its job
sleep 40
poweroff
EOL
chmod +x airootfs/root/scripts/elysium-demo.sh

# --- Picom (blur/transparency/rounded corners) ---
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

# --- KDE/Plasma global theming ---
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

# --- QEMU + XVFB: Automated boot and screenshots ---
ISO_PATH="$OUT_DIR/$ISO_NAME-$(date +%Y.%m.%d)-x86_64.iso"
if [[ ! -f $ISO_PATH ]]; then
  ISO_PATH=$(ls $OUT_DIR/*.iso | head -1)
fi

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

sleep 15
for i in {1..4}; do
  import -display :99 -window root "$SCREENSHOT_DIR/elysium-desktop-$i.png"
  sleep $SCREENSHOT_INTERVAL
done

kill $QEMU_PID || true
kill $XVFB_PID || true

echo "🟢 [6/8] All done! ISO and screenshots in $OUT_DIR and $SCREENSHOT_DIR"