#!/bin/sh
CUR_DIR=$(cd "$(dirname "$0")";pwd)
[ -f ${CUR_DIR}/../../.env ] && . ${CUR_DIR}/../../.env
. ${CUR_DIR}/_common.sh
WAIT_FILE="${USER_DIR}/.wait"

_github_api() {
	__GITHUB_API_URL__="https://api.github.com/repos/${GITHUB_REPOSITORY}"
	__OPTIONS__="-H 'Authorization: token ${REPO_TOKEN}'"
	eval $(echo "$1" | awk -F'(/|:)' '{print "__PATH_A__=\""$1"\"; __PATH_B__=\""$2"\"; __PATH_C__=\""$3"\""}')
	__ACTION__="$2"
	__URL__=""
	if [ "$__PATH_A__" = "workflows" ]; then
		__URL__="${__GITHUB_API_URL__}/actions/workflows"
		[ -z "$__PATH_B__" ] || __URL__="${__URL__}/${__PATH_B__}"
	elif [ "$__PATH_B__" = "runs" ]; then
		__URL__="${__GITHUB_API_URL__}/actions/workflows/${__PATH_A__}/runs"
	elif [ "$__PATH_A__" = "runs" ]; then
		__URL__="${__GITHUB_API_URL__}/actions/runs/${__PATH_B__}"
		[ "$__ACTION__" = "delete" ] && __OPTIONS__="$__OPTIONS__ -X DELETE"
	elif [ "$__PATH_B__" = "jobs" ]; then
		__URL__="${__GITHUB_API_URL__}/actions/runs/${__PATH_A__}/jobs"
	elif [ "$__PATH_A__" = "secrets" ]; then
		__URL__="${__GITHUB_API_URL__}/actions/secrets"
		[ -z "$__PATH_B__" ] || {
			__URL__="${__URL__}/${__PATH_B__}"
			[ -z "$__ACTION__" ] || {
				_github_api "encrypt" "${__ACTION__}" || return 1
				__OPTIONS__="$__OPTIONS__ -X PUT -d '{\"encrypted_value\":\"${__ENCRYPT_VALUE__}\"}'"
			}
		}
	elif [ "$__PATH_A__" = "dispatches" ]; then
		__URL__="${__GITHUB_API_URL__}/dispatches"
		[ -z "$__ACTION__" ] || __OPTIONS__="$__OPTIONS__ -X POST -d '$__ACTION__'"
	elif [ "$__PATH_A__" = "encrypt" ]; then
		[ -z "$__ACTION__" ] || {
			__GITHUB_PUBLIC_KEY__=$(_github_api "secrets/public-key" | jq -r '.key')
			[ -z "$__GITHUB_PUBLIC_KEY__" ] && return 1
			[ -d "$CACHE_DIR" ] || mkdir -p "$CACHE_DIR"
			cat <<-EOF > $CACHE_DIR/encrypt.js
			const sodium = require('tweetsodium');
			const key = "${__GITHUB_PUBLIC_KEY__}";
			const value = "${__ACTION__}";
			const messageBytes = Buffer.from(value);
			const keyBytes = Buffer.from(key, 'base64');
			const encryptedBytes = sodium.seal(messageBytes, keyBytes);
			const encrypted = Buffer.from(encryptedBytes).toString('base64');
			console.log("ENCRYPT_VALUE:"+encrypted);
			EOF
			cd $CACHE_DIR
			[ -z "$(ls node_modules/tweetsodium 2>/dev/null)" ] && npm i tweetsodium >/dev/null 2>/dev/null
			__ENCRYPT_VALUE__=$(node encrypt.js 2>/dev/null | grep -E '^ENCRYPT_VALUE:' | awk -F':' '{print $2}')
			cd $CUR_DIR
			[ -z "$__ENCRYPT_VALUE__" ] && return 1
			echo "$__ENCRYPT_VALUE__"
			return 0
		}
	fi
	[ -z "$__URL__" ] && return 1
# 	echo "curl -skL $__OPTIONS__  $__URL__"
	eval "curl -skL $__OPTIONS__  $__URL__"
	__CODE__=$?
	[ "$LOG_ENABLED" = "1" ] && echo "curl -skL $__OPTIONS__  $__URL__" >> $LOG_FILE
	return $__CODE__
}

_get_lan_ip() {
	[ -z "$LAN_IP" ] || {
		echo "$LAN_IP" && return 0
	}
	__WORKFLOW_NAME__="${GITHUB_WORKFLOW:-Main}"
	__JOB_NAME__="${GITHUB_JOB:-main}"
	__WORKFLOWS__=$(_github_api "workflows")
	[ -z "$__WORKFLOWS__" ] && return 0
	__WORKFLOW_ID__=$(echo "$__WORKFLOWS__" | jq -r ".workflows[]? | select(.name == \"$__WORKFLOW_NAME__\")? | .id?")
	__RUNS_IN_PROGRESS__=$(_github_api "$__WORKFLOW_ID__/runs" | jq '.workflow_runs[]? | select( .status == "in_progress" ) | .id')
	__IS_JOIN_LAN__="0"
	[ -z "$__RUNS_IN_PROGRESS__" ] && return 1
	while read __RUN_ID__
	do
		[ "$__RUN_ID__" = "$GITHUB_RUN_ID" ] || {
			# echo "RUN_ID: $__RUN_ID__"
			__STEPS__=$(_github_api "${__RUN_ID__}/jobs" | jq ".jobs[] | select(.name == \"${__JOB_NAME__}\") | .steps")
			[ -z "$__STEPS__" ] || {
				__STEP__=$(echo "$__STEPS__" | jq '.[] | select(.name == "Join LAN Network")')
				[ -z "$__STEP__" ] || {
					# queued / in_progress / completed
					__STEP_STATUS__=$(echo "$__STEP__" | jq -r '.status')
					# null / success / skipped
					__STEP_RESULT__=$(echo "$__STEP__" | jq -r '.conclusion')
					# echo "- result: $__STEP_RESULT__"
					[ "$__STEP_RESULT__" = "success" ] && __IS_JOIN_LAN__="1" && break
					# [ "$__STEP_STATUS__" = "queued" -o "$__STEP_STATUS__" = "in_progress" ] && {
					# 	sleep 60
					# }
				}
			}
		}
	done <<-EOF
	$__RUNS_IN_PROGRESS__
	EOF
	[ "$__IS_JOIN_LAN__" = "1" ] && return 1
	_n2n_get_ip || return 1
	echo "$LAN_IP"
	sudo echo "LAN_IP=$LAN_IP" >> "$GITHUB_ENV"
	return 1
}

_get_main_info() {
	__WORKFLOW_NAME__="${GITHUB_WORKFLOW:-Main}"
	__JOB_NAME__="${GITHUB_JOB:-main}"
	__WORKFLOWS__=$(_github_api "workflows")
	[ -z "$__WORKFLOWS__" ] && return 0
	__WORKFLOW_ID__=$(echo "$__WORKFLOWS__" | jq -r ".workflows[]? | select(.name == \"$__WORKFLOW_NAME__\")? | .id?")
	__RUNS_IN_PROGRESS__=$(_github_api "$__WORKFLOW_ID__/runs" | jq '.workflow_runs[]? | select( .status == "in_progress" ) | .id')
	__MAIN_IS_RUNNING__="false"
	__MAIN_RUN_SECONDS__="null"
	__MAIN_RUN_ID__="null"
	[ -z "$__RUNS_IN_PROGRESS__" ] && return 1
	while read __RUN_ID__
	do
		[ "$__RUN_ID__" = "$GITHUB_RUN_ID" ] || {
			# echo "RUN_ID: $__RUN_ID__"
			__STEPS__=$(_github_api "${__RUN_ID__}/jobs" | jq ".jobs[] | select(.name == \"${__JOB_NAME__}\") | .steps")
			[ -z "$__STEPS__" ] || {
				__RUN_STARTED_AT__=$(echo "$__STEPS__" | jq -r '.[0].started_at | sub("T";" ")')
				__RUN_STARTED_AT_SECONDS__=$(date -d "$__RUN_STARTED_AT__" +%s)
				__NOW_SECONDS__=$(date +%s)
				__MAIN_RUN_SECONDS__=$((__NOW_SECONDS__-__RUN_STARTED_AT_SECONDS__))
				__STEP__=$(echo "$__STEPS__" | jq '.[] | select(.name == "Join LAN Network")')
				[ -z "$__STEP__" ] || {
					# queued / in_progress / completed
					__STEP_STATUS__=$(echo "$__STEP__" | jq -r '.status')
					# null / success / skipped
					__STEP_RESULT__=$(echo "$__STEP__" | jq -r '.conclusion')
					# echo "- result: $__STEP_RESULT__"
					[ "$__STEP_RESULT__" = "success" ] && __MAIN_IS_RUNNING__="true" && __MAIN_RUN_ID__="$__RUN_ID__" && break
					# [ "$__STEP_STATUS__" = "queued" -o "$__STEP_STATUS__" = "in_progress" ] && {
					# 	sleep 60
					# }
				}
			}
		}
	done <<-EOF
	$__RUNS_IN_PROGRESS__
	EOF
	cat <<-EOF
	{
		"running": $__MAIN_IS_RUNNING__,
		"run_id": $__RUN_ID__,
		"run_time": $__MAIN_RUN_SECONDS__
	}
	EOF
	[ "$__MAIN_IS_RUNNING__" = "true" ] || return 1
	return 0
}

_delete_runs() {
	if [ "$1" = "all" ]; then
		__WORKFLOW_IDS__=$(_github_api "workflows" | jq -r '.workflows[]? | .id?')
		while read __WORKFLOW_ID__
		do
			[ -z "$__WORKFLOW_ID__" ] || {
				__RUN_IDS__=$(cat <<-EOF
				$__RUN_IDS__
				$(_github_api "$__WORKFLOW_ID__/runs" | jq '.workflow_runs[]? | select(.status == "completed") | .id')
				EOF
				)
			}
		done <<-EOF
		$__WORKFLOW_IDS__
		EOF
	else
		__RUN_IDS__=$(echo "$1" | tr ',' '\n')
	fi
	[ -z "$__RUN_IDS__" ] && return 1
	while read __RUN_ID__
	do
		[ -z "$__RUN_ID__" ] || {
			_github_api "runs/${__RUN_ID__}" delete
			echo "[DEL] RUN: ${__RUN_ID__} (CODE: $?)"
		}
	done <<-EOF
	$__RUN_IDS__
	EOF
}

_get_url_type() {
	parse_url "$1"
	echo "$__PROTOCOL__"
}

_zerotier_install() {
	sudo curl -s https://install.zerotier.com | sudo bash
	return $?
}

_zerotier_connect() {
	[ -z "$(which zerotier-cli)" ] && {
		_zerotier_install || return 1
	}
	[ -z "$1" ] || ZEROTIER_NETWORK_ID="$1"
	[ -z "$ZEROTIER_NETWORK_ID" ] && return 1
	sudo zerotier-cli join $ZEROTIER_NETWORK_ID || return 1
	__RETRY__=0
	while true
	do
		[ "$__RETRY__" -gt 10 ] && break
		echo "[INFO] Try to get Zerotier IP ($__RETRY__)"
		__ZEROTIER_LAN_IP__=$(sudo zerotier-cli listnetworks | grep $ZEROTIER_NETWORK_ID | grep -Eo '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')
		[ -z "$__ZEROTIER_LAN_IP__" ] || break
		__RETRY__=$((__RETRY__+1)) && sleep 1
	done
	echo "Zerotier LAN IP: $__ZEROTIER_LAN_IP__"
	return 0
}

_n2n_install() {
	# https://github.com/lucktu/n2n
	rm -rf /tmp/n2n
	mkdir -p /tmp/n2n
	git clone https://github.com/ntop/n2n.git /tmp/n2n
	cd /tmp/n2n
	./autogen.sh
	./configure
	make
	sudo make install || return 1
	return 0
}

_n2n_get_ip() {
	case "$EVENT_TYPE" in
		"main"|"Main"|"MAIN")
			LAN_IP="$N2N_LAN_IP_MAIN"
			;;
	esac
	case "$DOWNLOAD_TYPE" in
		"http"|"ftp")
			LAN_IP="${N2N_LAN_IP_PREFIX}.$(echo "$N2N_LAN_IP_HTTP_RANGE" | awk -F'-' '{print $1}')"
			;;
		"bt")
			LAN_IP="${N2N_LAN_IP_PREFIX}.$(echo "$N2N_LAN_IP_BT_RANGE" | awk -F'-' '{print $1}')"
			;;
	esac
	[ -z "$LAN_IP" ] && return 1
	return 0
}

_n2n_connect() {
	sudo chmod -R 777 "${APPS_DIR}"
	[ -z "$(which nmap)" ] && sudo apt-get install nmap >/dev/null 2>&1
	# [ -z "$(which edge)" ] && {
	# 	_n2n_install || return 1
	# }
	# [ -z "$LAN_IP" ] && _n2n_get_ip
	# [ -z "$LAN_IP" ] && return 1
	__N2N_OPTION__=""
	[ "$IS_MAIN" = "true" ] && __N2N_OPTION__=" -I 'main'"
	tmux_api sessions/n2n/run "sudo ${APPS_DIR}/n2n/edge $([ -z "$N2N_LAN_IP" ] || echo "-a $N2N_LAN_IP ")-d ${N2N_DEVICE_NAME} -c '${N2N_COMMUNITY}' -k '${N2N_KEY}' -f -l '${N2N_SERVER}'${__N2N_OPTION__}"
	__WAIT__="10"
	while true
	do
		[ "$__WAIT__" -le 0 ] && break
		__TMUX_HISTORY__=$(tmux_api sessions/n2n/capture)
		N2N_LAN_IP=$(echo "$__TMUX_HISTORY__" | grep -Eio 'created local tap device IP: [0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | awk '{print $NF}')
		[ -z "$N2N_LAN_IP" ] || break
		sleep 1
		__WAIT__=$((__WAIT__-1))
	done
	[ -z "$N2N_LAN_IP" ] && echo "$__TMUX_HISTORY__" && return 1
	echo "$N2N_LAN_IP"
	return 0
}

_ssh_install() {
	sudo apt-get install -y dropbear
	return 0
}

_ssh_run() {
	cat <<-EOF | sudo passwd ${USER}
	${SSH_PASSWD}
	${SSH_PASSWD}
	EOF
	sudo cp apps/ssh/* /etc/ssh/
}

_dispatch_action() {
	case "$1" in
		"Download"|"Main")	
			__PAYLOAD__=$(cat <<-EOF
			{
				"event_type": "$1",
				"client_payload": {
					"download_url": "$2"
					$([ -z "$3" ] || echo ",$3")
				}
			}
			EOF
			)
			;;
	esac
	is_json "$__PAYLOAD__" || echo "$__PAYLOAD__"
	# __PAYLOAD__=$(echo "$__PAYLOAD__" | tr -d '\n' | sed -E 's/"/\\"/g')
	__PAYLOAD__=$(echo "$__PAYLOAD__" | tr -d '\n')
	_github_api "dispatches" "${__PAYLOAD__}"
}

_download_btbtt() {
	__HOST_URL__=$(echo "$1" | grep -Eo 'https?://[^/]+')
	__ATTACH_URL__=""
	if echo "$1" | grep -Eq 'attach\-dialog\-fid\-[0-9]+\-aid\-[0-9]+.htm$'; then
		__ATTACH_URL__="$__HOST_URL__/$(curl -skL "$1" | grep -Eo 'href="[^"]*attach\-download[^"]+"' | awk '{gsub(/(^href="|"$)/,"",$0); print $0}')"
	elif echo "$1" | grep -Eq 'attach\-download\-fid\-[0-9]+\-aid\-[0-9]+.htm$'; then
		__ATTACH_URL__="$1"
	fi
	[ -z "$__ATTACH_URL__" ] && return 1
	__ATTACH_FILE_NAME__="$(curl -i $__ATTACH_URL__| grep -Eo 'filename="[^"]+"' | awk '{gsub(/(^filename="|"$)/,"",$0); print $0}')"
	__ATTACH_FILE__="/tmp/$__ATTACH_FILE_NAME__"
	# curl -skL -o "$__ATTACH_FILE__" "$__ATTACH_URL__" && file "$__ATTACH_FILE__" | grep -iq "torrent" && echo "torrent://$(base64 "$__ATTACH_FILE__" | tr -d '\n')" && return 0
	curl -skL -o "$__ATTACH_FILE__" "$__ATTACH_URL__" && file "$__ATTACH_FILE__" | grep -iq "torrent" && echo "torrent://$__ATTACH_URL__" && return 0
	echo "$1"
	return 1
}

_download_http() {
	__HOST_URL__=$(echo "$1" | grep -Eo 'https?://[^/]+')
	if echo "$__HOST_URL__" | grep -q 'btbtt.com$'; then
		_download_btbtt "$1"
	else
		echo "$1"
	fi
}

_download() {
	parse_url "$1"
	[ -z "$__PROTOCOL__" ] && return 1
	case "$__PROTOCOL__" in
		"http")
			__URL__=$(_download_http "$__URL__")
			;;
	esac
	_dispatch_action "Download" "$__URL__" "\"caller_run_id\": \"$GITHUB_RUN_ID\""
}

_restore() {
	echo "Restoring files from previous run..."
	return 0
}

_keep_alive() {
	__ACTION_LIMIT_SECONDS__=$((60*60*6))
	__KEEP_ALIVE_FIRE_SECONDS__=$((__ACTION_LIMIT_SECONDS__-60*5))
	while true
	do
		__UPTIME_SECONDS__=$(awk '{gsub(/\..*/,"",$1);print $1}' /proc/uptime)
		[ $__UPTIME_SECONDS__ -gt $__KEEP_ALIVE_FIRE_SECONDS__ ] && {
			[ -z "$1" ] || eval "$1"
			_dispatch_action "Download" "$DOWNLOAD_URL" "$(cat <<-EOF
			"caller_run_id": "$GITHUB_RUN_ID",
			"lan_ip": "$LAN_IP",
			"rsync_server": "rsync://$LAN_IP:9999"
			EOF
			)"
			break
		}
		sleep 5
	done
}

_wait() {
	echo $$ > "$WAIT_FILE"
	while [ -f "$WAIT_FILE" ]
	do
		sleep 1
		# inotifywait -qqt 2 -e create -e moved_to "$(dirname $WAIT_FILE)"
	done
	return 0
}

_end() {
	echo "DONE=true" >> "$GITHUB_ENV"
	[ -f "$WAIT_FILE" ] && rm -f "$WAIT_FILE"
	return 0
}

_start_main() {
	_dispatch_action "Main" "$1"
}

_init_nfs() {
	sudo apt-get update && sudo apt-get install nfs-kernel-server
	sudo echo "/ ${N2N_LAN_IP_PREFIX}.0/24(rw,sync,no_subtree_check)" > /etc/exports
	sudo exportfs -ra
}

_init_clean() {
	sudo timedatectl set-timezone "$TZ"
	sudo -E apt-get -qq update
	# sudo -E apt-get -qq install build-essential asciidoc binutils bzip2 gawk gettext git libncurses5-dev libz-dev patch python3 python2.7 unzip zlib1g-dev lib32gcc1 libc6-dev-i386 subversion flex uglifyjs gcc-multilib g++-multilib p7zip p7zip-full msmtp libssl-dev texinfo libglib2.0-dev xmlto qemu-utils upx-ucl libelf-dev autoconf automake libtool autopoint device-tree-compiler ccache xsltproc rename antlr3 gperf wget curl swig rsync
	sudo -E apt-get -qq purge azure-cli ghc* zulu* hhvm llvm* firefox powershell openjdk* dotnet* google* mysql* php* android*
	sudo rm -rf /etc/apt/sources.list.d/* /usr/share/dotnet /usr/local/lib/android /opt/ghc
	sudo -E apt-get -qq autoremove --purge
	sudo -E apt-get -qq clean
	sudo rm -rf /usr/share/rust /usr/share/miniconda /usr/share/swift /opt/hostedtoolcache/
	# sudo rm -rf /usr/share/dotnet /etc/mysql /etc/php /usr/local/lib/android
}

_init() {
	echo "[INFO] Setting up NFS ..."
	_init_nfs >/dev/null 2>&1
	echo "[INFO] Removing unused packages and files for More Disk Space ..."
	_init_clean >/dev/null 2>&1
}

[ -z "$1" ] || {
	ACTION="$1"
	shift
}

case "$ACTION" in
	"init")
		_init
		;;
	"is_main")
		[ "$(_get_main_info | jq '.running')" = "true" ] && echo "false" || echo "true"
		;;
	"get_lan_ip")
		_get_lan_ip || exit 0
		;;
	"get_url_type")
		_get_url_type "$@"
		;;
	"join_lan")
		_n2n_connect
		# _zerotier_connect || true
		;;
	"ssh")
		_ssh_run
		env > ~/.env
		sudo ps aux > ~/.ps
		sudo netstat -tpan > ~/.tcp
		;;
	"download"|"dl")
		_download "$@"
		;;
	"start")
		_start_main "$@"
		;;
	"keep_alive")
		_keep_alive "$@"
		;;
	"restore")
		_restore "$@"
		;;
	"wait")
		_wait
		;;
	"end")
		_end
		;;
	"clean")
		_delete_runs "$@"
		;;
	"github")
		_github_api "$@"
		;;
	"tmux")
		tmux_api "$@"
		;;
	"demo")
		_get_main_info
		;;
esac


