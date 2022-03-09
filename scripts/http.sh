#!/bin/sh
CUR_DIR=$(cd "$(dirname "$0")";pwd)
CUR_FILE="${CUR_DIR}/$(echo "$0" | awk -F'/' '{print $NF}')"
. ${CUR_DIR}/_common.sh
ARIA2_ROOT="$ROOT_DIR/aria2"
ARIA2_CONF_FILE="$ARIA2_ROOT/aria2.conf"
ARIA2_API_PORT="6800"
ARIA2_DOWNLOAD_DIR="$DEFAULT_DOWNLOAD_DIR"
ARIA2_BIN="${APPS_DIR}/aria2/aria2c"

_aria2_api() {
	# https://aria2.github.io/manual/en/html/aria2c.html?highlight=enable%20rpc#rpc-interface
	__API_HOST__="${API_HOST:-127.0.0.1}"
	__API_URL__="http://${__API_HOST__}:${ARIA2_API_PORT}/jsonrpc"
	eval $(echo "$1" | awk -F'/' '{print "__PATH_A__=\""$1"\"; __PATH_B__=\""$2"\"; __PATH_C__=\""$3"\""}')
	case "$__PATH_A__" in
		"tasks")
			__PARAMS__='[0,1000,["gid", "totalLength", "completedLength", "uploadSpeed", "downloadSpeed", "connections", "numSeeders", "seeder", "status", "errorCode", "verifiedLength", "verifyIntegrityPending"]]'
			if [ "$__PATH_B__" = "downloading" ]; then
				__METHOD__="aria2.tellActive"
			elif [ "$__PATH_B__" = "waiting" ]; then
				__METHOD__="aria2.tellWaiting"
			elif [ "$__PATH_B__" = "stopped" ]; then
				__METHOD__="aria2.tellStopped"
			elif [ "$__PATH_B__" = "pause" ]; then
				__METHOD__="aria2.pauseAll"
			elif [ "$__PATH_B__" = "unpause" ]; then
				__METHOD__="aria2.unpauseAll"
			elif [ -z "$__PATH_B__" ]; then
				__METHOD__="aria2.getGlobalStat"
				__PARAMS__=""
			else
				__METHOD__="aria2.tellStatus"
				__PARAMS__="[\"$__PATH_B__\"]"
				case "$__PATH_C__" in
					"uris")
						__METHOD__="aria2.getUris"
						;;
					"files")
						__METHOD__="aria2.getFiles"
						;;
					"peers")
						__METHOD__="aria2.getPeers"
						;;
					"servers")
						__METHOD__="aria2.getServers"
						;;
					"pause")
						__METHOD__="aria2.pause"
						;;
					"unpause")
						__METHOD__="aria2.unpause"
						;;
					"remove")
						__METHOD__="aria2.remove"
						;;
				esac
			fi
			;;
		"add")
			__METHOD__="aria2.addUri"
			__PARAMS__="[[\"$2\"]]"
			# Torrent
			# __METHOD__="aria2.addTorrent"
			# torrent = base64.b64encode(open('file.torrent').read())
			# __PARAMS__="[torrent]"
			# __METHOD__="aria2.addMetalink"
			# metalink = base64.b64encode(open('file.meta4').read())
			# __PARAMS__="[metalink]"
			;;
		"version"|"v")
			__METHOD__="aria2.getVersion"
			;;
		"help")
			__METHOD__="system.listMethods"
			;;
	esac
	# __METHOD__="system.multicall"
	# __PARAMS__='[[{"method": aaa, "params": bbb}, ...]]'
	__JSON__=$(cat <<-EOF
	{
		"jsonrpc": "2.0",
		"id": "aliyun"
		$([ -z "$__METHOD__" ] || echo ",\"method\": \"$__METHOD__\"")
		$([ -z "$__PARAMS__" ] || echo ",\"params\": $__PARAMS__")
	}
	EOF
	)
	echo "$__JSON__" | jq '.' >/dev/null 2>&1 || {
		echo "$__JSON__"
		return 1
	}
	eval "curl -skL --data-raw '$__JSON__' '$__API_URL__'"
	__CODE__="$?"
	return $__CODE__
}

_install_aria2() {
	# Aria2 Conf: https://github.com/P3TERX/aria2.conf/raw/master/aria2.conf
	# Aria2 Bin: https://github.com/P3TERX/Aria2-Pro-Core/releases/download/1.36.0_2021.08.22/aria2-1.36.0-static-linux-amd64.tar.gz
	mkdir -p "$ARIA2_ROOT"
	[ -f "$ARIA2_ROOT/aria2.session" ] || touch "$ARIA2_ROOT/aria2.session"
	cp -f ./apps/aria2/aria2.conf "$ARIA2_CONF_FILE"
	sed -Ei -e "s|^dir=.*|dir=$ARIA2_DOWNLOAD_DIR|" \
		-e "s|^input\-file=.*|input-file=$ARIA2_ROOT/aria2.session|" \
		-e "s|^save\-session=.*|save-session=$ARIA2_ROOT/aria2.session|" \
		-e "s|^dht\-file\-path=.*|dht-file-path=$ARIA2_ROOT/dht.dat|" \
		-e "s|^dht\-file\-path6=.*|dht-file-path6=$ARIA2_ROOT/dht6.dat|" \
		-e "s|^on\-download\-stop=.*|on-download-stop=$CUR_FILE|" \
		-e "s|^on\-download\-complete=.*|on-download-complete=$CUR_FILE|" \
		-e "s|^enable\-rpc=.*|enable-rpc=true|" \
		-e "/^rpc\-secret=/d" \
		-e "s|^rpc\-listen\-port=.*|rpc-listen-port=$ARIA2_API_PORT|" \
		"$ARIA2_CONF_FILE"
	$ARIA2_BIN --conf-path=$ARIA2_CONF_FILE -D
	chmod +x "$CUR_FILE"
#  --ftp-user=USER              Set FTP user. This affects all URLs.
#  --ftp-passwd=PASSWD          Set FTP password. This affects all URLs.
#  --http-user=USER             Set HTTP user. This affects all URLs.
#  --http-passwd=PASSWD         Set HTTP password. This affects all URLs.
}

_install_youtube_dl() {
	sudo apt-get install ffmpeg
	# sudo pip install youtube_dl
	# YT-DLP: https://github.com/yt-dlp/yt-dlp/
	sudo pip install -U yt-dlp
}

_init() {
	_install_youtube_dl
	_install_aria2
}

_download_video() {
	[ -z "$1" ] && return 1
	yt-dlp --get-filename --output "%(id)s" "$1" > .tasks
	while read __ID__
	do
		[ -z "$__ID__" ] || {
			echo "[INFO] Downloading video: $__ID__"
			__DOWNLOADED_FILES__=$(yt-dlp --format "bestvideo[ext=mp4]+bestaudio[ext=m4a]/bestvideo+bestaudio/best" --merge-output-format mp4 --output "%(id)s.%(ext)s" --exec "echo" "$__ID__" || yt-dlp --format "best" --merge-output-format mp4 --output "%(id)s.%(ext)s" --exec "echo" "$__ID__")
			echo "$__DOWNLOADED_FILES__" | while read __FILE__
			do
				[ -f "$__FILE__" ] && {
					__NAME__=$(yt-dlp --get-filename --output "[%(channel)s]%(title)s" "$__ID__")
					__EXT__=$(echo "${__FILE__}" | awk -F'.' '{print $NF}')
					while true
					do
						[ -z "$__NAME__" ] && break
						mv "$__FILE__" "${__NAME__}.${__EXT__}" 2>/dev/null && __FILE__="${__NAME__}.${__EXT__}" && break
						__NAME__=$(echo "$__NAME__" | awk '{LEN=length($0); print substr($0,1,LEN-1)}')
					done
					sh $CUR_FILE upload --sub-dir YT --use rclone "$__FILE__"
				}
			done
		}
	done <<-EOF
	$(cat .tasks)
	EOF
	# youtube-dl -F 
	# youtube-dl -f 'best' --merge-output-format mp4 "$__URL__"
	# youtube-dl -f 'bestvideo+bestaudio/bestvideo+bestaudio' --merge-output-format mp4 "$__URL__"
	# youtube-dl -f 'bestvideo[ext=webm]+bestaudio[ext=m4a]/bestvideo+bestaudio' --merge-output-format mp4 "$__URL__"
	sh "$CUR_DIR/main.sh" end
}

_download_roms() {
	[ -z "$(which rclone)" ] && sudo ln -sf "$APPS_DIR/rclone/rclone" /usr/bin/rclone
	add_host "static.downloadroms.io" "104.221.221.153"
	WEBSITE=""
	ROM_CONSOLE=""
	ROM_SHORT_NAME=""
	ROM_PAGE=""
	ROM_URL=$(echo "$1" | awk '{gsub(/^https?:\/\/(www\.)?/,"",$0); gsub(/\/roms/,"",$0); gsub(/\.(html).*/,"",$0); print $0}')
	eval "$(echo "$ROM_URL" | awk -F'/' '{print "WEBSITE=\""$1"\"; ROM_CONSOLE=\""$2"\"; ROM_SHORT_NAME=\""$3"\"; ROM_PAGE=\""$4"\""}')"
	[ "$ROM_SHORT_NAME" = "page" ] && ROM_SHORT_NAME="$ROM_PAGE"
	echo "$ROM_CONSOLE" | grep -q '\-rom\-' && eval "$(echo "$ROM_CONSOLE" | awk -F'-rom-' '{print "ROM_CONSOLE=\""$1"\"; ROM_SHORT_NAME=\""$2"\"; ROM_PAGE=\"\""}')"
	cat <<-EOF
	URL: $1
	ROM_URL: $ROM_URL
	ROM_CONSOLE: $ROM_CONSOLE
	ROM_SHORT_NAME: $ROM_SHORT_NAME
	ROM_PAGE: $ROM_PAGE
	EOF
	[ -z "$WEBSITE" ] || {
		export WEBSITE="$WEBSITE"
		sh "$CUR_DIR/roms.sh" download "$ROM_CONSOLE$([ -z "$ROM_SHORT_NAME" ] || echo "/$ROM_SHORT_NAME")" || return 1
	}
	# tmux_api sessions/keep_alive/run "sh '$CUR_DIR/main.sh' keep_alive"
	# if echo "$1" | grep -Eq 'romsgames.net/'; then
	# 	__ROM_WEBSITE__="romsgames.net"
	# 	echo "$1" | grep -Eq 'romsgames.net/roms/[-a-zA-Z0-9]+' && __ROM_CONSOLE__=$(echo "$1" | grep -Eo 'romsgames.net/roms/[-a-zA-Z0-9]+' | awk -F'/' '{print $3}')
	# 	echo "$1" | grep -Eq 'page=[0-9]+' && __ROM_PAGE__=$(echo "$1" | grep -Eo 'page=[0-9]+' | awk -F'=' '{print $2}')
	# 	echo "$1" | grep -Eq 'sort=[a-z]+' && __ROM_SORT__=$(echo "$1" | grep -Eo 'page=[a-z]+' | awk -F'=' '{print $2}')
	# 	echo "$1" | grep -Eq 'letter=[a-z0-9]+' && __ROM_LETTER__=$(echo "$1" | grep -Eo 'letter=[a-z0-9]+' | awk -F'=' '{print $2}')
	# 	echo "$1" | grep -Eq 'romsgames.net/[-a-zA-Z0-9]+-rom-[-a-zA-Z0-9]+' && {
	# 		__ROM__=$(echo "$1" | grep -Eo 'romsgames.net/[-a-zA-Z0-9]+-rom-[-a-zA-Z0-9]+' | awk -F'/' '{print $2}')
	# 		eval $(echo "$__ROM__" | awk -F'-rom-' '{print "__ROM_CONSOLE__=\""$1"\";__ROM_NAME__=\""$2"\""}')
	# 	}
	# elif 
	# fi
	while true
	do
		sleep 5
		tmux ls | grep -Eq '^rom-' || {
			sh "$CUR_DIR/main.sh" end
			break
		}
	done
	return 0
}

_download_github() {
	__GITHUB_REPO__=$(echo "$1" | sed -E -e 's/\.git$//' -e 's/.*github\.com\///')
	__GITHUB_USERNAME__=$(echo "$__GITHUB_REPO__" | awk -F'/' '{print $1}')
	__GITHUB_REPO_NAME__=$(echo "$__GITHUB_REPO__" | awk -F'/' '{print $2}')
	git clone "$1" "$__GITHUB_REPO_NAME__" && {
		# git checkout "$__GITHUB_BRANCH__"
		# rm -rf "$__GITHUB_REPO_NAME__/.git"
		tar -zcf "[GITHUB][${__GITHUB_USERNAME__}]${__GITHUB_REPO_NAME__}.tar.gz" "$__GITHUB_REPO_NAME__"
		sh $CUR_FILE upload --use rclone "$__FILE__"
	}
	sh "$CUR_DIR/main.sh" end
}

_download() {
	parse_url "$1"
	[ -z "$__PROTOCOL__" ] && return 1
	case "$__PROTOCOL__" in
		"http")
			__HOST_URL__=$(echo "$__URL__" | grep -Eo 'https?://[^/]+')
			if echo "$__URL__" | grep -Eq 'https://(www\.)?github.com/[^\/]+/[^\/]+(\.git)?$'; then
				_download_github "$__URL__"
			elif echo "$__URL__" | grep -Eq 'https://www\.youtube\.com/watch\?v='; then
				_download_video "$__URL__"
			elif echo "$__URL__" | grep -Eq '(emulatorgames\.net|romsgames\.net|romspure\.cc)'; then
				_download_roms "$__URL__"
			else
				_aria2_api add "$@"
			fi
			;;
		"ftp")
			_aria2_api add "$@"
			;;
	esac
}

_upload() {
	# while true
	# do
	# 	[ "$#" = "0" ] && break
	# 	[ -d "$1" -o -f "$1" ] && {
	# 		__START__=$(get_now_time s)
	# 		mv "$1" $ALIYUNDRIVE_DL_DIR/
	# 		__END__=$(get_now_time s)
	# 		echo "mv \"$1\" $ALIYUNDRIVE_DL_DIR/ ($((__END__-__START__))s)" >> $LOG_FILE
	# 	}
	# 	shift
	# done
	sh ${CUR_DIR}/aliyundrive.sh upload "$@"
}

[ -z "$1" ] || {
	ACTION="$1" && shift
}

case "$ACTION" in
	"init")
		_init "$@"
		;;
	"download"|"dl")
		_download "$@"
		;;
	"upload"|"up")
		_upload "$@"
		;;
	"api")
		# API_HOST=172.16.2.xxx _aria2_api "$@"
		_aria2_api "$@"
		;;
	*)
		echo "$ACTION" | grep -Eq '^[0-9a-zA-Z]{16}$' && {
			[ "$1" = "0" -o "$1" = "1" ] && shift && _upload "$@"
		}
		;;
esac
