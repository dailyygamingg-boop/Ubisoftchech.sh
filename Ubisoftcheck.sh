#!/usr/bin/env bash
# steam-proton-fix.sh
# Zenity-GUI zum Fixen und Starten von Ubisoft-Spielen unter Proton
# Für RebornOS / Arch. Voraussetzung: zenity, steam

set -uo pipefail

# ---------- Spiele-Datenbank ----------
declare -A GAMES=(
  ["Tom Clancy's The Division"]="365590"
  ["Tom Clancy's The Division 2"]="2221490"
  ["Assassin's Creed Odyssey"]="812140"
  ["Assassin's Creed Origins"]="582160"
  ["Assassin's Creed Shadows"]="3159330"
  ["Far Cry 5"]="552520"
  ["Far Cry 6"]="2369390"
  ["Ghost Recon Wildlands"]="460930"
  ["Rainbow Six Siege"]="359550"
  ["Watch_Dogs"]="243470"
  ["Watch Dogs 2"]="447040"
  ["Anno 1800"]="916440"
)

OK="✅"; WARN="⚠️"; ERR="❌"

# ---------- Steam-Root ----------
find_steam_root() {
  local candidates=(
    "$HOME/.steam/steam"
    "$HOME/.local/share/Steam"
    "$HOME/.var/app/com.valvesoftware.Steam/data/Steam"
  )
  for c in "${candidates[@]}"; do
    [[ -d "$c" ]] && { echo "$c"; return 0; }
  done
  return 1
}

find_library_folders() {
  local root="$1"
  echo "$root/steamapps"
  local vdf="$root/steamapps/libraryfolders.vdf"
  [[ -f "$vdf" ]] || return 0
  grep -oP '"path"\s*"\K[^"]+' "$vdf" 2>/dev/null | while read -r p; do
    [[ -d "$p/steamapps" ]] && echo "$p/steamapps"
  done
}

find_install_dir() {
  local root="$1" appid="$2"
  while read -r lib; do
    local manifest="$lib/appmanifest_${appid}.acf"
    if [[ -f "$manifest" ]]; then
      local idir
      idir=$(grep -oP '"installdir"\s*"\K[^"]+' "$manifest" 2>/dev/null | head -1)
      [[ -n "$idir" ]] && echo "$lib/common/$idir"
      return 0
    fi
  done < <(find_library_folders "$root")
  return 1
}

find_compatdata() {
  local root="$1" appid="$2"
  while read -r lib; do
    local cd="$lib/compatdata/$appid"
    [[ -d "$cd" ]] && { echo "$cd"; return 0; }
  done < <(find_library_folders "$root")
  return 1
}

# ---------- Alle installierten Proton-Versionen ----------
list_proton_versions() {
  local root="$1"
  local pdir="$root/steamapps/common"
  [[ -d "$pdir" ]] && find "$pdir" -maxdepth 1 -type d -name 'Proton*' 2>/dev/null | sort
  local ct="$HOME/.steam/root/compatibilitytools.d"
  [[ -d "$ct" ]] && find "$ct" -maxdepth 1 -type d -iname '*proton*' 2>/dev/null | sort
}

# ---------- Proton-Version setzen ----------
set_proton_version() {
  local root="$1" appid="$2" proton="$3"
  local userdata="$root/userdata"
  [[ -d "$userdata" ]] || return 1
  local changed=0

  for user_dir in "$userdata"/*; do
    local lc="$user_dir/config/localconfig.vdf"
    [[ -f "$lc" ]] || continue

    if grep -qP "\"$appid\"\s*\{" "$lc"; then
      [[ -f "$lc.bak" ]] || cp "$lc" "$lc.bak"
      awk -v appid="$appid" -v proton="$proton" '
        BEGIN{inblock=0; depth=0}
        {
          if (!inblock && $0 ~ "\"" appid "\"[[:space:]]*\\{") { inblock=1; depth=1; print; next }
          if (inblock) {
            if ($0 ~ /\{/) depth++
            if ($0 ~ /\}/) { depth--; if (depth==0) { inblock=0; print; next } }
            if ($0 ~ /"name"/) sub(/"name"[[:space:]]*"[^"]*"/, "\"name\"\t\t\"" proton "\"")
          }
          print
        }
      ' "$lc.bak" > "$lc"
      changed=1
    else
      if grep -q '"CompatToolMapping"' "$lc"; then
        [[ -f "$lc.bak" ]] || cp "$lc" "$lc.bak"
        awk -v appid="$appid" -v proton="$proton" '
          {print}
          /"CompatToolMapping"[[:space:]]*\{/ && !done {
            printf "\t\t\t\t\t\"%s\"\n", appid
            printf "\t\t\t\t\t{\n\t\t\t\t\t\t\"name\"\t\t\"%s\"\n\t\t\t\t\t\t\"config\"\t\t\"\"\n\t\t\t\t\t\t\"Priority\"\t\t250\n\t\t\t\t\t}\n", proton
            done=1
          }
        ' "$lc.bak" > "$lc"
        changed=1
      fi
    fi
  done
  [[ $changed -eq 1 ]]
}

# ---------- LaunchOptions setzen ----------
set_launch_options() {
  local root="$1" appid="$2" opts="$3"
  local userdata="$root/userdata"
  [[ -d "$userdata" ]] || return 1
  local changed=0

  for user_dir in "$userdata"/*; do
    local lc="$user_dir/config/localconfig.vdf"
    [[ -f "$lc" ]] || continue

    if grep -qP "\"$appid\"\s*\{" "$lc"; then
      [[ -f "$lc.bak" ]] || cp "$lc" "$lc.bak"
      awk -v appid="$appid" -v opts="$opts" '
        BEGIN{inblock=0; depth=0; has_launch=0}
        {
          if (!inblock && $0 ~ "\"" appid "\"[[:space:]]*\\{") {
            inblock=1; depth=1; has_launch=0; print; next
          }
          if (inblock) {
            if ($0 ~ /"LaunchOptions"/) { has_launch=1 }
            if ($0 ~ /\{/) depth++
            if ($0 ~ /\}/) {
              depth--
              if (depth==0) {
                if (!has_launch) printf "\t\t\t\t\t\"LaunchOptions\"\t\t\"%s\"\n", opts
                inblock=0; print; next
              }
            }
            if ($0 ~ /"LaunchOptions"/) sub(/"LaunchOptions"[[:space:]]*"[^"]*"/, "\"LaunchOptions\"\t\t\"" opts "\"")
          }
          print
        }
      ' "$lc.bak" > "$lc"
      changed=1
    fi
  done
  [[ $changed -eq 1 ]]
}

# ---------- Diagnose ----------
run_diagnose() {
  local name="$1" appid="$2"
  local out=""
  out+="=== Diagnose: $name (AppID $appid) ===\n\n"

  local root
  if ! root=$(find_steam_root); then
    printf "%b" "$ERR Steam-Root nicht gefunden\n"
    return
  fi
  out+="Steam-Root: $root\n\n"

  local install
  if install=$(find_install_dir "$root" "$appid"); then
    out+="$OK Installiert: $install\n"
  else
    out+="$WARN Nicht in Steam-Bibliothek gefunden\n"
  fi

  local cd
  if cd=$(find_compatdata "$root" "$appid"); then
    out+="$OK compatdata: $cd\n"
    [[ -d "$cd/pfx" ]] && out+="   Prefix: vorhanden\n" || out+="   Prefix: $ERR fehlt\n"
    local uc="$cd/pfx/drive_c/Program Files (x86)/Ubisoft/Ubisoft Game Launcher/UbisoftConnect.exe"
    [[ -f "$uc" ]] && out+="   Ubisoft Connect: $OK gefunden\n" || out+="   Ubisoft Connect: $WARN nicht gefunden\n"
  else
    out+="$ERR Kein compatdata – nie mit Proton gestartet\n"
  fi

  out+="\nInstallierte Proton-Versionen:\n"
  while IFS= read -r p; do
    [[ -n "$p" ]] && out+="   - $(basename "$p")\n"
  done < <(list_proton_versions "$root")

  printf "%b" "$out"
}

# ---------- Spiel starten ----------
launch_game() {
  local name="$1" appid="$2"

  if ! command -v steam &>/dev/null; then
    zenity --error --width=440 --text="'steam' nicht im PATH gefunden.\n\nStarte Steam einmal normal, oder prüfe, ob du die Flatpak-Version nutzt."
    return 1
  fi

  # Prefix-Check: erst starten, wenn Proton den Prefix angelegt hat
  local root cd
  root=$(find_steam_root)
  if [[ -n "$root" ]]; then
    cd=$(find_compatdata "$root" "$appid")
    if [[ -z "$cd" || ! -d "$cd/pfx" ]]; then
      zenity --question --width=520 \
        --text="Für '$name' existiert noch kein Proton-Prefix.\n\nBeim ersten Start baut Steam ihn automatisch auf — das kann beim ersten Mal länger dauern oder hängen.\n\nTrotzdem starten?"
      [[ $? -ne 0 ]] && return 1
    fi
  fi

  # Steam läuft? Wenn nicht, starten wir es headless im Hintergrund
  if ! pgrep -x steam >/dev/null 2>&1; then
    zenity --info --width=440 --text="Steam läuft nicht. Ich starte Steam jetzt und danach das Spiel.\n\nDas kann ein paar Sekunden dauern."
    nohup steam &>/dev/null &
    sleep 6
  fi

  # Spiel starten
  nohup steam -applaunch "$appid" &>/dev/null &
  zenity --info --width=520 \
    --text="Startbefehl abgesetzt:\n\nsteam -applaunch $appid\n\nWenn nach 1–2 Minuten kein Fenster kommt:\n• Alt+Tab drücken\n• Prefix mit dem Skript zurücksetzen\n• andere Proton-Version wählen"
  return 0
}

# ---------- Hauptmenü ----------
game_names=()
for k in "${!GAMES[@]}"; do game_names+=("$k"); done
IFS=$'\n' game_names=($(sort <<<"${game_names[*]}")); unset IFS

selected=$(zenity --list --title="Steam Proton Fix" \
  --text="Spiel auswählen:" --column="Spiel" \
  --width=480 --height=520 "${game_names[@]}") || exit 0
[[ -z "$selected" ]] && exit 0
appid="${GAMES[$selected]}"

while true; do
  action=$(zenity --list --title="Aktion: $selected" \
    --text="AppID: $appid" --column="Aktion" \
    --width=460 --height=420 \
    "Spiel starten" \
    "Diagnose ausführen" \
    "Proton-Version wählen" \
    "LaunchOptions setzen (Fix)" \
    "Prefix resetten (löscht Anmeldung!)" \
    "Anderes Spiel wählen" \
    "Beenden") || exit 0

  case "$action" in
    "Spiel starten")
      launch_game "$selected" "$appid"
      ;;

    "Diagnose ausführen")
      root=$(find_steam_root)
      [[ -z "$root" ]] && { zenity --error --text="Steam-Root nicht gefunden."; continue; }
      diag=$(run_diagnose "$selected" "$appid")
      zenity --text-info --title="Diagnose: $selected" --width=720 --height=520 --filename=<(printf "%s" "$diag")
      ;;

    "Proton-Version wählen")
      root=$(find_steam_root)
      [[ -z "$root" ]] && continue
      versions=()
      while IFS= read -r p; do
        [[ -n "$p" ]] && versions+=("$(basename "$p")")
      done < <(list_proton_versions "$root")
      [[ ${#versions[@]} -eq 0 ]] && { zenity --error --text="Keine Proton-Versionen gefunden."; continue; }

      choice=$(zenity --list --title="Proton-Version wählen" \
        --text="Empfehlung für Watch_Dogs:\nProton 8.0-5, Proton 7.0-6 oder GE-Proton 8.x (nicht Experimental)" \
        --column="Version" --width=520 --height=400 "${versions[@]}") || continue
      [[ -z "$choice" ]] && continue

      if set_proton_version "$root" "$appid" "$choice"; then
        zenity --info --width=460 --text="Proton auf '$choice' gesetzt.\n\nSteam neu starten!"
      else
        zenity --error --width=460 --text="Konnte Proton-Version nicht ändern.\nSteam einmal starten, damit localconfig.vdf existiert."
      fi
      ;;

    "LaunchOptions setzen (Fix)")
      root=$(find_steam_root)
      [[ -z "$root" ]] && continue

      opts=$(zenity --list --title="LaunchOptions wählen" \
        --text="Fix-Kombination für Ubisoft Connect:" \
        --column="Fix" --width=620 --height=420 \
        "PROTON_NO_NTSYNC=1 %command%  (Ubisoft Connect Fix)" \
        "PROTON_ENABLE_WAYLAND=0 %command%  (Xwayland erzwingen)" \
        "PROTON_NO_STEAM_INPUT=1 %command%  (Steam Input aus)" \
        "PROTON_NO_NTSYNC=1 PROTON_ENABLE_WAYLAND=0 %command%  (Kombi)" \
        "PROTON_NO_NTSYNC=1 PROTON_NO_STEAM_INPUT=1 %command%  (Kombi)" \
        "PROTON_NO_NTSYNC=1 PROTON_ENABLE_WAYLAND=0 PROTON_NO_STEAM_INPUT=1 %command%  (alles)" \
        "LaunchOptions leeren") || continue

      [[ -z "$opts" ]] && continue
      [[ "$opts" == "LaunchOptions leeren" ]] && opts=""

      if set_launch_options "$root" "$appid" "$opts"; then
        zenity --info --width=520 --text="LaunchOptions gesetzt:\n\n$opts\n\nSteam neu starten!"
      else
        zenity --error --width=520 --text="Konnte LaunchOptions nicht ändern.\nSteam einmal starten."
      fi
      ;;

    "Prefix resetten (löscht Anmeldung!)")
      root=$(find_steam_root)
      [[ -z "$root" ]] && continue
      cd=$(find_compatdata "$root" "$appid") || { zenity --info --text="Kein compatdata vorhanden."; continue; }
      zenity --question --width=480 --text="Prefix wirklich löschen?\n\n$cd\n\nUbisoft-Anmeldung geht verloren!" || continue
      if rm -rf "$cd"; then
        zenity --info --width=380 --text="Prefix gelöscht.\nNächster Start baut ihn neu auf."
      else
        zenity --error --width=380 --text="Fehler beim Löschen."
      fi
      ;;

    "Anderes Spiel wählen") break ;;
    "Beenden"|"") exit 0 ;;
  esac
done

exec "$0"
