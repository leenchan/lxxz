
[ -d "/home/runner" ] && ROMS_ROOT_DIR="/home/runner/roms"
[ -z "$DOWNLOAD_DIR" ] || ROMS_ROOT_DIR="$DOWNLOAD_DIR"
[ -z "$RCLONE_ALIYUN_ROMS_DIR" ] && RCLONE_ALIYUN_ROMS_DIR="aliyun:/Game/roms"
INCLUDED_ALIYUN="true"

aliyun_upload_rom() {
	# $1:console   $2:game short name    $3:files
	cat<<-EOF
	CONSOLE:
	$1
	GAME NAME:
	$2
	FILES:
	$3	
	EOF
	__TMUX_SESSION__="rom-$2"
	[ -z "$3" ] && return 2
	tmux new-session -d -s "$__TMUX_SESSION__"
	__TMUX_CMD__=$(echo "$3" | awk '{gsub(/\$/,"\\$",$0);print $0}' | sed -E -e "s#($ROMS_ROOT_DIR)(.*)/([^/]+)#rclone copy -P '\1\2\/\3' '$RCLONE_ALIYUN_ROMS_DIR\2' \&\& rm -f '\1\2\/\3' \&\& #g")
	__TMUX_CMD__=$(echo "$__TMUX_CMD__" | tr -d '\n')"exit 0"
	echo "$__TMUX_CMD__"
	tmux send-keys -t "$__TMUX_SESSION__" "$__TMUX_CMD__ " ENTER
	return 0
}

aliyun_exist_rom() {
	# $1:console   $2:game short name    $3:info file
	rclone size "$RCLONE_ALIYUN_ROMS_DIR/$(echo "$3" | awk -F'/' '{print $(NF-2)"/"$(NF-1)"/"$NF}')" >/dev/null 2>&1 && return 0
	return 1
}
