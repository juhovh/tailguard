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

PORTS_FOUND=""
DEFAULT_ROUTES_FOUND=0
SUBNETS_FOUND=""

process_section() {
	if [[ $INTERFACE_SECTION -eq 1 && -n $LISTEN_PORT ]]; then
		[[ -n $PORTS_FOUND ]] && PORTS_FOUND="$PORTS_FOUND,"
		PORTS_FOUND="$PORTS_FOUND$LISTEN_PORT"
	elif [[ $PEER_SECTION -eq 1 && -n $ALLOWED_IPS ]]; then
		for ip in $(echo "${ALLOWED_IPS}" | tr "," "\n"); do
			eval "$(ipcalc -n -p "$ip")"; subnet="$NETWORK/$PREFIX"
			if [[ "$subnet" = "0.0.0.0/0" || "$subnet" = "::/0" ]]; then
				DEFAULT_ROUTES_FOUND=1;
				continue;
			fi
			[[ -n $SUBNETS_FOUND ]] && SUBNETS_FOUND="$SUBNETS_FOUND,"
			SUBNETS_FOUND="$SUBNETS_FOUND$subnet"
		done
	fi
	reset_section
}

reset_section() {
	INTERFACE_SECTION=0
	PEER_SECTION=0
	LISTEN_PORT=""
	ALLOWED_IPS=""
}

reset_section
while read -r line || [[ -n $line ]]; do
	stripped="${line%%\#*}"
	key="${stripped%%=*}"; key="${key##*([[:space:]])}"; key="${key%%*([[:space:]])}"
	value="${stripped#*=}"; value="${value##*([[:space:]])}"; value="${value%%*([[:space:]])}"
	[[ $key == "["* ]] && { process_section; reset_section; }
	[[ $key == "[Interface]" ]] && INTERFACE_SECTION=1
	[[ $key == "[Peer]" ]] && PEER_SECTION=1
	if [[ $INTERFACE_SECTION -eq 1 ]]; then
		case "$key" in
		ListenPort) LISTEN_PORT="$value"; continue ;;
		esac
	fi
	if [[ $PEER_SECTION -eq 1 ]]; then
		case "$key" in
		AllowedIPs) ALLOWED_IPS="$value"; continue ;;
		esac
	fi
done < "$CONFIG_FILE"
process_section


[[ -n PORTS_FOUND ]] && echo "WG_PORTS_FOUND=\"$PORTS_FOUND\""
[[ $DEFAULT_ROUTES_FOUND -eq 1 ]] && echo "WG_DEFAULT_ROUTES_FOUND=1"
[[ -n SUBNETS_FOUND ]] && echo "WG_SUBNETS_FOUND=\"$SUBNETS_FOUND\""
