#!/bin/sh
CUR_DIR=$(cd "$(dirname "$0")";pwd)
. ${CUR_DIR}/_common.sh
RCLONE_APP_DIR="$APPS_DIR/rclone"
RCLONE_BIN="$RCLONE_APP_DIR/rclone"
RCLONE_ALIYUNDRIVE_NAME="aliyun"

_webdav_sample() {
	# Reading Files/Folders on Webdav Server:
	curl 'https://example.com/webdav'
	# Deleting Files/Folders on Webdav Server:
	curl -X DELETE 'https://example.com/webdav/test'
	curl -X DELETE 'https://example.com/webdav/test.txt'
	# Renaming File on Webdav Server:
	curl -X MOVE --header 'Destination:http://example.org/new.txt' 'https://example.com/old.txt'
	# Creating new foder on Webdav Server:
	curl -X MKCOL 'https://example.com/new_folder'
	# Uploading File on Webdav Server:
	curl -T '/path/to/local/file.txt' 'https://example.com/test/'
	# Username/Password
	curl --user 'user:pass' 'https://example.com'
}

_webdav_cli() {
	_get_aliyundrive_host || return 1
	__ALIYUNDRIVE_URL__="http://${ALIYUNDRIVE_HOST}:${ALIYUNDRIVE_PORT}"
	__CMD__="curl"
	__ACTION__="$1"
	[ -z "$__ACTION__" ] || shift
	__URL__="${__ALIYUNDRIVE_URL__}/${1}"
	__FILE_SIZE__=""
	case "$__ACTION__" in
		"download"|"dl")
			__ACTION__="DOWNLOAD"
			echo "[DL] ${__URL__}"
			__FILE__="$CUR_DIR/$(echo "$1" | awk -F'/' '{print $NF}')"
			[ -z "$2" ] || {
				__FILE__="$2"
			}
			__CMD__="${__CMD__} '${__URL__}' -o '${__FILE__}'"
			;;
		"upload"|"up")
			__ACTION__="UPLOAD"
			echo "[UP] $2 => ${__URL__}"
			__FILE__="$2"
			__CMD__="${__CMD__} '${__URL__}' -T '$(echo "$__FILE__" | sed -E 's/\[/\\[/g; s/\]/\\]/g')'"
			;;
		"remove"|"rm")
			__ACTION__="REMOVE"
			echo "[DEL] $1"
			__CMD__="${__CMD__} '${__URL__}' -s -X DELETE"
			;;
		"rename"|"mv")
			__ACTION__="MOVE"
			echo "[MV] $__URL__ => ${__ALIYUNDRIVE_URL__}/$2"
			__CMD__="${__CMD__} '${__URL__}' -s -X MOVE --header 'Destination:${__ALIYUNDRIVE_URL__}/${2}'"
			;;
		"mkdir"|"md")
			__ACTION__="MKDIR"
			echo "[MD] $__URL__"
			__CMD__="${__CMD__} '${__URL__}' -s -X MKCOL"
			;;
		*)
			return 1
			;;
	esac
	__START__=$(get_now_time ms)
	eval "${__CMD__}"
	__CODE__="$?"
	__END__=$(get_now_time ms)
	__DURATION__=$(echo "$__START__:$__END__" | awk -F':' '{print ($2-$1);}')
	__DEBUG_MSG__="${__ACTION__}: ${__CMD__} \"${_URL_}\" (CODE:$__CODE__ TIME:${__DURATION__}s)"
	[ "$__ACTION__" = "DOWNLOAD" -o "$__ACTION__" = "UPLOAD" ] && {
		__FILE_SIZE__=$(_get_size "$__FILE__" "MB")
		__SPEED__=$(echo "${__DURATION__}:${__FILE_SIZE__}" | awk -F':' '{printf ("%.2f M/s", $2/$1)}')
		__DEBUG_MSG__="${__ACTION__}: ${__CMD__} (CODE:$__CODE__ TIME:${__DURATION__}s SIZE:${__FILE_SIZE__}MB SPEED:${__SPEED__})"
	}
	debug_log "$__DEBUG_MSG__"
	return $__CODE__
}

_upload_with_curl() {
	[ -z "$1" ] && return 1
	_REMOTE_NAME_=$(echo "$1" | awk -F'/' '{if ($NF=="") {print $(NF-1)} else {print $NF}}')
	_ABS_PATH_=$(get_absolute_path "$1" "$(pwd)")
	# echo "REMOTE_NAME: $_REMOTE_NAME_"
	# echo "LOCAL_DIR: $_ABS_PATH_"
	[ -f "$_ABS_PATH_" ] && {
		_webdav_cli upload "$ALIYUNDRIVE_DL_PREFIX/" "$_ABS_PATH_"
		echo "$1 => $ALIYUNDRIVE_DL_PREFIX/$_REMOTE_NAME_"
	}
	[ -d "$_ABS_PATH_" ] && {
		_ABS_PATH_PREFIX_=$(echo "$_ABS_PATH_" | sed -E 's|\/[^\/]+\/?$||g')
		while read ITEM
		do
			_REMOTE_PATH_=$(echo "$ITEM" | sed -E "s|$_ABS_PATH_PREFIX_||g")
			[ -f "$ITEM" ] && {
				eval $(echo "$_REMOTE_PATH_" | awk -F'/' '{for (i=1;i<=NF;i++) {
					if (i==NF) {_F_NAME_=$i} else {_F_DIR_=_F_DIR_==""?$i:_F_DIR_"/"$i}
				}} END {
					print "_F_DIR_=\""_F_DIR_"\";"
					print "_F_NAME_=\""_F_NAME_"\";"
				}')
				_webdav_cli upload "$ALIYUNDRIVE_DL_PREFIX/$_F_DIR_/" "$ITEM"
			}
			[ -d "$ITEM" ] && {
				_webdav_cli mkdir "$ALIYUNDRIVE_DL_PREFIX$_REMOTE_PATH_"
			}
		done<<-EOF
		$(find "$_ABS_PATH_")
		EOF
	}
	return 0
}

_upload_with_rclone() {
	[ -z "$1" ] && return 1
	__RCLONE_DEST_DIR__="$2"
	[ -z "$__RCLONE_DEST_DIR__" ] && __RCLONE_DEST_DIR__="/$ALIYUNDRIVE_DL_PREFIX"
	_REMOTE_NAME_=$(echo "$1" | awk -F'/' '{if ($NF=="") {print $(NF-1)} else {print $NF}}')
	__ABS_PATH__=$(get_absolute_path "$1" "$(pwd)")
	[ -f "$__ABS_PATH__" ] && {
		echo "$RCLONE_BIN copy -P \"$__ABS_PATH__\" \"$RCLONE_ALIYUNDRIVE_NAME:$__RCLONE_DEST_DIR__\"" >> $LOG_FILE
		$RCLONE_BIN copy -P "$__ABS_PATH__" "$RCLONE_ALIYUNDRIVE_NAME:$__RCLONE_DEST_DIR__" && return 0
	}
	[ -d "$__ABS_PATH__" ] && {
		echo "$RCLONE_BIN copy -P --transfers=1 \"$__ABS_PATH__\" \"$RCLONE_ALIYUNDRIVE_NAME:$__RCLONE_DEST_DIR__/$(echo \"$__ABS_PATH__\" | awk -F'/' '{print $NF}')\"" >> $LOG_FILE
		$RCLONE_BIN copy -P --transfers=1 "$__ABS_PATH__" "$RCLONE_ALIYUNDRIVE_NAME:$__RCLONE_DEST_DIR__/$(echo "$__ABS_PATH__" | awk -F'/' '{print $NF}')" && return 0
	}
	return 1
}

_upload_with_davfs() {
	cp -rf "$1" "${ALIYUNDRIVE_MNT}${2}/" && return 0
	return 1
}

_upload() {
	[ "$#" = "0" ] && return 1
	__ESTIMATE_TIME__=0
	__UPLOAD_ITEMS__=""
	__UPLOAD_WITH__=""
	while true
	do
		[ "$#" -le "0" ] && break
		if [ "$1" = "--dl-dir" -o "$1" = "-D" ]; then
			shift
			[ -z "$1" ] || {
				__REMOTE_DIR__="$1"
				shift
			}
		elif [ "$1" = "--sub-dir" -o "$1" = "-S" ]; then
			shift
			[ -z "$1" ] || {
				__REMOTE_DIR__="/$ALIYUNDRIVE_DL_PREFIX/$1"
				shift
			}
		elif [ "$1" = "--use" -o "$1" = "-U" ]; then
			shift
			[ -z "$1" ] || {
				__UPLOAD_WITH__="$1"
				shift
			}
		elif [ "$1" = "--test" ]; then
			_speedtest
			break
		elif [ "$1" = "--estimate" ]; then
			__ESTIMATE_TIME__="1"
			shift
		else
			__UPLOAD_ITEMS__=$(cat <<-EOF
			$__UPLOAD_ITEMS__
			$1
			EOF
			)
			shift
		fi
	done
	[ -z "$__REMOTE_DIR__" ] && __REMOTE_DIR__="/$ALIYUNDRIVE_DL_PREFIX"
	__UPLOAD_TOTAL__=$(echo "$__UPLOAD_ITEMS__" | wc -l)
	__CURRENT__="1"
	while read __ITEM__
	do
		[ "$__CURRENT__" = "$__UPLOAD_TOTAL__" ] && {
			[ "$__ESTIMATE_TIME__" = "1" ] && _get_upload_speed >/dev/null && {
				__TOTAL_SIZE_KB__=$(echo "$__TOTAL_SIZE__" | awk '{printf ("%.2f",$0/1024)}')
				__TOTAL_SIZE_MB__=$(echo "$__TOTAL_SIZE__" | awk '{printf ("%.2f",$0/1024/1024)}')
				__ESTIMATED_TIME__=$(echo "$__TOTAL_SIZE_KB__:$__UPLOAD_SPEED_KB__" | awk -F':' '{printf ("%.2f", $1/$2)}')
				cat <<-EOF
				UPLOAD_SIZE  : ${__TOTAL_SIZE_MB__} MB
				UPLOAD_SPEED : ${__UPLOAD_SPEED_MB__} MB/s
				ESTIMATE     : ${__ESTIMATED_TIME__} s
				EOF
			}
			break
		}
		if [ "$__ESTIMATE_TIME__" = "1" ]; then
			__CUR_SIZE__=$(_get_size "$__ITEM__")
			__TOTAL_SIZE__=$((__TOTAL_SIZE__+__CUR_SIZE__))
		else
			[ -z "$__ITEM__" ] || {
				case "$__UPLOAD_WITH__" in
					"davfs")
						_upload_with_davfs "$__ITEM__" "$__REMOTE_DIR__"
						;;
					"curl")
						_upload_with_curl "$__ITEM__" "$__REMOTE_DIR__"
						;;
					"rclone")
						_upload_with_rclone "$__ITEM__" "$__REMOTE_DIR__"
						;;
					*)
						_upload_with_rclone "$__ITEM__" "$__REMOTE_DIR__"
						;;
				esac
			}
		fi
	done <<-EOF
	$__UPLOAD_ITEMS__
	EOF
	return 0
}

_download() {
	_webdav_cli download $1
}

_get_estimated_time() {
	_get_size "$1"
}

_get_upload_speed() {
	__UPLOAD_SPEED_SIZE__="${1:-256}"
	__OK__="0"
	__UPLOAD_SPEED__=""
	__UPLOAD_SPEED_NAME__="SPEEDTEST_${_SPEEDTEST_SIZE_}M.$(get_now_time ms)"
	__UPLOAD_SPEED_FILE__="/tmp/$__UPLOAD_SPEED_NAME__"
	dd if=/dev/zero of="${__UPLOAD_SPEED_FILE__}" bs=1M count=${__UPLOAD_SPEED_SIZE__} >/dev/null 2>&1
	_webdav_cli upload "$ALIYUNDRIVE_DL_PREFIX/" "${__UPLOAD_SPEED_FILE__}" && __OK__=1
	__UPLOAD_SPEED_TIME__="$__DURATION__"
	_webdav_cli remove "$ALIYUNDRIVE_DL_PREFIX/$__UPLOAD_SPEED_NAME__" >/dev/null &
	[ "$__OK__" = "1" ] && {
		__UPLOAD_SPEED_KB__=$(echo "$__UPLOAD_SPEED_TIME__:$__UPLOAD_SPEED_SIZE__" | awk -F':' '{printf ("%.0f", $2*1024/$1); }')
		__UPLOAD_SPEED_MB__=$(echo "$__UPLOAD_SPEED_KB__"|awk '{printf ("%.2f", $0/1024); }')
		__UPLOAD_SPEED__="$__UPLOAD_SPEED_KB__"
		echo "$__UPLOAD_SPEED_MB__"
		return 0
	}
	return 1
}

_speedtest() {
	if _get_upload_speed "256"; then
		cat <<-EOF
		SIZE  : ${__UPLOAD_SPEED_SIZE__}MB
		TIME  : ${__UPLOAD_SPEED_TIME__}s
		SPEED : ${__UPLOAD_SPEED_MB__} MB/s
		EOF
	else
		echo "[ERR] Failed to test speed of Aliyundrive."
	fi
}

_get_aliyundrive_host() {
	ALIYUNDRIVE_HOST="127.0.0.1"
	# [ "$IS_MAIN" ] && ALIYUNDRIVE_HOST="127.0.0.1" || {
	# 	__N2N_LAN_IP__=$(get_interface_ip ${N2N_DEVICE_NAME})
	# 	[ -z "$__N2N_LAN_IP__" ] || {
	# 		__N2N_LAN_IP_PREFIX__=$(echo "$__N2N_LAN_IP__" | awk -F'.' '{print $1"."$2"."$3}')
	# 		__HOSTS__=$(nmap -p${ALIYUNDRIVE_PORT} --open ${__N2N_LAN_IP_PREFIX__}.0/24 -Pn -oG - | grep -i "Ports: *${ALIYUNDRIVE_PORT}" | grep -Eo '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')
	# 		echo "$__HOSTS__"
	# 		while read __HOST__
	# 		do
	# 			[ -z "$__HOST__" ] || {
	# 				curl -si -m 2 "http://${__HOST__}:${ALIYUNDRIVE_PORT}/${ALIYUNDRIVE_DL_PREFIX}" | head -n1 | grep -Eq '[23]0[1-9]' && ALIYUNDRIVE_HOST="$__HOST__"
	# 			}
	# 		done <<-EOF
	# 		$__HOSTS__
	# 		EOF
	# 		[ -z "$ALIYUNDRIVE_HOST" ] && ALIYUNDRIVE_HOST="127.0.0.1"
	# 	}
	# }
	echo "ALIYUNDRIVE_HOST=$ALIYUNDRIVE_HOST" >> "$GITHUB_ENV"
	echo "$ALIYUNDRIVE_HOST" && return 0
}

_reset_aliyundrive_refresh_token() {
	[ -z "$ALIYUNDRIVE_USERNAME" -o -z "$ALIYUNDRIVE_PASSWORD" ] && echo "[ERR] Please set ALIYUNDRIVE_USERNAME and ALIYUNDRIVE_PASSWORD first." && return 1
	[ -d "$CACHE_DIR" ] || mkdir -p "$CACHE_DIR"
	sudo apt-get install fonts-wqy-microhei fonts-wqy-zenhei xfonts-wqy
	cp $APPS_DIR/aliyundrive/get_refresh_token.js $CACHE_DIR/
	cd "$CACHE_DIR"
	[ -z "$(ls node_modules/puppeteer 2>/dev/null)" ] && npm i puppeteer
	ALIYUNDRIVE_USERNAME="${ALIYUNDRIVE_USERNAME}" ALIYUNDRIVE_PASSWORD="$ALIYUNDRIVE_PASSWORD" node get_refresh_token.js
	exit 1
	REFRESH_TOKEN=$(node get_refresh_token.js | grep '^REFRESH_TOKEN:' | awk -F':' '{print $2}')
	sh main.sh github secrets/git "${REFRESH_TOKEN}"
}

_install_aliyundrive_rust() {
	# https://github.com/messense/aliyundrive-webdav
	pip install aliyundrive-webdav
	ALIYUNDRIVE_BIN="aliyundrive-webdav"
	$ALIYUNDRIVE_BIN --version
	[ -z "$REFRESH_TOKEN" ] && echo "Please set Aliyun Token" && return 1
	tmux_api sessions/aliyundrive_rust/run "${ALIYUNDRIVE_BIN} --port ${ALIYUNDRIVE_PORT} --refresh-token ${REFRESH_TOKEN} --auto-index --no-trash"
	__RETRY__="10"
	__ALIYUNDRIVE_OK__="0"
	while true
	do
		[ "$__RETRY__" -le 0 ] && break
		echo "Checking Aliyun ($__RETRY__)"
		tmux_api sessions/aliyundrive_rust/capture | grep -iq 'refresh_token is not valid' && {
			echo "[ERR] Aliyundrive: REFRESH_TOKEN is not valid"
			_reset_aliyundrive_refresh_token
			__RETRY__="0"
		}
		curl -sI "http://${ALIYUNDRIVE_HOST}:${ALIYUNDRIVE_PORT}" | grep -q "200" && __ALIYUNDRIVE_OK__="1" && break
		__RETRY__=$((__RETRY__-1))
		sleep 1
	done
	[ "$__ALIYUNDRIVE_OK__" = "0" ] && echo "[ERR] Aliyundrive Webdav (Rust): Failed to start." && return 1
	_webdav_cli mkdir "$ALIYUNDRIVE_DL_PREFIX" &
	return 0
}

_install_davfs() {
	[ -z "$(which mount.davfs)" ] || return 0
	# Install Packages
	sudo apt-get install davfs2 inotify-tools
	# Config Davfs
	sudo mv /etc/davfs2/davfs2.conf /etc/davfs2/davfs2.conf.bak
	cat <<-EOF >/tmp/davfs2.conf
	if_match_bug    1
	use_locks       0
	cache_size      0
	delay_upload    0
	EOF
	sudo mv /tmp/davfs2.conf /etc/davfs2/davfs2.conf
	mkdir -p "$ALIYUNDRIVE_MNT"
	echo "" | awk '{print "";print ""}' | sudo mount -t davfs -o "uid=${UID},gid=${GID},file_mode=666,dir_mode=777" "$1" "${ALIYUNDRIVE_MNT}"
	[ -z "$(ls $ALIYUNDRIVE_MNT)" ] && echo "[ERR] Failed to mount Aliyundrive." && return 1
	return 0
}

_install_rclone() {
	# [ -z "$(which rclone)" ] && sudo cp "$RCLONE_BIN" /usr/bin && sudo chmod +x /usr/bin/$(echo "$RCLONE_BIN" | awk -F'/' '{print $NF}')
	# RCLONE_CONF_DIR="$USER_DIR/.config/rclone"
	# [ -d "$RCLONE_CONF_DIR" ] || mkdir -p "$RCLONE_CONF_DIR"
	cat <<-EOF > $RCLONE_APP_DIR/rclone.conf
	[${RCLONE_ALIYUNDRIVE_NAME}]
	type = webdav
	url = $1
	vendor = other
	EOF
	$RCLONE_BIN ls "${RCLONE_ALIYUNDRIVE_NAME}:/${ALIYUNDRIVE_DL_PREFIX}" >/dev/null 2>&1 || {
		echo "[ERR] Failed to mount Aliyundrive." && return 1
	}
	return 0
}

_mount() {
	_get_aliyundrive_host
	[ "$ALIYUNDRIVE_HOST" = "127.0.0.1" ] && {
		_install_aliyundrive_rust || return 1
	}
# 	[ -z "$ALIYUNDRIVE_URL" ] && ALIYUNDRIVE_URL="http://${ALIYUNDRIVE_HOST}:${ALIYUNDRIVE_PORT}"
	ALIYUNDRIVE_URL="http://${ALIYUNDRIVE_HOST}:${ALIYUNDRIVE_PORT}"
	_install_rclone "$ALIYUNDRIVE_URL" || return 1
	_install_davfs "$ALIYUNDRIVE_URL" || return 1
	return 0
}

[ -z "$1" ] || {
	ACTION="$1"
	shift
}

case "$ACTION" in
	"mount")
		_mount "$@" || exit 1
        	;;
	"upload"|"up")
		_upload "$@"
		;;
	"download"|"dl")
		_download "$@"
		;;
esac
