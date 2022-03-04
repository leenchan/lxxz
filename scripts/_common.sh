UID=$(id | grep -Eo 'uid=[0-9]+' | awk -F'=' '{print $2}')
GID=$(id | grep -Eo 'gid=[0-9]+' | awk -F'=' '{print $2}')

LOG_ENABLED="${LOG_ENABLED:-1}"
LOG_FILE="/tmp/log.txt"
REPO_NAME=$(echo "${GITHUB_REPOSITORY}" | awk -F'/' '{print $2}')
USER_DIR="/home/${USER}"
ROOT_DIR="${USER_DIR}/work/${REPO_NAME}"
REPO_DIR="${ROOT_DIR}/${REPO_NAME}"
APPS_DIR="${REPO_DIR}/apps"
CACHE_DIR="/tmp/${REPO_NAME}"
SCRIPTS_DIR="${REPO_DIR}/scripts"
N2N_COMMUNITY="${GITHUB_REPOSITORY}"
N2N_KEY="${SSH_PASSWD}"
# N2N_SERVER="supernode.ntop.org:7777"
# N2N_SERVER="n2n.lucktu.com:10090"
# N2N_SERVER="n2n.udpfile.com:10090"
[ -z "$N2N_SERVER" ] && N2N_SERVER="supernode.ntop.org:7777"
N2N_LAN_IP_PREFIX="172.16.2"
N2N_LAN_IP_MAIN="${N2N_LAN_IP_PREFIX}.100"
N2N_LAN_IP_HTTP_RANGE="110-119"
N2N_LAN_IP_BT_RANGE="120-149"
N2N_LAN_IP_ED2K_RANGE="150-159"
N2N_DEVICE_NAME="n2n"
ALIYUNDRIVE_PORT="18080"
ALIYUNDRIVE_MNT="${ROOT_DIR}/aliyun"
ALIYUNDRIVE_DL_PREFIX="Downloads"
ALIYUNDRIVE_DL_DIR="${ALIYUNDRIVE_MNT}/$ALIYUNDRIVE_DL_PREFIX"
ALIYUNDRIVE_RPOFILE_PREFIX=".github"
ALIYUNDRIVE_RPOFILE_DIR="${ALIYUNDRIVE_DL_DIR}/${ALIYUNDRIVE_RPOFILE_PREFIX}"
DEFAULT_DOWNLOAD_DIR="$ROOT_DIR/downloads"
SSH_PORT="82"

get_absolute_path() {
	_ABS_DIR_="$2"
	[ -z "$2" ] && _ABS_DIR_=$(cd "$(dirname "$0")";pwd)
	if echo "$1" | grep -q '^/'; then
		echo "$1"
	elif echo "$1" | grep -Eq '^\.\/' || [ "$1" = "." ]; then
		echo "$1" | sed -E "s|^\.|$_ABS_DIR_|g"
	elif echo "$1" | grep -Eq '^\.\.\/' || [ "$1" = ".." ]; then
		echo "$1" | sed -E "s|^\..|$(echo "$_ABS_DIR_" | awk '{gsub(/\/[^\/]+$/,"",$0); print $0}')|g"
	else
		echo "$_ABS_DIR_/$1"
	fi
}

get_now_time() {
	[ "$1" = "ms" ] && date "+%s.%2N" && return 0
	[ "$1" = "s" ] && date "+%s" && return 0
	date "+%d/%m/%Y %H:%M.%S"
	return 0
}

get_size() {
	__SIZE__=""
	[ -f "$1" ] && {
		__SIZE__=$(ls -al "$1" | awk '{print $5}')
	}
	[ -d "$1" ] && {
		__SIZE__=$(du -sc "$1" | awk 'END {print $1*1024}')
	}
	[ -z "$__SIZE__" ] && return 1
	case "$2" in
		"m"|"mb"|"M"|"MB")
			echo "$__SIZE__" | awk '{printf ("%.2f",$0/1024/1024)}';;
		"g"|"gb"|"G"|"GB")
			echo "$__SIZE__" | awk '{printf ("%.2f",$0/1024/1024/1024)}';;
		*)
			echo "$__SIZE__";;
	esac
	return 0
}

get_interface_ip() {
	ifconfig "${1}" | grep -Eo 'inet\s+[0-9+.]+' | awk '{print $NF}'
}

get_lan_ip() {
	__LAN_IP__=$(ifconfig edge0 | grep -Eo 'inet\s+[0-9.]+' | cut -d ' ' -f 2)
	[ -z "$__LAN_IP__" ] && return 1
	echo "$__LAN_IP__" && return 0
}

debug_log() {
	echo "[$(get_now_time)] $@"
	[ "$LOG_ENABLED" = "1" ] && echo "[$(get_now_time)] $@" >> "$LOG_FILE"
}

parse_url() {
	__URL__=$(echo "$1" | awk '{gsub(/^\s+/,"",$0); gsub(/\s+$/,"",$0); print $0}')
	__PROTOCOL__=""
	if echo "$__URL__" | grep -Eq '^https?://'; then
		__PROTOCOL__="http"
	elif echo "$__URL__" | grep -Eq '^ftp://'; then
		__PROTOCOL__="ftp"
	elif echo "$__URL__" | grep -Eq '^(magnet:|torrent:|bc://bt/)'; then
		__PROTOCOL__="bt"
	elif echo "$__URL__" | grep -Eq '^ed2k://'; then
		__PROTOCOL__="ed2k"
	fi
	return 0
}

is_json() {
	echo "$1" | jq '.' >/dev/null && return 0
	return 1
}

add_host() {
	# $1:domain    $2:ip
	[ -z "$1" -o -z "$2" ] && return 0
	__RECORD__="$2 $1"
	grep -Eq "$__RECORD__" /etc/hosts || sudo echo "$__RECORD__" >> /etc/hosts
}

tmux_api() {
	[ -z "$1" ] && return 1
	eval $(echo "$1" | awk -F'/' '{print "__TMUX_PATH_A__=\""$1"\"; __TMUX_PATH_B__=\""$2"\"; __TMUX_PATH_C__=\""$3"\"; __TMUX_PATH_D__=\""$4"\""}')
	shift
	case "$__TMUX_PATH_A__" in
		"sessions")
			__TMUX_SESSIONS_INFO__=$(tmux list-sessions)
			__TMUX_SESSIONS__=$(echo "$__TMUX_SESSIONS_INFO__" | awk -F':' '{print $1}')
			if [ -z "$__TMUX_PATH_B__" -a -z "$__TMUX_PATH_C__" ]; then
				echo "$__TMUX_SESSIONS__"
			else
				if [ "$__TMUX_PATH_B__" = "info" -a -z "$__TMUX_PATH_C__" ]; then
					__TMUX_PATH_D__="$__TMUX_PATH_C__"
					__TMUX_PATH_C__="info"
				elif [ "$__TMUX_PATH_B__" = "run" -a -z "$__TMUX_PATH_C__" ]; then
					__TMUX_PATH_D__="$__TMUX_PATH_C__"
					__TMUX_SESSIONS__=$$
					__TMUX_PATH_C__="run"
				elif echo "$__TMUX_PATH_B__" | grep -q '\+$'; then
					__TMUX_SESSION_PREFIX__=$(echo "$__TMUX_PATH_B__" | tr -d '+')
					__LAST_INDEX__=$(echo "$__TMUX_SESSIONS__" | grep -E "^${__TMUX_SESSION_PREFIX__}[0-9]+$" | tail -n1 | grep -Eo '[1-9][0-9]+')
					[ -z "$__LAST_INDEX__" ] && __LAST_INDEX__="1" || __LAST_INDEX__=$((__LAST_INDEX__+1))
					__TMUX_SESSIONS__="${__TMUX_SESSION_PREFIX__}${__LAST_INDEX__}"
				elif echo "$__TMUX_PATH_B__" | grep -q '\*$'; then
					__TMUX_SESSION_PREFIX__=$(echo "$__TMUX_PATH_B__" | tr -d '*')
					__TMUX_SESSIONS__=$(echo "$__TMUX_SESSIONS__" | grep -E "^${__TMUX_SESSION_PREFIX__}.*")
				else
					__TMUX_SESSIONS__="$__TMUX_PATH_B__"
				fi
				case "$__TMUX_PATH_C__" in
					"info")
						while read __TMUX_SESSION__
						do
							echo "$__TMUX_SESSIONS_INFO__" | awk -F':' -v NAME="$__TMUX_SESSION__" '($1==NAME){print $0}'
						done <<-EOF
						$__TMUX_SESSIONS__
						EOF
						;;
					"run")
						__TMUX_CMD__=$(echo "$@" | tr '\n' '; ' | awk '{gsub(/; *$/,"",$0); print $0}')
						[ -z "$__TMUX_SESSIONS__" ] && __TMUX_SESSIONS__=$$
						while read __TMUX_SESSION__
						do
							[ -z "$__TMUX_SESSION__" ] || {
								tmux has-session -t "$__TMUX_SESSION__" >/dev/null 2>&1 || tmux new-session -d -s "$__TMUX_SESSION__"
								tmux send-keys -t "$__TMUX_SESSION__" "$__TMUX_CMD__ " ENTER
							}
						done <<-EOF
						$__TMUX_SESSIONS__
						EOF
						[ -z "$__TMUX_PATH_D__" ] || {
							[ "$__TMUX_PATH_D__" -gt 0 ] && sleep $__TMUX_PATH_D__ && tmux_api "$__TMUX_PATH_A__/$__TMUX_PATH_B__/capture"
						}
						;;
					"stop")
						while read __TMUX_SESSION__
						do
							[ -z "$__TMUX_SESSION__" ] || {
								tmux has-session -t "$__TMUX_SESSION__" && tmux send-keys -t "$__TMUX_SESSION__" C-c && echo "$__TMUX_SESSION__"
							}
						done <<-EOF
						$__TMUX_SESSIONS__
						EOF
						;;
					"kill")
						while read __TMUX_SESSION__
						do
							[ -z "$__TMUX_SESSION__" ] || {
								tmux kill-session -t "$__TMUX_SESSION__" && echo "$__TMUX_SESSION__"
							}
						done <<-EOF
						$__TMUX_SESSIONS__
						EOF
						;;
					"clear")
						while read __TMUX_SESSION__
						do
							[ -z "$__TMUX_SESSION__" ] || {
								tmux clear-history -t "$__TMUX_SESSION__" && echo "$__TMUX_SESSION__"
							}
						done <<-EOF
						$__TMUX_SESSIONS__
						EOF
						;;
					"capture"|"cap")
						__TMUX_START_LINE__="-"
						__TMUX_END_LINE__="-"
						[ -z "$2" ] || {
							[ "$2" -gt 0 ] && __TMUX_START_LINE__="-$2"
						}
						while read __TMUX_SESSION__
						do
							[ -z "$__TMUX_SESSION__" ] || {
								tmux capture-pane -t "$__SESSION__" -p -S $__TMUX_START_LINE__ -E $__TMUX_END_LINE__ 2>/dev/null
							}
						done <<-EOF
						$__TMUX_SESSIONS__
						EOF
						;;
					*)
						[ -z "$__TMUX_PATH_C__" ] && {
							__TMUX_TOTAL__="0"
							while read __TMUX_SESSION__
							do
								tmux has-session -t "$__TMUX_SESSION__" >/dev/null 2>&1 && __TMUX_TOTAL__=$((__TMUX_TOTAL__+1))
							done <<-EOF
							$__TMUX_SESSIONS__
							EOF
							echo "$__TMUX_TOTAL__"
							[ "$__TMUX_TOTAL__" = "0" ] && return 1
						}
				esac
			fi
			;;
	esac
	return 0
}
