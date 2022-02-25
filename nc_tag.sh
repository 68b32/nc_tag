#!/bin/bash

_HOST="nextcloud.example.com"
_USERNAME="user"
_PASSWORD="password"

get_fileprop_by_path() {
	local path="$1"
	local prop="$2"
	curl -u $_USERNAME:$_PASSWORD "https://$_HOST/remote.php/dav/files/$_USERNAME/$path" -X PROPFIND --data '<?xml version="1.0" encoding="UTF-8"?>
	 <d:propfind xmlns:d="DAV:">
	   <d:prop xmlns:oc="http://owncloud.org/ns">
	     <oc:'"$prop"' />
	   </d:prop>
	 </d:propfind>' 2> /dev/null | xmlstarlet sel -t -v "//oc:$prop"
}



get_tags_from_server() {
	curl -s -u $_USERNAME:$_PASSWORD "https://$_HOST/remote.php/dav/systemtags"  -X PROPFIND --data '<?xml version="1.0" encoding="utf-8" ?>
	<a:propfind xmlns:a="DAV:" xmlns:oc="http://owncloud.org/ns">
	  <a:prop>
	    <oc:display-name/>
	    <oc:user-visible/>
	    <oc:user-assignable/>
	    <oc:id/>
	  </a:prop>
	</a:propfind>' | xmllint --format - | xmlstarlet sel -t -v "//oc:display-name | //oc:id" | grep -Pv '^$' | xargs -n2 -d'\n'
}

reload_tags() {
	_TAGS="`get_tags_from_server`"
}

validate_tagname() {
	local tag="$1"
	echo $tag | grep -P '[^0-9a-zA-Z\-]' &> /dev/null && echo "INVALID TAGNAME $tag" && return 1
}

tag_exists() {
	local needle="$1"
	validate_tagname "$tag"
	echo $_TAGS | grep -P "(^|\s)$needle [0-9]+" &> /dev/null
	return $?
}

get_id_for_tag() {
	local tag="$1"
	tag_exists "$tag" || return 1
	validate_tagname "$tag"
	echo $_TAGS | grep -Po "(^|\s)$tag [0-9]+" | awk '{print $2}'
	return $?
}

get_tag_for_id() {
	local tagid="$1"
	echo $_TAGS | grep -Po "(^|\s)[a-zA-Z0-9\-]+ $tagid(\s|$)" | awk '{print $1}'
}


get_tags_from_file() {
	local path="$1"
	fileid="`get_fileprop_by_path \"$path\" fileid`"
	echo $fileid | grep -P '[^0-9]' &> /dev/null && return 1
	[ -z "$fileid" ] && return 2

	curl -s -u $_USERNAME:$_PASSWORD "https://$_HOST/remote.php/dav/systemtags-relations/files/$fileid" -X PROPFIND --data '<?xml version="1.0" encoding="utf-8" ?>
	<a:propfind xmlns:a="DAV:" xmlns:oc="http://owncloud.org/ns">
	  <a:prop>
	    <oc:display-name/>
	    <oc:user-visible/>
	    <oc:user-assignable/>
	    <oc:id/>
	  </a:prop>
	</a:propfind>' | xmlstarlet sel -t -v "//oc:display-name" | grep -vP '^$'
}

file_has_tag() {
	local path="$1"
	local tag="$2"
	validate_tagname "$tag"
	get_tags_from_file "$path" | grep -P "^$tag$" && return 0
	return 1
}

add_tag_to_file() {
	local path="$1"
	local tag="$2"
	validate_tagname "$tag"
	file_has_tag "$path" "$tag" && return 1

	fileid="`get_fileprop_by_path \"$path\" fileid`"
	echo $fileid | grep -P '[^0-9]' &> /dev/null && return 1
	[ -z "$fileid" ] && return 2

	tagid="`get_id_for_tag \"$tag\"`"
	echo $tagid | grep -P '[^0-9]' &> /dev/null && return 1
	[ -z "$tagid" ] && return 2

	curl -s -u $_USERNAME:$_PASSWORD "https://$_HOST/remote.php/dav/systemtags-relations/files/$fileid/$tagid" -X PUT
	return $?
}

add_tag_to_server() {
	local tag="$1"
	validate_tagname "$tag"
	tag_exists "$tag" && return 1
	curl -s -u $_USERNAME:$_PASSWORD "https://$_HOST/remote.php/dav/systemtags/" -X POST -H 'Content-Type: application/json' --data "{\"userVisible\":true,\"userAssignable\":true,\"canAssign\":true,\"name\":\"$tag\"}"
	return $?
}

