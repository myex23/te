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

# Desktop Environment and Window Management
plasma-meta sddm xorg kdeplasma-addons

# Window tools (AUR packages such as bismuth-git and krohnkite-git removed because they are not official)
wmctrl xdotool tmux rofi picom

# UI theming (only official repos)
fastfetch

# System utilities
pywal feh btop

# AI / Automation
python python-pip git

# Multimedia
pipewire pipewire-alsa pipewire-pulse
EOL

# --- Setup systemd for autologin ---
mkdir -p airootfs/etc/systemd/system/getty@tty1.service.d/
cat <<EOL > airootfs/etc/systemd/system/getty@tty1.service.d/autologin.conf
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin root --noclear %I \$TERM
EOL

# --- Setup desktop autostart for demo ---
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

# --- Demo script to launch the UI and then shutdown ---
cat <<'EOL' > airootfs/root/scripts/elysium-demo.sh
#!/usr/bin/env bash
export DISPLAY=:0
sleep 8
feh --bg-scale /usr/share/backgrounds/archlinux/archlinux-simplyblack.jpg || true
picom --config /root/.config/picom.conf &
sleep 3
konsole --hold -e "fastfetch; echo 'Elysium OS Demo!'; sleep 12" &
sleep 2
rofi -show drun -theme Sweet &
btop &
sleep 2
tmux new-session -d -s demo 'htop'
sleep 2
sleep 40
poweroff
EOL
chmod +x airootfs/root/scripts/elysium-demo.sh

# --- Picom configuration ---
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

# --- Build ISO ---
echo "🔵 [4/8] Building ISO..."
mkarchiso -v -o "../$OUT_DIR" .
cd ..

# --- QEMU + Xvfb: Boot the ISO and take a screenshot ---
ISO_PATH="$(ls $OUT_DIR/*.iso | head -1)"
echo "🟠 [5/8] Booting ISO in QEMU for screenshot capture..."
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
# Grab one screenshot for the showcase
import -display :99 -window root "$SCREENSHOT_DIR/elysium-showcase.png"

kill $QEMU_PID || true
kill $XVFB_PID || true

echo "🟢 [6/8] Build complete!"
echo "ISO is available in the '$OUT_DIR' directory and the screenshot is in '$SCREENSHOT_DIR'."