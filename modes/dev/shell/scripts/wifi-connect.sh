#!/usr/bin/env bash
# Joins a secured Wi-Fi network for the first time (the control center's password box).
#   wifi-connect.sh <device> <ssid> <security>     the password comes on standard input
# The password never appears in a command line (other programs could read it from the
# process list): NetworkManager gets it from a passwd-file read from standard input.
# It saves a profile named after the network; if the password is wrong, the profile is
# removed again so the next try asks again. Prints one line for the box when it fails.
dev=$1 ssid=$2 sec=$3
IFS= read -r pw

case $sec in
    *802.1X*) echo "This network needs a username too (work or school Wi-Fi): set it up with nmtui"; exit 3 ;;
esac
# WPA3 only: SAE; anything with WPA2/WPA1 in it: the usual pre-shared key
km=wpa-psk
[[ $sec == *WPA3* && $sec != *WPA2* && $sec != *WPA1* ]] && km=sae

# an empty profile with the network's name (a first try that never connected) goes;
# a real one keeps its name and this one gets a name of its own
name=$ssid
ts=$(nmcli -g connection.timestamp connection show id "$ssid" 2>/dev/null)
if [ "$ts" = 0 ]; then nmcli connection delete id "$ssid" >/dev/null 2>&1
elif [ -n "$ts" ]; then name="$ssid (Tide)"; fi

if ! out=$(nmcli connection add type wifi con-name "$name" ${dev:+ifname "$dev"} ssid "$ssid" \
        wifi-sec.key-mgmt "$km" 2>&1); then
    echo "Couldn't set it up: ${out##*Error: }"; exit 1
fi
if out=$(printf '802-11-wireless-security.psk:%s\n' "$pw" | nmcli --wait 30 connection up "$name" passwd-file /dev/stdin 2>&1); then
    exit 0
fi
nmcli connection delete "$name" >/dev/null 2>&1
case $out in
    *"Secrets were required"*|*"802-1x"*|*"supplicant"*|*"key"*|*"password"*) echo "Wrong password" ;;
    *"not found"*|*"could not be found"*|*"No network"*) echo "The network is out of range" ;;
    *) echo "Couldn't connect: $(printf '%s' "${out##*Error: }" | head -1 | cut -c1-80)" ;;
esac
exit 1
