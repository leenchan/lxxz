#!/bin/sh
CUR_DIR=$(cd "$(dirname "$0" 2>/dev/null)";pwd)
ROMS_ROOT_DIR="$CUR_DIR"
CACHE_DIR="$CUR_DIR/.cache"

ROMS_EXT="z64 n64 bin cue"
ARCHIVE_EXT="zip rar 7z zip"
THUMB_EXT="webp jpg jpeg png gif mp4 flv"
THUBM_DIR_NAME="thumbnail"
NEED_EXTRACT="nintendo-64"
INFO_DIR_NAME="info"
DOWNLOAD_THREADS="16"

[ -f "$CUR_DIR/roms_aliyun.sh" ] && . $CUR_DIR/roms_aliyun.sh >/dev/null 2>&1

_init_() {
	# https://www.romstation.fr/games/
	WEBSITE_LIST=$(cat <<-EOF
	romsgames.net:romsgames:1
	emulatorgames.net:emulatorgames:2
	romspure.cc:romspure:3
	romsfun.com:romsfun:4
	EOF
	)
	_ROM_EXT_REGEX_=$(echo "$ROMS_EXT $ARCHIVE_EXT" | tr ' ' '|')
	_ARCHIVE_EXT_REGEX_=$(echo "$ARCHIVE_EXT" | tr ' ' '|')
	_THUMB_EXT_REGEX_=$(echo "$THUMB_EXT" | tr ' ' '|')
	_ROM_NEED_EXTRACT_REGEX_=$(echo "$NEED_EXTRACT" | tr ' ' '|')
	case "$WEBSITE" in
		"romsgames"|"1")
			WEBSITE="romsgames.net";;
		"emulatorgames"|"2")
			WEBSITE="emulatorgames.net";;
		"romspure"|"3")
			WEBSITE="romspure.cc";;
		"romsfun"|"4")
			WEBSITE="romsfun.com";;
		*)
			WEBSITE="romsfun.com";;
	esac
}

extract_file() {
	return 1
	# sudo apt-get install p7zip-full
	[ -f "$1" ] || return 1
	__EXTRACT_TO__="$2"
	[ -z "$__EXTRACT_TO__" ] && __EXTRACT_TO__="$(echo "$1" | awk '{gsub(/[^\/]+$/,"",$0); print $0}')"
	echo "$1" | grep -Eq "\\.($_ARCHIVE_EXT_REGEX_)$" && {
		echo "[INFO] Trying to deccompress ..."
		[ "x$(which 7z)" != "x" ] && 7z e "$1" -aoa -o"$__EXTRACT_TO__" && return 0
		[ "x$(which bsdtar)" != "x" ] && bsdtar -xf "$1" -C "$__EXTRACT_TO__" && return 0
		# unzip -d "$(echo "$1" | awk '{gsub(/[^\/]+$/,"",$0); print $0}')" "$1" && rm -f "$1" && return 0
	}
	echo "[ERR] Failed to deccompress"
	return 1
}

fetch_html() {
	[ -z "$1" ] && return 1
	__FETCH_URL__="$1"
	__FETCH_OPTIONS__=""
	__FETCH_DATA__=""
	__FETCH_ONELINE__="0"
	shift
	while [ "$#" -gt 0 ]
	do
	[ "$1" = "--oneline" ] && __FETCH_ONELINE__="1"
	echo "$1" | grep -Eq '^--header=' && __FETCH_OPTIONS__="$__FETCH_OPTIONS__ -H $(echo "$1" | awk '{gsub(/^--header=/,"",$0); print $0}')"
	shift
	done
	__FETCH_DATA__=$(curl -skL --max-time 5 --retry 3 --retry-delay 1 "$__FETCH_URL__")
	# __RETRY__="3"
	# while [ $__RETRY__ -gt 0 ]
	# do
	# 	__FETCH_DATA__=$(curl -skL --max-time 5 --retry 3 --retry-delay 1 "$1")
	# 	[ -z "$__FETCH_DATA__" ] || break
	# 	__RETRY__=$((__RETRY__-1))
	# done
	[ -z "$__FETCH_DATA__" ] && return 1
	[ "$__FETCH_ONELINE__" = "1" ] && __FETCH_DATA__=$(echo "$__FETCH_DATA__" | tr -d '\n\r')
	echo "$__FETCH_DATA__"
	return 0
}

dl_file() {
	[ -z "$1" ] && return 1
	_DL_URL_="$1" && shift
	_DL_OPTIONS_=""
	_DL_BIN_="wget"
	[ -z "$(which aria2c)" ] || _DL_BIN_="aria2c"
	while [ $# -gt 0 ]
	do
		if echo "$1" | grep -Eq '^--output='; then
			_DL_OUTPUT_FILE_=$(echo "$1" | awk '{gsub(/^--output=/,"",$0); gsub(/"/,"",$0); print $0}')
			_DL_FILE_NAME_=$(echo "$_DL_OUTPUT_FILE_" | awk -F'/' '{print $NF}')
			[ -z "$_DL_FILE_NAME_" ] && _DL_FILE_DIR_="$_DL_OUTPUT_FILE_" || _DL_FILE_DIR_=$(echo "$_DL_OUTPUT_FILE_" | sed -E 's/[^\/]+$//')
			[ -z "$_DL_FILE_NAME_" ] && _DL_FILE_NAME_=$(echo "$_DL_URL_" | awk -F'/' '{print $1}')
			[ -z "$_DL_FILE_NAME_" ] || _DL_FILE_NAME_=$(echo "$_DL_FILE_NAME_" | awk '{gsub(/\$/,"\\$",$0);print $0}')
			[ -d "$_DL_FILE_DIR_" ] || mkdir -p "$_DL_FILE_DIR_"
			if [ -z "$(which aria2c)" ]; then
				_DL_OPTIONS_="$_DL_OPTIONS_ -O \"${_DL_FILE_DIR_}${_DL_FILE_NAME_}\""
			else
				_DL_OPTIONS_="-d \"$_DL_FILE_DIR_\" -o \"$_DL_FILE_NAME_\""
			fi
		elif echo "$1" | grep -Eq '^(--header=)'; then
			_DL_OPTIONS_="$_DL_OPTIONS_ $1"
		fi
		shift
	done
	[ -z "$(which aria2c)" ] || _DL_OPTIONS_="$_DL_OPTIONS_ -x $DOWNLOAD_THREADS -s $DOWNLOAD_THREADS"
	# echo "$_DL_BIN_ $_DL_OPTIONS_ \"$_DL_URL_\""
	eval "$_DL_BIN_ $_DL_OPTIONS_ \"$_DL_URL_\"" && return 0
	return 1
}

convert_size() {
	[ "$1" -ge 0 ] || return 1
	echo "$1" | awk '{
		if ($1 >= 1024*1024*1024) {
			UNIT="GB"; SIZE=($1/1024/1024/1024)
		} else if ($1 >= 1024*1024) {
			UNIT="MB"; SIZE=($1/1024/1024)
		} else if ($1 >= 1024) {
			UNIT="KB"; SIZE=($1/1024)
		} else {
			UNIT="Byte"; SIZE=($1/1024)
		}
		gsub(/\..*/,"",SIZE); print SIZE" "UNIT
	}'
	return 0
}

get_file_size() {
	__SIZE__=$(ls -al "$1" 2>/dev/null | awk '{print $5}')
	[ "$__SIZE__" -ge 0 ] && echo "$__SIZE__" && return 0
	return 1
}

gen_index() {
	# $1: type
	__CONSOLE__=$(echo "$1" | awk -F'/' '{print $1}')
	[ -z "$__CONSOLE__" ] && return 1
	rom_init "$__CONSOLE__"
	[ -d "$_ROM_CONSOLE_DIR_" ] || {
		echo "[ERR] Could not find dir: $__CONSOLE__" && return 1
	}
	_INDEX_FILE_="$CUR_DIR/${__CONSOLE__}.html"
	# _ROMS_TITLE_=$(grep -nr '"name":' "$CUR_DIR/$1/$INFO_DIR_NAME" | sed -E 's#(.*[^/]+\.txt).*"([^"]+)".*#\1::::\2#g')
	_ROMS_HTML_=$(
		while read __ROM_INFO_FILE__
		do
			__ROM_INFO_JSON__=$(cat "$__ROM_INFO_FILE__")
			__ROM_TITLE__=$(echo "$__ROM_INFO_JSON__" | grep -E '"title":' | awk '{gsub(/^.*"title":[^"]*"/,"",$0); gsub(/",?$/,"",$0); print $0}')
			__ROM_INFO_FILE_PATH__="$_ROM_INFO_PATH_/$(echo "$__ROM_INFO_FILE__" | awk -F'/' '{print $NF}')"
			__ROM_COVER__=""
			for _THUMB_EXT_ in $THUMB_EXT; do
				[ -f "$_ROM_THUMBNAIL_DIR_/${__ROM_TITLE__}.${_THUMB_EXT_}" ] && __ROM_COVER__="$1/${THUBM_DIR_NAME}/${__ROM_TITLE__}.${_THUMB_EXT_}"
			done
			[ -z "$__ROM_COVER__" ] || __ROM_COVER__=$(echo "$__ROM_COVER__" | awk '{gsub(/#/,"%23",$0); print $0}')
			
			cat <<-EOF
			<li class="rom"><div data-info="$__ROM_INFO_FILE_PATH__"><div class="cover"><img src="$__ROM_COVER__" />$_ACTION_HTML_</div><div><h3>$__ROM_TITLE__</h3></div></div></li>
			EOF
		done <<-EOF
		$(grep -nr '"short_name":' "$_ROM_INFO_DIR_" | sed -E 's/:[0-9]+:.*//g')
		EOF
	)
	cat <<-EOF > "$_INDEX_FILE_"
	<!doctype html>
	<html lang="en">
	<head>
	<meta charset="utf-8">
	<meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">
	<style>
	* {color: #555; font-size: 14px; font-family: -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",Arial,"Noto Sans",sans-serif,"Apple Color Emoji","Segoe UI Emoji","Segoe UI Symbol","Noto Color Emoji";}
	*, ::after, ::before {box-sizing: border-box;}
	body {margin: 0; padding: 0; background-color: rgb(234, 236, 238);}
	a {text-decoration: none; color: #000;}
	table {border-collapse: collapse;}
	ul {display: flex; flex-wrap: wrap; margin: 0; padding: 0; list-style: none; justify-content: center;}
	li.rom {width: 240px; padding: 12px; box-sizing: border-box;}
	li.rom>div {background: #fff; box-shadow: 0 0.125rem 0.25rem rgb(0 0 0 / 8%); border-radius: 12px; overflow: hidden; display: block; position: relative; cursor: pointer;}
	li.rom>div:hover {box-shadow: 0 0.5rem 0.5rem rgb(0 0 0 / 15%);}
	h3 {font-size: 14px; font-weight: 500; margin: 0; padding: 12px 8px; text-align: center;}
	.hidden {display: none;}
	.align-right {text-align: right;}
	.icon {display: inline-block; width: 32px; height: 32px; background-color: rgba(0,0,0,0.5); background-size: 75%; background-position: center; background-repeat: no-repeat; content: ""; border-radius: 100px; }
	.icon-folder {background-image: url('data:image/svg+xml;base64,PD94bWwgdmVyc2lvbj0iMS4wIiA/PjxzdmcgZmlsbD0ibm9uZSIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0IiB3aWR0aD0iMjQiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+PHBhdGggZD0iTTIwLjAwMDUgOS41MDE5OFY4Ljc0OTg4QzIwLjAwMDUgNy41MDcyNCAxOC45OTMxIDYuNDk5ODggMTcuNzUwNSA2LjQ5OTg4SDEyLjAyNTJMOS42NDQxNyA0LjUxOTk4QzkuMjQwMDggNC4xODM5NiA4LjczMTEyIDQgOC4yMDU1OCA0SDQuMjUwMDZDMy4wMDc3MiA0IDIuMDAwNDkgNS4wMDY4OSAyLjAwMDA2IDYuMjQ5MjJMMS45OTYwOSAxNy43NDkyQzEuOTk1NjcgMTguOTkyMiAzLjAwMzE1IDIwIDQuMjQ2MDkgMjBINC4yNzI0NUM0LjI3NjU2IDIwIDQuMjgwNjggMjAgNC4yODQ4IDIwSDE4LjQ2OThDMTkuMjcyOCAyMCAxOS45NzI3IDE5LjQ1MzYgMjAuMTY3NSAxOC42NzQ2TDIxLjkxNzQgMTEuNjc2NUMyMi4xOTM2IDEwLjU3MiAyMS4zNTgyIDkuNTAxOTggMjAuMjE5NyA5LjUwMTk4SDIwLjAwMDVaTTQuMjUwMDYgNS41SDguMjA1NThDOC4zODA3NiA1LjUgOC41NTA0MSA1LjU2MTMyIDguNjg1MTEgNS42NzMzM0wxMS4yNzQ1IDcuODI2NTVDMTEuNDA5MiA3LjkzODU1IDExLjU3ODkgNy45OTk4OCAxMS43NTQxIDcuOTk5ODhIMTcuNzUwNUMxOC4xNjQ3IDcuOTk5ODggMTguNTAwNSA4LjMzNTY2IDE4LjUwMDUgOC43NDk4OFY5LjUwMTk4SDYuNDI0MzRDNS4zOTE4NCA5LjUwMTk4IDQuNDkxODYgMTAuMjA0NyA0LjI0MTQ5IDExLjIwNjRMMy40OTczMiAxNC4xODM3TDMuNTAwMDYgNi4yNDk3NEMzLjUwMDIgNS44MzU2MyAzLjgzNTk1IDUuNSA0LjI1MDA2IDUuNVpNNS42OTY3MiAxMS41NzAxQzUuNzgwMTggMTEuMjM2MiA2LjA4MDE3IDExLjAwMiA2LjQyNDM0IDExLjAwMkgyMC4yMTk3QzIwLjM4MjMgMTEuMDAyIDIwLjUwMTcgMTEuMTU0OCAyMC40NjIyIDExLjMxMjZMMTguNzEyMyAxOC4zMTA3QzE4LjY4NDUgMTguNDIyIDE4LjU4NDUgMTguNSAxOC40Njk4IDE4LjVINC4yODQ4QzQuMTIyMTYgMTguNSA0LjAwMjgyIDE4LjM0NzIgNC4wNDIyNiAxOC4xODk0TDUuNjk2NzIgMTEuNTcwMVoiIGZpbGw9IiNmZmZmZmYiLz48L3N2Zz4=');}
	.icon-download {background-image: url('data:image/svg+xml;base64,PD94bWwgdmVyc2lvbj0iMS4wIiA/PjxzdmcgYmFzZVByb2ZpbGU9InRpbnkiIGhlaWdodD0iMjRweCIgaWQ9IkxheWVyXzEiIHZlcnNpb249IjEuMiIgdmlld0JveD0iMCAwIDI0IDI0IiB3aWR0aD0iMjRweCIgeG1sOnNwYWNlPSJwcmVzZXJ2ZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiB4bWxuczp4bGluaz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94bGluayI+PGc+PHBhdGggZD0iTTE2LjcwNyw3LjQwNEMxNi41MTgsNy4yMTYsMTYuMjU5LDcuMTIxLDE2LDcuMTIxcy0wLjUxOCwwLjA5NS0wLjcwNywwLjI4M0wxMyw5LjY5N1YzYzAtMC41NTItMC40NDgtMS0xLTFzLTEsMC40NDgtMSwxICAgdjYuNjk3TDguNzA3LDcuNDA0QzguNTE4LDcuMjE2LDguMjY3LDcuMTExLDgsNy4xMTFTNy40ODIsNy4yMTYsNy4yOTMsNy40MDRjLTAuMzksMC4zOS0wLjM5LDEuMDI0LDAsMS40MTRMMTIsMTMuNWw0LjcwOS00LjY4NCAgIEMxNy4wOTcsOC40MjksMTcuMDk3LDcuNzk0LDE2LjcwNyw3LjQwNHoiIGZpbGw9IiNmZmYiIC8+PHBhdGggZD0iTTIwLjk4NywxNmMwLTAuMTA1LTAuMDA0LTAuMjExLTAuMDM5LTAuMzE2bC0yLTZDMTguODEyLDkuMjc1LDE4LjQzMSw5LDE4LDloLTAuMjE5Yy0wLjA5NCwwLjE4OC0wLjIxLDAuMzY4LTAuMzY3LDAuNTI1ICAgTDE1LjkzMiwxMWgxLjM0OGwxLjY2Nyw1SDUuMDU0bDEuNjY3LTVoMS4zNDhMNi41ODYsOS41MjVDNi40MjksOS4zNjgsNi4zMTIsOS4xODgsNi4yMTksOUg2QzUuNTY5LDksNS4xODgsOS4yNzUsNS4wNTIsOS42ODQgICBsLTIsNkMzLjAxNywxNS43ODksMy4wMTMsMTUuODk1LDMuMDEzLDE2QzMsMTYsMywyMSwzLDIxYzAsMC41NTMsMC40NDcsMSwxLDFoMTZjMC41NTMsMCwxLTAuNDQ3LDEtMUMyMSwyMSwyMSwxNiwyMC45ODcsMTZ6IiBmaWxsPSIjZmZmIi8+PC9nPjwvc3ZnPg==');}
	.icon-info {background-image: url('data:image/svg+xml;base64,PD94bWwgdmVyc2lvbj0iMS4wIiA/PjxzdmcgYmFzZVByb2ZpbGU9InRpbnkiIGhlaWdodD0iMjRweCIgaWQ9IkxheWVyXzEiIHZlcnNpb249IjEuMiIgdmlld0JveD0iMCAwIDI0IDI0IiB3aWR0aD0iMjRweCIgeG1sOnNwYWNlPSJwcmVzZXJ2ZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiB4bWxuczp4bGluaz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94bGluayI+PGc+PHBhdGggZD0iTTEzLjgzOSwxNy41MjVjLTAuMDA2LDAuMDAyLTAuNTU5LDAuMTg2LTEuMDM5LDAuMTg2Yy0wLjI2NSwwLTAuMzcyLTAuMDU1LTAuNDA2LTAuMDc5Yy0wLjE2OC0wLjExNy0wLjQ4LTAuMzM2LDAuMDU0LTEuNCAgIGwxLTEuOTk0YzAuNTkzLTEuMTg0LDAuNjgxLTIuMzI5LDAuMjQ1LTMuMjI1Yy0wLjM1Ni0wLjczMy0xLjAzOS0xLjIzNi0xLjkyLTEuNDE2QzExLjQ1Niw5LjUzMiwxMS4xMzQsOS41LDEwLjgxNSw5LjUgICBjLTEuODQ5LDAtMy4wOTQsMS4wOC0zLjE0NiwxLjEyNmMtMC4xNzksMC4xNTgtMC4yMjEsMC40Mi0wLjEwMiwwLjYyNmMwLjEyLDAuMjA2LDAuMzY3LDAuMywwLjU5NSwwLjIyMiAgIGMwLjAwNS0wLjAwMiwwLjU1OS0wLjE4NywxLjAzOS0wLjE4N2MwLjI2MywwLDAuMzY5LDAuMDU1LDAuNDAyLDAuMDc4YzAuMTY5LDAuMTE4LDAuNDgyLDAuMzQtMC4wNTEsMS40MDJsLTEsMS45OTUgICBjLTAuNTk0LDEuMTg1LTAuNjgxLDIuMzMtMC4yNDUsMy4yMjVjMC4zNTYsMC43MzMsMS4wMzgsMS4yMzYsMS45MjEsMS40MTZjMC4zMTQsMC4wNjMsMC42MzYsMC4wOTcsMC45NTQsMC4wOTcgICBjMS44NSwwLDMuMDk2LTEuMDgsMy4xNDgtMS4xMjZjMC4xNzktMC4xNTcsMC4yMjEtMC40MiwwLjEwMi0wLjYyNkMxNC4zMTIsMTcuNTQzLDE0LjA2MywxNy40NTEsMTMuODM5LDE3LjUyNXoiIGZpbGw9IiNmZmZmZmYiLz48Y2lyY2xlIGN4PSIxMyIgY3k9IjYuMDAxIiByPSIyLjUiIGZpbGw9IiNmZmZmZmYiLz48L2c+PC9zdmc+');}
	.icon-search {background-image: url('data:image/svg+xml;base64,PD94bWwgdmVyc2lvbj0iMS4wIiA/PjxzdmcgZW5hYmxlLWJhY2tncm91bmQ9Im5ldyAwIDAgMzIgMzIiIGlkPSJHbHlwaCIgdmVyc2lvbj0iMS4xIiB2aWV3Qm94PSIwIDAgMzIgMzIiIHhtbDpzcGFjZT0icHJlc2VydmUiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyIgeG1sbnM6eGxpbms9Imh0dHA6Ly93d3cudzMub3JnLzE5OTkveGxpbmsiPjxwYXRoIGQ9Ik0yNy40MTQsMjQuNTg2bC01LjA3Ny01LjA3N0MyMy4zODYsMTcuOTI4LDI0LDE2LjAzNSwyNCwxNGMwLTUuNTE0LTQuNDg2LTEwLTEwLTEwUzQsOC40ODYsNCwxNCAgczQuNDg2LDEwLDEwLDEwYzIuMDM1LDAsMy45MjgtMC42MTQsNS41MDktMS42NjNsNS4wNzcsNS4wNzdjMC43OCwwLjc4MSwyLjA0OCwwLjc4MSwyLjgyOCwwICBDMjguMTk1LDI2LjYzMywyOC4xOTUsMjUuMzY3LDI3LjQxNCwyNC41ODZ6IE03LDE0YzAtMy44NiwzLjE0LTcsNy03czcsMy4xNCw3LDdzLTMuMTQsNy03LDdTNywxNy44Niw3LDE0eiIgaWQ9IlhNTElEXzIyM18iLz48L3N2Zz4=');}
	.icon-close {background-image: url('data:image/svg+xml;base64,PD94bWwgdmVyc2lvbj0iMS4wIiA/Pjxzdmcgdmlld0JveD0iMCAwIDMyIDMyIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPjxkZWZzPjxzdHlsZT4uY2xzLTF7ZmlsbDpub25lO308L3N0eWxlPjwvZGVmcz48dGl0bGUvPjxnIGRhdGEtbmFtZT0iTGF5ZXIgMiIgaWQ9IkxheWVyXzIiPjxwYXRoIGQ9Ik00LDI5YTEsMSwwLDAsMS0uNzEtLjI5LDEsMSwwLDAsMSwwLTEuNDJsMjQtMjRhMSwxLDAsMSwxLDEuNDIsMS40MmwtMjQsMjRBMSwxLDAsMCwxLDQsMjlaIi8+PHBhdGggZD0iTTI4LDI5YTEsMSwwLDAsMS0uNzEtLjI5bC0yNC0yNEExLDEsMCwwLDEsNC43MSwzLjI5bDI0LDI0YTEsMSwwLDAsMSwwLDEuNDJBMSwxLDAsMCwxLDI4LDI5WiIvPjwvZz48ZyBpZD0iZnJhbWUiPjxyZWN0IGNsYXNzPSJjbHMtMSIgaGVpZ2h0PSIzMiIgd2lkdGg9IjMyIi8+PC9nPjwvc3ZnPg==');}
	.icon-video {background-image: url('data:image/svg+xml;base64,PD94bWwgdmVyc2lvbj0iMS4wIiA/PjwhRE9DVFlQRSBzdmcgIFBVQkxJQyAnLS8vVzNDLy9EVEQgU1ZHIDEuMS8vRU4nICAnaHR0cDovL3d3dy53My5vcmcvR3JhcGhpY3MvU1ZHLzEuMS9EVEQvc3ZnMTEuZHRkJz48c3ZnIGhlaWdodD0iMTAwJSIgc3R5bGU9ImZpbGwtcnVsZTpldmVub2RkO2NsaXAtcnVsZTpldmVub2RkO3N0cm9rZS1saW5lam9pbjpyb3VuZDtzdHJva2UtbWl0ZXJsaW1pdDoyOyIgdmVyc2lvbj0iMS4xIiB2aWV3Qm94PSIwIDAgNTEyIDUxMiIgd2lkdGg9IjEwMCUiIHhtbDpzcGFjZT0icHJlc2VydmUiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyIgeG1sbnM6c2VyaWY9Imh0dHA6Ly93d3cuc2VyaWYuY29tLyIgeG1sbnM6eGxpbms9Imh0dHA6Ly93d3cudzMub3JnLzE5OTkveGxpbmsiPjxwYXRoIGQ9Ik01MDEuMzAzLDEzMi43NjVjLTUuODg3LC0yMi4wMyAtMjMuMjM1LC0zOS4zNzcgLTQ1LjI2NSwtNDUuMjY1Yy0zOS45MzIsLTEwLjcgLTIwMC4wMzgsLTEwLjcgLTIwMC4wMzgsLTEwLjdjMCwwIC0xNjAuMTA3LDAgLTIwMC4wMzksMTAuN2MtMjIuMDI2LDUuODg4IC0zOS4zNzcsMjMuMjM1IC00NS4yNjQsNDUuMjY1Yy0xMC42OTcsMzkuOTI4IC0xMC42OTcsMTIzLjIzOCAtMTAuNjk3LDEyMy4yMzhjMCwwIDAsODMuMzA4IDEwLjY5NywxMjMuMjMyYzUuODg3LDIyLjAzIDIzLjIzOCwzOS4zODIgNDUuMjY0LDQ1LjI2OWMzOS45MzIsMTAuNjk2IDIwMC4wMzksMTAuNjk2IDIwMC4wMzksMTAuNjk2YzAsMCAxNjAuMTA2LDAgMjAwLjAzOCwtMTAuNjk2YzIyLjAzLC01Ljg4NyAzOS4zNzgsLTIzLjIzOSA0NS4yNjUsLTQ1LjI2OWMxMC42OTYsLTM5LjkyNCAxMC42OTYsLTEyMy4yMzIgMTAuNjk2LC0xMjMuMjMyYzAsMCAwLC04My4zMSAtMTAuNjk2LC0xMjMuMjM4Wm0tMjk2LjUwNiwyMDAuMDM5bDAsLTE1My42MDNsMTMzLjAxOSw3Ni44MDJsLTEzMy4wMTksNzYuODAxWiIgc3R5bGU9ImZpbGwtcnVsZTpub256ZXJvOyIvPjwvc3ZnPg==');}
	.label {background-color: #eee;}
	.tag-size {}
	.btn {display: inline-block; line-height: 32px; padding: 4px 16px; border-radius: 32px;}
	.btn-primary {background-color: #0091f7; color: #fff;}
	.main {padding-bottom: 52px;}
	.cover {display: block; min-height: 64px; position: relative; background-color: #ccc;}
	.cover img {display: block; width: 100%;}
	.action {position: absolute; bottom: 0; right: 0; padding: 8px;}
	.action .icon {margin-left: 8px; cursor: pointer; width: 28px; height: 28px;}
	.action .icon-download {background-color: #0091f7;}
	.files {padding: 0; margin-top: 32px; width: 100%; max-width: 480px;}
	.files td {padding: 12px; border-top: 1px solid #ccc; vertical-align: top;}
	.files td:first-child {padding-left: 0;}
	.files-disabled>a::before {content: ""; display: inline-block; width: 16px; height: 16px; opacity: 0.5; vertical-align: top; background: url('data:image/svg+xml;base64,PD94bWwgdmVyc2lvbj0iMS4wIiA/PjwhRE9DVFlQRSBzdmcgIFBVQkxJQyAnLS8vVzNDLy9EVEQgU1ZHIDEuMS8vRU4nICAnaHR0cDovL3d3dy53My5vcmcvR3JhcGhpY3MvU1ZHLzEuMS9EVEQvc3ZnMTEuZHRkJz48c3ZnIGVuYWJsZS1iYWNrZ3JvdW5kPSJuZXcgMCAwIDMyIDMyIiBoZWlnaHQ9IjMycHgiIGlkPSJMYXllcl8xIiB2ZXJzaW9uPSIxLjEiIHZpZXdCb3g9IjAgMCAzMiAzMiIgd2lkdGg9IjMycHgiIHhtbDpzcGFjZT0icHJlc2VydmUiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyIgeG1sbnM6eGxpbms9Imh0dHA6Ly93d3cudzMub3JnLzE5OTkveGxpbmsiPjxnPjxwb2x5bGluZSBmaWxsPSJub25lIiBwb2ludHM9IiAgIDY0OSwxMzcuOTk5IDY3NSwxMzcuOTk5IDY3NSwxNTUuOTk5IDY2MSwxNTUuOTk5ICAiIHN0cm9rZT0iI0ZGRkZGRiIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJvdW5kIiBzdHJva2UtbWl0ZXJsaW1pdD0iMTAiIHN0cm9rZS13aWR0aD0iMiIvPjxwb2x5bGluZSBmaWxsPSJub25lIiBwb2ludHM9IiAgIDY1MywxNTUuOTk5IDY0OSwxNTUuOTk5IDY0OSwxNDEuOTk5ICAiIHN0cm9rZT0iI0ZGRkZGRiIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJvdW5kIiBzdHJva2UtbWl0ZXJsaW1pdD0iMTAiIHN0cm9rZS13aWR0aD0iMiIvPjxwb2x5bGluZSBmaWxsPSJub25lIiBwb2ludHM9IiAgIDY2MSwxNTYgNjUzLDE2MiA2NTMsMTU2ICAiIHN0cm9rZT0iI0ZGRkZGRiIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJvdW5kIiBzdHJva2UtbWl0ZXJsaW1pdD0iMTAiIHN0cm9rZS13aWR0aD0iMiIvPjwvZz48cGF0aCBkPSJNMjcuOTIyLDEwLjYxNWMtMC4wNTEtMC4xMjItMC4xMjQtMC4yMzEtMC4yMTYtMC4zMjNsLTcuOTk4LTcuOTk4Yy0wLjA5Mi0wLjA5Mi0wLjIwMS0wLjE2NS0wLjMyMy0wLjIxNiAgQzE5LjI2NCwyLjAyNywxOS4xMzQsMiwxOSwySDVDNC40NDgsMiw0LDIuNDQ4LDQsM3MwLjQ0OCwxLDEsMWgxM3Y3YzAsMC41NTIsMC40NDcsMSwxLDFoN3YxNkg2VjdjMC0wLjU1Mi0wLjQ0OC0xLTEtMVM0LDYuNDQ4LDQsNyAgdjIyYzAsMC41NTMsMC40NDgsMSwxLDFoMjJjMC41NTMsMCwxLTAuNDQ3LDEtMVYxMUMyOCwxMC44NjcsMjcuOTczLDEwLjczNiwyNy45MjIsMTAuNjE1eiBNMjAsNS40MTRMMjQuNTg2LDEwSDIwVjUuNDE0eiIvPjwvc3ZnPg==') no-repeat; background-size: 75%; background-position: center;}
	.search-bar {position: fixed; bottom: 12px; right: 0; width: 100%; max-width: 480px; display: flex; padding: 0 16px;}
	.search-bar .icon-search {background-color: #fff; margin-top: 4px; cursor: pointer;}
	.search-bar .search-text {display: block; flex: 1; border: 1px solid #ccc; border-radius: 8px; line-height: 16px; font-size: 16px; margin-left: 8px; padding: 8px 16px;}
	.search-bar.closed {display: inline-block; width: auto;}
	.search-bar.closed .search-text {display: none;}
	.search-result {font-size: 16px; text-align: center; padding: 24px 0 8px 0;}
	.popup {overflow: hidden;}
	.popup-box {position: fixed; top: 0; bottom: 0; left: 0; right: 0; background: rgba(0,0,0,0.9); display: none; }
	.popup .popup-box {display : block;}
	.rom-info {display: block; width: 100%; height: 100%; background: #fff; position: absolute; position: relative;}
	.rom-info .rom-info-container {padding: 48px; height: 100%; overflow: auto;}
	.rom-info .rom-info-container .rom-info-wrapper {display: flex;}
	.rom-info .rom-cover {width: 33.33%; text-align: right;}
	.rom-info .rom-cover>img {display: inline-block; width: 100%; max-width: 320px;}
	.rom-info .rom-details {flex: 1; max-width: 640px; text-align: left; padding-left: 32px;}
	.rom-info .rom-details>h3 {font-size: 24px; font-weight: 400; text-align: left; padding: 0; margin-bottom: 8px;}
	.rom-info .rom-details .rom-title-sub {margin-bottom: 16px;}
	.rom-info .rom-details .rom-title-sub>* + *::before {content:"/"; margin-left: 8px; margin-right: 8px;}
	.rom-info .rom-details .rom-labels {margin-bottom: 16px;}
	.rom-info .rom-details .rom-labels>* {display: inline-block; vertical-align: top;}
	.rom-info .rom-details .rom-labels>* + * {margin-left: 8px;}
	.rom-info .rom-details .rom-labels .icon {background-color: rgba(0,0,0,0.25); background-size: 66.66%; opacity: 0.6; width: 28px; height: 28px;}
	.rom-info .rom-details .rom-labels .icon.genre {line-height: 28px; width: auto; color: #000; padding: 0 12px; font-weight: 500;}
	.rom-info .rom-details>.rom-description {line-height: 1.75;}
	.rom-info .icon-close {position: absolute; top: 8px; right: 8px; width: 32px; height: 32px; background-color: #eee; background-size: 42%; opacity: 50%; cursor: pointer;}
	@media only screen and (max-width: 768px) {
		li.rom {width: 50%; padding: 12px;}
	}
	@media only screen and (max-width: 480px) {
		li.rom {width: 100%; padding: 12px;}
		.rom-info .rom-info-container {padding: 24px;}
		.rom-info .rom-info-container .rom-info-wrapper {display: block;}
		.rom-info .rom-info-container .rom-info-wrapper .rom-cover {width: 100%; text-align: center;}
		.rom-info .rom-info-container .rom-info-wrapper .rom-cover>img {max-width: none;}
		.rom-info .rom-info-container .rom-info-wrapper .rom-details {padding: 0; margin-top: 16px;}
	}
	</style>
	</head>
	<body>
	<div class="main">
	<div class="search-result hidden"></div>
	<ul>
	$_ROMS_HTML_
	</ul>
	</div>
	<div class="search-bar closed"><span class="icon icon-search"></span><input type="text" class="search-text" placeholder="name"></div>
	<div class="popup-box"></div>
	<script>
	var searchBar = document.querySelector('.search-bar');
	var searchIcon = searchBar.querySelector('.icon-search');
	var searchInput = searchBar.querySelector('.search-text');
	var searchResult = document.querySelector('.search-result');
	var romDoms = document.querySelectorAll('li.rom>div');
	function isEmpty(v) {
		return v === undefined || v === null || v === '' ? true : false;
	}
	function search(text) {
		var roms = document.querySelectorAll('li');
		var re = new RegExp(text, 'i');
		var i = 0;
		roms.forEach(function(rom) {
			var title = rom.querySelector('h3').textContent;
			if (re.test(title)) {
				i++;
				rom.classList.remove('hidden');
			} else {
				rom.classList.add('hidden');
			}
		});
		if (text && text !== '') {
			searchResult.textContent = 'Found ' + i + ' ROMs.';
			searchResult.classList.remove('hidden');
		} else {
			searchResult.textContent = '';
			searchResult.classList.add('hidden');
		}
	}
	function openClosePopup(opened) {
		if (opened) {
			document.body.classList.add('popup');
		} else {
			document.body.classList.remove('popup');
		}
	}
	searchIcon.addEventListener('click', function(e){
		if (/closed/.test(searchBar.className)) {
			searchBar.classList.remove('closed');
			searchInput.focus();
		} else {
			searchBar.classList.add('closed');
			searchInput.value = '';
			search('');
		}
	});
	searchInput.addEventListener('input', function(e){
		search(e.target.value);
	});
	romDoms.forEach(function(dom) {
		dom.addEventListener('click', function(e) {
			var popupBox = document.querySelector('.popup-box');
			var cover = dom.querySelector('img').cloneNode(true);
			var title = dom.querySelector('h3').cloneNode(true);
			popupBox.innerHTML = '<div class="rom-info"><div class="rom-info-container"><div class="rom-info-wrapper"><div class="rom-cover"></div><div class="rom-details"></div></div></div><span class="icon icon-close"></span></div>';
			var romInfo = popupBox.querySelector('.rom-info');
			var romCover = popupBox.querySelector('.rom-cover');
			var romDetails = popupBox.querySelector('.rom-details');
			var close = popupBox.querySelector('.icon-close');
			close.addEventListener('click', function() {
				romInfo.outerHTML = '';
				openClosePopup(false);
			});
			cover && romCover.append(cover);
			title && romDetails.append(title);
			romDetails.innerHTML = romDetails.innerHTML + '<div class="rom-title-sub"></div>' + '<div class="rom-labels"><a href="https://www.youtube.com/results?search_query='+title.textContent.replace(/\s+/g,'+')+'+'+('$1'.replace(/-/g,'+'))+'" target="_blank"><span class="icon icon-video"></span></a></div>';
			var infoFile = dom.getAttribute('data-info');
			if (infoFile && infoFile != '') {
				var xhr = new XMLHttpRequest();
				xhr.open('GET', infoFile, true);
				xhr.onload = function (e) {
					try {
						var data = JSON.parse(e.target.responseText);
						romDetails.innerHTML = romDetails.innerHTML + '<div class="rom-description">' + (data.description && data.description !='' ? data.description : 'No Description.') + '</div>';
						var filesTable = '<tr><td>No files.</td></tr>';
						if (data.files && data.files[0]) {
							filesTable = '';
							data.files.forEach(function(f) {
								var fileName = f.name && f.name != '' ? f.name : f.path.replace(/.*\//,'');
								var filePath = f.path;
								var fileSize = f.size * 1 > 0 ? (
									f.size > 1024*1024*1024 ? (f.size/1024/1024/1024).toFixed(1) + ' GB'
									: f.size > 1024*1024 ? (f.size/1024/1024).toFixed(1) + ' MB'
									: f.size > 1024 ? (f.size/1024).toFixed(1) + ' KB'
									: f.size + ' Byte') : 'N/A';
								filesTable += '<tr><td width="75%"><a href="'+filePath+'" target="_blank">'+fileName+'</a></td><td width="25%">'+fileSize+'</td><tr>';
							});
						}
						romDetails.innerHTML = romDetails.innerHTML + '<table class="files"><tbody>' + filesTable + '</tbody></table>';
						var romTitleSub = romDetails.querySelector('.rom-title-sub');
						var romLabels = romDetails.querySelector('.rom-labels');
						romTitleSub.innerHTML = !isEmpty(data.publisher) ? (romTitleSub.innerHTML + '<span>' + data.publisher + '</span>') : romTitleSub.innerHTML;
						romTitleSub.innerHTML = !isEmpty(data.released_date) ? (romTitleSub.innerHTML + '<span>' + data.released_date + '</span>') : romTitleSub.innerHTML;
						if (!isEmpty(data.genre)) {
							data.genre.split(',').forEach(function(genre) {
								romLabels.innerHTML = '<span class="icon genre">' + genre + '</span>' + romLabels.innerHTML;
							});
						}
					} catch(e) {}
				};
				xhr.send(null);
			}

			openClosePopup(true);
		});
	});
	</script>
	</body>
	</html>
	EOF
	echo "[OK] Generated index: $_INDEX_FILE_"
	rom_downloaded_push "$_INDEX_FILE_"
	return 0
}

has_rom_file() {
	# $1: type $2 name
	[ -z "$1" -o -z "$2" ] && return 1
	_CUR_ROM_FILE_=""
	for _EXT_ in $ROMS_EXT $ARCHIVE_EXT;
	do
		[ -f "$CUR_DIR/$1/${2}.${_EXT_}" ] && _CUR_ROM_FILE_="$CUR_DIR/$1/${2}.${_EXT_}"
		[ -f "$CUR_DIR/$1/${2}.${_EXT_}.aria2" ] && _CUR_ROM_FILE_=""
		[ -z "$_CUR_ROM_FILE_" ] || break
	done
	[ -z "$_CUR_ROM_FILE_" ] || return 0
	return 1
}

need_decompression() {
	echo "$1" | grep -Eq "^($_ROM_NEED_EXTRACT_REGEX_)$" && return 0
	return 1
}

on_rom_download() {
	[ "$INCLUDED_ALIYUN" = "true" ] && aliyun_upload_rom "$@"
}

exist_rom() {
	# $1:console    $2:game short name    $3:info file
	[ "$ONLY_DOWNLOAD_INFO" = "true" ] && return 1
	[ "$FORCE_DOWNLOAD" = "true" ] && return 0
	[ "$INCLUDED_ALIYUN" = "true" ] && aliyun_exist_rom "$1" "$2" "$3" && echo "[INFO] [$1] $2 exists. SKIP downloading." && return 0
	[ -f "$3" ] && echo "[INFO] [$1] $2 exists. SKIP downloading." && return 0
	return 1
}

roms_files_push() {
	ROMS_DOWNLOADED=$(cat <<-EOF | sed '/^[  ]*$/d'
	$ROMS_DOWNLOADED
	$1
	EOF
	)
}

rom_downloaded_push() {
	ROM_DOWNLOADED=$(cat <<-EOF | sed '/^[  ]*$/d'
	$ROM_DOWNLOADED
	$1
	EOF
	)
	roms_files_push "$1"
}

rom_init() {
	# $1: Type $2: Short_Name
	[ -z "$1" ] && return 1
	ROM_DOWNLOADED=""
	_ROM_CONSOLE_FULLNAME_="$1"
	[ "$_ROM_CONSOLE_FULLNAME_" = "gamecube" ] && _ROM_CONSOLE_FULLNAME_="nintendo-gamecube"
	[ "$_ROM_CONSOLE_FULLNAME_" = "wii" ] && _ROM_CONSOLE_FULLNAME_="nintendo-wii"
	[ "$_ROM_CONSOLE_FULLNAME_" = "dreamcast" ] && _ROM_CONSOLE_FULLNAME_="sega-dreamcast"
	_ROM_CONSOLE_DIR_="$ROMS_ROOT_DIR/$_ROM_CONSOLE_FULLNAME_"
	_ROM_INFO_PATH_="$_ROM_CONSOLE_FULLNAME_/$INFO_DIR_NAME"
	_ROM_INFO_DIR_="$_ROM_CONSOLE_DIR_/$INFO_DIR_NAME"
	_ROM_INFO_FILE_="$_ROM_INFO_DIR_/$2.txt"
	_ROM_THUMBNAIL_DIR_="$_ROM_CONSOLE_DIR_/$THUBM_DIR_NAME"
	_ROM_TITLE_=""
	_ROM_NAME_=""
	_ROM_DESCRIPTION_=""
	_ROM_DL_URL_=""
	_ROM_FILES_=""
	_ROM_PUBLISHER_=""
	_ROM_RELEASED_DATE_=""
	_ROM_GENRE_=""
	_ROM_DL_URL_LIST_=""
	return 0
}

remove_rom() {
	# $1: Console/Short_Name
	rom_init $(echo "$1" | tr '/' ' ') || return 1
	[ -f "$_ROM_INFO_FILE_" ] && {
		_ROM_NAME_=$(grep -E '"name":' "$_ROM_INFO_FILE_" | sed -E -e 's/.*"name":\s+"(.*)".*/\1/g')
		echo "[INFO] Removeing ROM: $_ROM_NAME_"
		while read _FILE_
		do
			_FILE_NAME_=$(echo "$_FILE_" | awk -F'/' "{gsub(/\.($_ROM_EXT_REGEX_|$_ARCHIVE_EXT_REGEX_|$_THUMB_EXT_REGEX_)\$/,\"\",\$NF); print \$NF}")
			[ "$_ROM_NAME_" = "$_FILE_NAME_" ] && rm -f "$_FILE_" && echo "[REMOVE] $_FILE_"
		done <<-EOF
		$(find "$_ROM_DOWNLOAD_DIR_")
		EOF
		rm -f "$_ROM_INFO_FILE_" && echo "[REMOVE] $_ROM_INFO_FILE_"
		return 0
	}
	echo "[ERR] Not find ROM info file."
}

download_rom() {
	# $1: Type $2: Short Name
	[ -z "$1" -o -z "$2" ] && return 1
	[ -z "$DL_COUNT" ] || DL_COUNT=$((DL_COUNT+1))
	rom_init "$1" "$2" || return 1
	exist_rom "$1" "$2" "$_ROM_INFO_FILE_" && return 2
	# echo "$1/$2" | tee -a $CUR_DIR/to_download.txt
	# return 0
	case "$WEBSITE" in
		"romsgames.net")
			_ROM_HTML_=$(fetch_html "https://www.romsgames.net/${1}-rom-${2}/")
			_ROM_TITLE_=$(echo "$_ROM_HTML_" | grep -Eo '<h1[^>]*>[^<]+' | sed -E -e 's/<[^>]+>//g' -e 's/&amp;/\&/g')
			_ROM_ID_=$(echo "$_ROM_HTML_" |  grep -Eo 'dlid="[^"]+"' | awk -F'=' '{gsub(/"/, "", $2); print $2}')
			_ROM_DL_URLS_HTML_=$(curl "https://www.romsgames.net/download/${1}-rom-${2}/" --data-raw "mediaId=$_ROM_ID_" -skL)
			_ROM_DL_URLS_HTML_=$(echo "$_ROM_DL_URLS_HTML_" | sed -E -e 's/(<form[^>]+>)/\n\1/g' -e 's/(<\/form>)/\1\n/g' | grep 'output.bin')
			_ROM_DL_URL_ACTION=$(echo "$_ROM_DL_URLS_HTML_" | grep -Eo 'action="[^"]+"' | awk '{gsub(/"/,"",$0); gsub(/^action=/,"",$0); print $0}')
			_ROM_DL_URL_ATTACH=$(echo "$_ROM_DL_URLS_HTML_" | grep -Eo 'value="[^"]+"' | awk '{gsub(/"/,"",$0); gsub(/^value=/,"",$0); print $0}')
			_ROM_EXT_=$(echo "$_ROM_DL_URL_ATTACH" | awk -F'.' '{print $NF}')
			[ -z "$_ROM_DL_URL_ACTION" -o -z "$_ROM_DL_URL_ATTACH" ] && return 1
			_ROM_DL_URLS_="${_ROM_DL_URL_ACTION}?attach=${_ROM_DL_URL_ATTACH}::::${_ROM_TITLE_}.${_ROM_EXT_}"
			[ -z "$_ROM_DL_URLS_" ] && echo "$_ROM_DL_URLS_HTML_"
			_THUMB_URLS_=$(echo "$_ROM_HTML_" | grep -Eo '<div[^>]*game-cover"[^>]*><img[^>+]+>' | grep -Eo 'data-src="[^"]+"' | awk '{gsub(/"/,"",$0);gsub(/^data-src=/,"",$0); print $0}')
			_THUMB_URLS_=$(echo "$_THUMB_URLS_" | sed -E 's#^(\/.*)#https://www.romsgames.net\1#g')
			_ROM_DESCRIPTION_=$(echo "$_ROM_HTML_" | sed -E -e 's/(<div[^>]*>)/\n\1/g' -e 's/(<\/div>)/\1\n/g'| grep 'screenshots' | sed -E 's/<[^>]+>//g')
			_ROM_HEADER_REFERER_="--header=\"Referer: https://www.romsgames.net/\""
			;;
		"emulatorgames.net")
			_ROM_HTML_=$(curl "https://www.emulatorgames.net/roms/$1/$2/" -skL)
			_ROM_TITLE_=$(echo "$_ROM_HTML_" | grep -Eo '<h1[^>]*>[^<]+' | sed -E -e 's/<[^>]+>//g' -e 's/&amp;/\&/g')
			_ROM_ID_=$(echo "$_ROM_HTML_"  | grep -Eo 'data-id="[^"]+"' | head -n1 | awk -F'=' '{gsub(/"/,"",$2); print $2}')
			_ROM_DL_URLS_HTML_=$(curl 'https://www.emulatorgames.net/prompt/' -skL -H "referer: https://www.emulatorgames.net/download/?rom=$2" --data-raw "get_type=post&get_id=${_ROM_ID_}")
			_ROM_DL_URLS_=$(echo "$_ROM_DL_URLS_HTML_" | sed -E -e 's/\\//g' | grep -Eo 'https?:[^"]+/roms/[^"]+')
			_ROM_EXT_=$(echo "$_ROM_DL_URLS_" | awk -F'.' '{print $NF}')
			_ROM_DL_URLS_="$_ROM_DL_URLS_::::${_ROM_TITLE_}.${_ROM_EXT_}"
			[ -z "$_ROM_DL_URLS_" ] && echo "$_ROM_DL_URLS_HTML_"
			_THUMB_HTML_=$(echo "$_ROM_HTML_" | sed -E 's/(<\/?picture[^>]*>)/\n\1/g' | grep -E '^<picture' | head -n1)
			_THUMB_URLS_=$(echo "$_THUMB_HTML_" | grep -Eo "\"[^\"]+\.(${_THUMB_EXT_REGEX_})\"" | tr -d '"')
			_ROM_DESCRIPTION_=$(echo "$_ROM_HTML_" | grep -Eo '<p>[^<]+</p>' | awk '{gsub(/<\/?p>/,"",$0); print $0}')
			_ROM_HEADER_REFERER_=""
			;;
		"romspure.cc"|"romsfun.com")
			_ROM_HTML_=$(fetch_html "https://$WEBSITE/roms/$1/$2/" --oneline)
			# echo "$_ROM_HTML_"
			_ROM_TITLE_=$(echo "$_ROM_HTML_" | grep -Eo '<h1[^>]*>[^<]+'| sed -E -e 's/<[^>]+>//g' -e "s/&#39;/'/g" -e 's/&amp;/\&/g' -e 's/&[^;]+;//g' -e 's/^\s+//g' -e 's/\s+$//g' -e 's/\//-/g')
			_ROM_DL_BTN_URL_=$(echo "$_ROM_HTML_" | grep -Eo 'http[^"]+/download/[^"]+')
			[ -z "$_ROM_DL_BTN_URL_" ] && echo "[ERR] NO ROM Files."
			[ -z "$_ROM_DL_BTN_URL_" ] || {
				_ROM_DL_URL_LIST_=$(fetch_html "$_ROM_DL_BTN_URL_" | grep -Eo 'http[^"]+/download/[^"]+')
				[ "$_ROM_DL_URL_LIST_" = "$_ROM_DL_BTN_URL_" ] && {
					_ROM_DL_URL_LIST_=""
					_ROM_DL_URL_INDEX_=1
					while true
					do
						fetch_html "$_ROM_DL_BTN_URL_/$_ROM_DL_URL_INDEX_" -skL | grep -q 'click-here' && {
							[ -z "$_ROM_DL_URL_LIST_" ] && _ROM_DL_URL_LIST_="$_ROM_DL_BTN_URL_/$_ROM_DL_URL_INDEX_" || _ROM_DL_URL_LIST_=$(cat <<-EOF
							$_ROM_DL_URL_LIST_
							$_ROM_DL_BTN_URL_/$_ROM_DL_URL_INDEX_
							EOF
							)
						} || break
						_ROM_DL_URL_INDEX_=$((_ROM_DL_URL_INDEX_+1))
					done
				}
				# __RETRY_GET_FILE_URL__=3
				# while [ "$__RETRY_GET_FILE_URL__" -gt 0 ]
				# do
				# 	echo "[INFO] Trying fetch Download URLs: $_ROM_DL_BTN_URL_ ... ($__RETRY_GET_FILE_URL__)"
				# 	_ROM_DL_URL_LIST_HTML_=$(fetch_html "$_ROM_DL_BTN_URL_")
				# 	echo "$_ROM_DL_URL_LIST_HTML_" | grep -q 'Filename' && _ROM_DL_URL_LIST_=$(echo "$_ROM_DL_URL_LIST_HTML_" | grep -Eo 'http[^"]+/download/[^"]+')
				# 	[ -z "$_ROM_DL_URL_LIST_" ] || break
				# 	sleep 5
				# 	__RETRY_GET_FILE_URL__=$((__RETRY_GET_FILE_URL__-1))
				# done
				# echo "_ROM_DL_URL_LIST_: $_ROM_DL_URL_LIST_"
				[ -z "$_ROM_DL_URL_LIST_" ] || {
					_ROM_DL_URLS_=$(
						while read _ROM_DL_URL_
						do
							[ -z "$_ROM_DL_URL_" ] || {
								_ROM_DL_FILE_HTML_=$(fetch_html "$_ROM_DL_URL_")
								_ROM_DL_FILE_TITLE_=$(echo "$_ROM_DL_FILE_HTML_" | grep -Eo '<h1[^>]*>[^<]+'| sed -E -e 's/<[^>]+>//g' -e 's/&amp;/\&/g' -e 's/&[^;]+;//g' -e 's/^download *//ig')
								_ROM_DL_FILE_URL_=$(echo "$_ROM_DL_FILE_HTML_" | grep 'click-here' | grep -Eo 'http[^"]+')
								[ "$1" = "sega-dreamcast" ] && _ROM_DL_FILE_URL_=$(echo "$_ROM_DL_FILE_URL_" | awk '{gsub(/\.zip/,".7z",$0); print $0}')
								_ROM_DL_FILE_EXT_=$(echo "$_ROM_DL_FILE_URL_" | awk -F'.' '{gsub(/\?.*/,"",$NF); print $NF}')
								[ -z "$_ROM_DL_FILE_URL_" ] || echo "${_ROM_DL_FILE_URL_}::::$([ -z "$_ROM_DL_FILE_TITLE_" ] || echo "${_ROM_DL_FILE_TITLE_}.${_ROM_DL_FILE_EXT_}")"
							}
						done <<-EOF
						$_ROM_DL_URL_LIST_
						EOF
					)
				}
			}
			_THUMB_URLS_=$(echo "$_ROM_HTML_" | grep -Eo 'data-src="[^"]+"' | awk '{gsub(/(data-src=|")/,"",$0); print $0}')
			_ROM_ID_=$(echo "$_ROM_HTML_" | grep -Eo 'data-post-id="[^"]+"' | awk '{gsub(/(data-post-id=|")/,"",$0); print $0}')
			_ROM_DESCRIPTION_=$(curl "https://$WEBSITE/wp-admin/admin-ajax.php?action=k_get_desc&post_id=${_ROM_ID_}" -skL | sed -E -e 's/.*"message":\s*"(.*)"}.*/\1/g' -e 's/<[^>]+>//g')
			[ -z "$_ROM_DESCRIPTION_" ] && _ROM_DESCRIPTION_=$(echo "$_ROM_HTML_" | sed -E -e 's/(<div[^>]*>)/\n\1/g' -e 's/<\/div>/\n/g' | grep 'entry-content' | sed -E 's/^<div[^>]+>//g')
			_ROM_DETAILS_HTML_=$(echo "$_ROM_HTML_" | sed -E -e 's/(<tr[^>]*>)/\n\1/g' -e 's/<\/tr>/\n/g' | grep '^<tr' | sed -E -e 's/.*>([^<]+)<\/th>/\1::::/g' -e 's/<\/?[^>]*>//g')
			_ROM_PUBLISHER_=$(echo "$_ROM_DETAILS_HTML_" | grep -i '^Publisher' | awk -F'::::' '{print $2}')
			_ROM_RELEASED_DATE_=$(echo "$_ROM_DETAILS_HTML_" | grep -i '^Released' | awk -F'::::' '{print $2}')
			_ROM_GENRE_=$(echo "$_ROM_DETAILS_HTML_" | grep -i '^Genre' | awk -F'::::' '{print $2}')
			;;
		*)
			return 1
			;;
	esac
	echo "$([ -z "$DL_COUNT" ] || echo "[$DL_COUNT$([ -z "$DL_TOTAL" ] || echo "/$DL_TOTAL")] ")[$1] $_ROM_TITLE_"
	[ -z "$_ROM_TITLE_" ] && echo "[ERR] Fail to fetch ROM HTML." && return 1
	[ -d "$_ROM_CONSOLE_DIR_" ] || mkdir -p "$_ROM_CONSOLE_DIR_"
	# Download ROM Files
	[ -z "$_ROM_DL_URLS_" ] && [ "$ONLY_DOWNLOAD_INFO" != "true" ] && echo "[ERR] Could not get download URL of ROM: $1/$2" && return 1
	[ -z "$_ROM_DL_URLS_" ] || _ROM_DL_URLS_=$(echo "$_ROM_DL_URLS_" | awk ' !x[$0]++')
	echo "ROM_DL_URLS: $_ROM_DL_URLS_"
	while read _ROM_DL_URL_
	do
		_ROM_FILE_NAME_=$(echo "$_ROM_DL_URL_" | awk -F'::::' '{print $2}')
		_ROM_FILE_URL_=$(echo "$_ROM_DL_URL_" | awk -F'::::' '{print $1}')
		[ -z "$_ROM_FILE_NAME_" ] && _ROM_FILE_NAME_=$(echo "$_ROM_FILE_URL_" | awk -F'/' '{print $NF}')
		_ROM_FILE_CACHE_="$CACHE_DIR/$_ROM_FILE_NAME_"
		_ROM_FILE_PATH_="$1/$_ROM_FILE_NAME_"
		_ROM_FILE_FULLPATH_="$_ROM_CONSOLE_DIR_/$_ROM_FILE_NAME_"
		_ROM_FILE_IS_OK_="false"
		if [ -f "$_ROM_FILE_FULLPATH_" ] && [ ! -f "$_ROM_FILE_FULLPATH_.aria2" ]; then
			echo "[INFO] File exists (${_ROM_FILE_PATH_}) and SKIP downloading file."
			_ROM_FILE_IS_OK_="true"
		else
			[ "$ONLY_DOWNLOAD_INFO" != "true" ] && {
				if dl_file "$_ROM_FILE_URL_" "--output=\"$_ROM_FILE_FULLPATH_\"" "$_ROM_HEADER_REFERER_"; then
					echo "[OK] Success to download ROM File: $_ROM_FILE_PATH_"
					# need_decompression "$1" && {
					# 	[ -d "$_ROM_CACHE_DIR_" ] || mkdir -p "$_ROM_CACHE_DIR_"
					# 	rm -rf "$_ROM_CACHE_DIR_"/*
					# 	extract_file "$_ROM_FILE_" "$_ROM_CACHE_DIR_" && {
					# 		ls "$_ROM_CACHE_DIR_"/* | grep -E '(\.html|\.htm|\.txt)$' | while read _F_; do rm -f "$_F_"; done
					# 		_ROM_NAME_FROM_DL_=$(ls "$_ROM_CACHE_DIR_"/* | grep -E "\.($_ROM_EXT_REGEX_)$" | head -n1 | awk -F'/' '{gsub(/\.[^.]+$/,"",$NF); print $NF;}')
					# 		_ROM_FILES_=$(ls "$_ROM_CACHE_DIR_")
					# 		[ -z "$_ROM_NAME_FROM_DL_" ] || _ROM_NAME_="$_ROM_NAME_FROM_DL_"
					# 		mv "$_ROM_CACHE_DIR_"/* "$_ROM_DOWNLOAD_DIR_/"
					# 		rm -f "$_ROM_FILE_"
					# 		rom_downloaded_push "$(echo "$_ROM_FILES_" | sed -E "s#(.*)#$_ROM_DOWNLOAD_DIR_/\1#g")"
					# 	}
					# 	rm -rf $_ROM_CACHE_DIR_
					# }
					_ROM_FILE_IS_OK_="true"
				else
					echo "[ERR] Fail to download ROM file: ($_ROM_FILE_URL_)" && return 1
				fi
			}
		fi
		[ "$_ROM_FILE_IS_OK_" = "true" ] && {
			rom_downloaded_push "$_ROM_FILE_FULLPATH_"
			_ROM_FILE_SIZE_=$(get_file_size "$_ROM_FILE_FULLPATH_")
			_ROM_FILES_=$(cat <<-EOF | sed '/^[  ]*$/d'
			$_ROM_FILES_$([ -z "$_ROM_FILES_" ] || echo ",")
			{"path": "$_ROM_FILE_PATH_", "name": "$_ROM_FILE_NAME_", "size": $([ -z "$_ROM_FILE_SIZE_" ] && echo "null" || echo "$_ROM_FILE_SIZE_")}
			EOF
			)
		}
	done <<-EOF
	$_ROM_DL_URLS_
	EOF
	# Download ROM Thumbnail
	[ -z "$_THUMB_URLS_" ] || {
		echo "[INFO] Fetching ROM Thumbnail ..."
		while read _THUMB_URL_
		do
			echo "$_THUMB_URL_" | grep -Eq "\.(${_THUMB_EXT_REGEX_})" && {
				_THUBM_EXT_=$(echo "$_THUMB_URL_" | grep -Eo "\.(${_THUMB_EXT_REGEX_})" | head -n1 | tr -d '.')
				_THUMB_FILE_="${_ROM_THUMBNAIL_DIR_}/${_ROM_TITLE_}.${_THUBM_EXT_}"
				[ -f "$_THUMB_FILE_" ] && rom_downloaded_push "$_THUMB_FILE_" || {
					dl_file "$_THUMB_URL_" "--output=\"$_THUMB_FILE_\"" > /dev/null && echo "[INFO] Downloaded IMAGE: ${_ROM_TITLE_}.${_THUBM_EXT_}" && rom_downloaded_push "$_THUMB_FILE_"
				}
			}
		done <<-EOF
		$_THUMB_URLS_
		EOF
	}
	# Generate ROM Information File
	[ -d "$_ROM_INFO_DIR_" ] || mkdir -p "$_ROM_INFO_DIR_"
	_ROM_DESCRIPTION_=$(echo "$_ROM_DESCRIPTION_" | sed -E -e 's/"/\\"/g' -e 's/&amp;/\&/g' -e 's/&nbsp;/ /g')
	cat <<-EOF > "$_ROM_INFO_FILE_"
	{
		"short_name": "$2",
		"title": "$_ROM_TITLE_",
		"console": "$1",
		"publisher": "$_ROM_PUBLISHER_",
		"released_date": "$_ROM_RELEASED_DATE_",
		"genre": "$_ROM_GENRE_",
		"description": "$_ROM_DESCRIPTION_",
		"files": [$(echo "$_ROM_FILES_" | tr -d '\n')]
	}
	EOF
	rom_downloaded_push "$_ROM_INFO_FILE_"
	echo "$ROM_DOWNLOADED"
	on_rom_download "$1" "$2" "$ROM_DOWNLOADED"
	return 0
}

dl_page() {
	# $1: Type $2: Page
	[ -z "$1" -o -z "$2" ] && return 1
	[ $2 -gt 0 ] || return 1
	case "$WEBSITE" in
		"romsgames.net")
			_PAGE_URL_="https://www.romsgames.net/roms/$1/?letter=all&page=$2&sort=alphabetical"
			_PAGE_HTML_=$(curl "$_PAGE_URL_" -skL)
			_ROMS_URL_=$(echo "$_PAGE_HTML_" | sed -E -e 's/(<div[^>]+>)/\n\1/g' | grep 'game-cover' | grep -Eo 'href="[^"]+"' | awk '{gsub(/"/,"",$0); gsub(/^href=/,"",$0); print $0}' | awk -F'-rom-' '{print $2}' | tr -d '/')
			;;
		"emulatorgames.net")
			_PAGE_URL_="https://www.emulatorgames.net/roms/$1/$2/"
			[ "$2" = "1" ] && _PAGE_URL_="https://www.emulatorgames.net/roms/$1/"
			_PAGE_HTML_=$(curl "$_PAGE_URL_" -skL)
			_ROMS_URL_=$(echo "$_PAGE_HTML_" | sed -E 's/(<\/?ul[^>]*>)/\n\1/g' | grep 'site-list' | grep -Eo 'href="[^"]+"' | awk '{gsub(/"/,"",$0); gsub(/^href=/,"",$0); print $0}' | awk -F'/' '{print $NF=="" ? $(NF-1): $NF}')
			;;
		"romspure.cc"|"romsfun.com")
			_PAGE_URL_="https://$WEBSITE/roms/$1/page/$2/"
			_PAGE_HTML_=$(curl "$_PAGE_URL_" -skL)
			_ROMS_URL_=$(echo "$_PAGE_HTML_" | tr -d '\n\r' | sed -E -e 's/(<tr[^>]*>)/\n\1/g' -e 's/(<\/tr>)/\1\n/g' | grep '^<tr.*<td' | sed -E 's/.*href="([^"]+)".*/\1/g' | awk -F'/' '{gsub(/\.html.*/,"",$NF); print $NF==""?$(NF-1):$NF}')
			;;
		*)
			return 1
			;;
	esac
	_ROMS_COUNT_=$(echo "$_ROMS_URL_" | wc -l)
	echo "Fetching $1 - page $2"
	while read _SHORT_NAME_
	do
		download_rom "$1" "$_SHORT_NAME_"
	done<<-EOF
	$_ROMS_URL_
	EOF
	return 0
}

download_console() {
	_PAGES_=""
	case "$WEBSITE" in
		"romsgames.net")
			_HTML_=$(fetch_html "https://www.romsgames.net/roms/$1/?letter=all&page=1&sort=alphabetical")
			_PAGES_=$(echo "$_HTML_" | grep -Eo 'page=[0-9]+' | awk -F'=' '{print $2}' | tail -n1)
			;;
		"emulatorgames.net")
			_HTML_=$(fetch_html "https://www.emulatorgames.net/roms/$1/")
			_PAGES_=$(echo "$_HTML_" | grep -Eo 'href="[^"]+/[0-9]+/"' | tail -n1 | awk -F'/' '{print $(NF-1)}')
			[ -z "$_PAGES_" ] && _PAGES_="1"
			;;
		"romspure.cc"|"romsfun.com")
			_HTML_=$(fetch_html "https://$WEBSITE/roms/$1")
			_PAGES_=$(echo "$_HTML_" | grep -Eo 'page/[0-9]+' | tail -n1 | awk -F'/' '{print $2}')
			;;
		*)
			return 1
			;;
	esac
	[ -z "$_PAGES_" ] && return 1
	_CUR_=1
	list_roms "$1" >/dev/null 2>&1
	DL_COUNT=0
	DL_TOTAL="$_ROMS_COUNT_"
	while [ $_CUR_ -le $_PAGES_ ]
	do
		dl_page "$1" "$_CUR_" && gen_index
		_CUR_=$((_CUR_+1))
	done
}

download_roms() {
	[ -z "$1" ] && return 1
	eval $(echo "$1" | awk -F'/' '{print "__CONSOLE__=\""$1"\"; __ROM_SHORT_NAME__=\""$2"\""}')
	if [ -z "$__ROM_SHORT_NAME__" ]; then
		download_console "$@"
	else
		[ -z "$__CONSOLE__" -o -z "$__ROM_SHORT_NAME__" ] && echo "[ERR] Please input a valid rom name: CONSOLE/GAME_SHORT_NAME" && return 1
		if echo "$__ROM_SHORT_NAME__" | grep -Eq '^[0-9]+$' && [ $__ROM_SHORT_NAME__ -ge 1 ]; then
			__ROM_PAGE__="$__ROM_SHORT_NAME__"
			dl_page "$__CONSOLE__" "$__ROM_PAGE__"
		else
			download_rom "$__CONSOLE__" "$__ROM_SHORT_NAME__"
		fi
	fi
	gen_index "$__CONSOLE__"
}

list_roms() {
	case "$WEBSITE" in
		"romsgames.net")
			_HTML_=$(curl "https://www.romsgames.net/roms/" -skL)
			_CONSOLE_LIST_=$(echo "$_HTML_" | sed -E 's/(<a href="\/roms\/[^>]+>)/\n\1/g' | grep 'titlebox' | sed -E -e 's/.*href="([^"]+)".*>([^<]+)+.*>\s*([0-9]+).*/\2::::\1::::\3/g' | sort)
			;;
		"emulatorgames.net")
			_HTML_=$(curl https://www.emulatorgames.net/roms/ -skL)
			_CONSOLE_LIST_=$(echo "$_HTML_" | sed -E 's/(<\/?ul[^>]*>)/\n\1/g' | grep 'site-list' | sed -E 's/(<\/?li[^>]*>)/\n\1/g' | grep '^<li' | grep '/roms/' | sed -E 's/.*href="([^"]+)".*>([^<]+)<.*/\2::::\1::::/g' | sort)
			[ -z "$1" ] || {
				_PAGES_=$(curl "https://www.emulatorgames.net/roms/$1/" -skL | grep -Eo 'href="[^"]+/[0-9]+/"' | tail -n1 | awk -F'/' '{print $(NF-1)}')
				_LAST_PAGE_COUNT_=$(curl "https://www.emulatorgames.net/roms/$1/$([ -z "$_PAGES_" ] || echo "$_PAGES_/")" -skL | sed -E -e 's/(<li[^>]*>)/\n\1/g' -e 's/(<\/li>)/\1\n/g' | grep 'picture' | wc -l)
				[ -z "$_PAGES_" ] && _PAGES_="1"
				__ROMS_COUNT__=$(echo "$_PAGES_::::$_LAST_PAGE_COUNT_" | awk -F'::::' '{print ($1-1)*48+$2}')
			}
			;;
		"romspure.cc"|"romsfun.com")
			_HTML_=$(curl "https://$WEBSITE/roms/" -skL)
			_CONSOLE_LIST_=$(echo "$_HTML_" | tr -d '\n\r' | sed -E -e 's/(<tr[^>]*>)/\n\1/g' -e 's/(<\/tr>)/\1\n/g' | grep '^<tr.*<td' | sed -E -e 's/.*href="([^"]+)".*>([^<]+)<.*>([^<]+)<.*>([^<]+)<.*/\2::::\1::::\3::::\4/g' | sort)
			;;
		*)
			return 1
			;;
	esac
	if [ -z "$1" ]; then
		echo "Website: $WEBSITE"
		while read _CONSOLE_
		do
			echo "$_CONSOLE_" | awk -F'::::' '{gsub(/\/$/,"",$2); split($2,href,"/"); print $1" ("href[length(href)]")"($3!=""?" ("$3" ROMs)":"")}'
		done <<-EOF
		$_CONSOLE_LIST_
		EOF
	else
		_CONSOLE_=$(echo "$_CONSOLE_LIST_" | grep -E "/roms/$1/?::::" | head -n1)
		[ -z "$_CONSOLE_" ] || {
			eval $(echo "$_CONSOLE_" | awk -F'::::' '{print "_ROMS_TITLE_=\""$1"\"; _ROMS_COUNT_=\""$3"\""}')
			[ -z "$_ROMS_COUNT_" ] && _ROMS_COUNT_="$__ROMS_COUNT__"
			_ROMS_COUNT_LOCAL_=$(ls "$CUR_DIR/$1" 2>/dev/null | grep -E "\.($_ROM_EXT_REGEX_)$" | sed -E "s/\.($_ROM_EXT_REGEX_)$//" | sort -u | wc -l)
			cat <<-EOF
			$_ROMS_TITLE_ ($1)
			Website    : $WEBSITE
			Remote roms: $_ROMS_COUNT_
			Local roms : $_ROMS_COUNT_LOCAL_
			EOF
		}
	fi
}

list_websites() {
	echo "$WEBSITE_LIST" | awk -F':' '{print "["$3"] "$1}'
	echo "eg. WEBSITE=3 sh $0 list nintendo-64"
}

_init_
case "$1" in
	"list"|"l")
		shift
		list_roms "$@"
		;;
	"download"|"d")
		shift
		download_roms "$@"
		;;
	"remove"|"r")
		shift
		remove_rom "$@"
		;;
	"info"|"i")
		shift
		ONLY_DOWNLOAD_INFO="true"
		download_roms "$@"
		;;
	"index"|"I")
		shift
		gen_index "$@"
		;;
	"website"|"w")
		shift
		list_websites
		;;
	*)
		cat <<-EOF
		$0 [COMMAND] [CONSOLE/GAME_SHORT_NAME]
		Command: list:l / download:d / remove:r / info:i / index:I / website:w

		eg. 
		$0 list (list all consoles)
		$0 list nintendo-64
		$0 download nintendo-64 (download all roms of the console)
		$0 download nintendo-64/pokemon-puzzle-league
		$0 index
		EOF
		;;
esac




