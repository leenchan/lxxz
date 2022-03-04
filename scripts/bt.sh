#!/bin/sh
CUR_DIR=$(cd "$(dirname "$0")";pwd)
CUR_FILE="${CUR_DIR}/$(echo "$0" | awk -F'/' '{print $NF}')"
. ${CUR_DIR}/_common.sh

BT_BIN="$APPS_DIR/qbittorrent/qbittorrent-nox"
BT_ROOT_DIR="$ROOT_DIR"
BT_PROFILE_DIR="$ROOT_DIR/qBittorrent"
BT_PROFILE_CONF_DIR="$BT_PROFILE_DIR/config"
BT_PROFILE_CONF_FILE="$BT_PROFILE_CONF_DIR/qBittorrent.conf"
BT_DOWNLOAD_DIR="$ROOT_DIR/downloads"
BT_WEBUI_PORT="4080"

_api() {
	# API WIKI
	# https://github.com/qbittorrent/qBittorrent/wiki/WebUI-API-(qBittorrent-4.1)
	__API_HOST__="${API_HOST:-127.0.0.1}"
	__API_URL__="http://${__API_HOST__}:${BT_WEBUI_PORT}/api/v2"
	__API_OPTION__=""
	# __API_OPTION__="-J 'Cookie: $API_TOKEN'"
	eval $(echo "$1" | awk -F'/' '{print "__PATH_A__=\""$1"\"; __PATH_B__=\""$2"\"; __PATH_C__=\""$3"\""}')
	case "$__PATH_A__" in
		"login")
			__API_URL__="${__API_URL__}/auth/login"
			__API_OPTION__="-i -d 'username=${USERNAME}&password=${PASSWORD}'"
			;;
		"version")
			__API_URL__="${__API_URL__}/app/version"
			;;
		"get")
			__API_URL__="${__API_URL__}/app/preferences"
			__API_OPTION__="${__API_OPTION__} -d '${2}'"
			;;
		"set")
			__API_URL__="${__API_URL__}/app/setPreferences"
			;;
		"torrents")
			if [ -z "$__PATH_B__" ]; then
				# /api/v2/torrents/info?filter=downloading&category=sample%20category&sort=ratio
				__API_URL__="${__API_URL__}/torrents/info"
			else
				# __PATH_B__: task hash
				case "$__PATH_C__" in
					"trackers"|"seeds"|"files"|"pieces"|"pause"|"resume"|"delete"|"purge"|"recheck"|"reannounce")
						[ "$__PATH_C__" = "pieces" ] && __PATH_C__="pieceStates"
						__API_URL__="${__API_URL__}/torrents/trackers?hash=${__PATH_B__}"
						[ "$__PATH_C__" = "purge" ] && __API_URL__="${__API_URL__}/torrents/delete?hash=${__PATH_B__}&deleteFiles=true"
						;;
					"addTrackers")
						# ${2}: urls=http://192.168.0.1/announce%0Audp://192.168.0.1:3333/dummyAnnounce
						__API_URL__="${__API_URL__}/torrents/addTrackers?hash=${__PATH_B__}&urls=${2}"
						;;
					*)
						__API_URL__="${__API_URL__}/torrents/properties?hash=${__PATH_B__}"
				esac
			fi
			;;
		"add")
			__API_URL__="${__API_URL__}/torrents/add"
			# __API_OPTION__="${__API_OPTION__} -X POST"
			shift
			while true
			do
				[ "$#" -le 0 ] && break
				[ -f "$1" ] && __API_OPTION__="${__API_OPTION__} -F 'torrents=@${1}'" || __API_OPTION__="${__API_OPTION__} -F 'urls=${1}'"
				shift
			done
			# cookie, category=movies, skip_checking=true, paused=true, root_folder=true, savepath
			;;
	esac
	eval "curl -skL $__API_OPTION__ $__API_URL__"
	__CODE__=$?
	[ "$LOG_ENABLED" = "1" ] && echo "curl $__API_OPTION__ $__API_URL__" >> $LOG_FILE
	return $__CODE__
}

_create_config() {
	echo "[INFO] Create qBittorrent Configuration."
	echo "BT_PROFILE_CONF_DIR: $BT_PROFILE_CONF_DIR"
	echo "BT_PROFILE_CONF_FILE: $BT_PROFILE_CONF_FILE"
	mkdir -p "$BT_PROFILE_CONF_DIR"
	cat <<-EOF > "$BT_PROFILE_CONF_FILE"
	[AutoRun]
	enabled=true
	program=sh $CUR_FILE upload \"%R\"
	
	[LegalNotice]
	Accepted=true

	[Network]
	Cookies=@Invalid()

	[Preferences]
	Downloads\SavePath=${BT_DOWNLOAD_DIR}/
	Downloads\UseIncompleteExtension=true
	Connection\PortRangeMin=6990
	Queueing\QueueingEnabled=false
	Bittorrent\AutoUpdateTrackers=true
	Bittorrent\CustomizeTrackersListUrl=https://raw.githubusercontent.com/XIU2/TrackersListCollection/master/all.txt
	WebUI\Port=$BT_WEBUI_PORT
	WebUI\LocalHostAuth=false
	WebUI\AuthSubnetWhitelist=${N2N_LAN_IP_PREFIX}.0/24
	WebUI\AuthSubnetWhitelistEnabled=true
	EOF
}

_init() {
	grep -q 'Accepted=true' "$BT_PROFILE_CONF_FILE" || _create_config
	${BT_BIN} --version
	${BT_BIN} --profile="$BT_ROOT_DIR" &
}

_download() {
	__OK__="0"
	# http://, https://, magnet:, bc://bt/, torrent://
	__URL__=$(echo "$1" | awk '{gsub(/^\s+/,"",$0); gsub(/\s+$/,"",$0); print $0}')
	# __URL__="https://88btbtt.com/attach-download-fid-951-aid-5415333.htm"
	if echo "$__URL__" | grep -Eq '^(magnet:|bc://bt/)'; then
		_api add "$__URL__" && __OK__="1"
	elif echo "$__URL__" | grep -Eq '^(torrent://)'; then
		__FILE__="/tmp/torrent_file"
		if echo "$__URL__" | grep -Eq '^torrent://https?://'; then
			curl -skL -o "$__FILE__" "$(echo "$__URL__" | sed -E 's/^torrent:\/\///')"
		else
			echo "$__URL__" | sed -E '1s|^torrent://||' | base64 -d > $__FILE__
		fi
		file "$__FILE__" | grep -iq 'torrent' && _api add "$__FILE__" && __OK__="1"
	fi
	[ "$__OK__" = "1" ] && echo "[OK] Success to add BitTorrent task." && return 0
	echo "[ERR] Failed to add BitTorrent task."
	return 1
}

_upload() {
	# echo "cp -rf \"$@\" $ALIYUNDRIVE_DL_DIR/" >> $LOG_FILE
	# cp -rf "$@" $ALIYUNDRIVE_DL_DIR/
	sh ${CUR_DIR}/aliyundrive.sh upload "$@"
}

[ -z "$1" ] || {
	ACTION="$1"
	shift
}

case "$ACTION" in
	"init")
		_init
		;;
	"download"|"dl")
		_download "$@"
		;;
	"upload"|"up")
		_upload "$@"
		;;
	"log")
		shift
		echo $@ >> /tmp/bt.log
		;;
	"api"|"i")
		_api "$@"
		;;
esac
