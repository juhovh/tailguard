#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (C) 2015-2020 Jason A. Donenfeld <Jason@zx2c4.com>. All Rights Reserved.
# Copyright (C) 2025 Juho Vähä-Herttua <juhovh@iki.fi>. All Rights Reserved.

# Checks if WireGuard config has a default route, adds --advertise-exit-node if yes
# Parses all subnets from AllowedIPs and adds --advertise-routes= with them if found

set -e
shopt -s nocasematch
shopt -s extglob
export LC_ALL=C

CONFIG_FILE="$1"
[[ $CONFIG_FILE =~ ^[a-zA-Z0-9_=+.-]{1,15}$ ]] && CONFIG_FILE="/etc/wireguard/$CONFIG_FILE.conf"
[[ $CONFIG_FILE =~ /?([a-zA-Z0-9_=+.-]{1,15})\.conf$ ]]
INTERFACE="${BASH_REMATCH[1]}"
DEFAULT_FOUND=0
SUBNETS_FOUND=""

process_peer() {
	[[ $PEER_SECTION -ne 1 || -z $ALLOWED_IPS ]] && return 0
	for ip in $(echo "${ALLOWED_IPS}" | tr "," "\n"); do
		eval "$(ipcalc -n -p "$ip")"; subnet="$NETWORK/$PREFIX"
		if [ "$subnet" = "0.0.0.0/0" ]; then DEFAULT_FOUND=1; continue; fi
		if [ "$subnet" = "::/0" ]; then DEFAULT_FOUND=1; continue; fi
		if [ -z "$SUBNETS_FOUND" ]; then
			SUBNETS_FOUND="$subnet"
		else
			SUBNETS_FOUND="$SUBNETS_FOUND,$subnet"
		fi
	done
	reset_peer_section
}

reset_peer_section() {
	PEER_SECTION=0
	ALLOWED_IPS=""
}

reset_peer_section
while read -r line || [[ -n $line ]]; do
	stripped="${line%%\#*}"
	key="${stripped%%=*}"; key="${key##*([[:space:]])}"; key="${key%%*([[:space:]])}"
	value="${stripped#*=}"; value="${value##*([[:space:]])}"; value="${value%%*([[:space:]])}"
	[[ $key == "["* ]] && { process_peer; reset_peer_section; }
	[[ $key == "[Peer]" ]] && PEER_SECTION=1
	if [[ $PEER_SECTION -eq 1 ]]; then
		case "$key" in
		AllowedIPs) ALLOWED_IPS="$value"; continue ;;
		esac
	fi
done < "$CONFIG_FILE"
process_peer

TS_EXTRA_ARGS="--reset --accept-routes"
if [ $DEFAULT_FOUND -eq 1 ]; then TS_EXTRA_ARGS="$TS_EXTRA_ARGS --advertise-exit-node"; fi
if [ -n "$SUBNETS_FOUND" ]; then TS_EXTRA_ARGS="$TS_EXTRA_ARGS --advertise-routes=$SUBNETS_FOUND"; fi
echo "$TS_EXTRA_ARGS"
