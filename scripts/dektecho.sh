#!/usr/bin/env bash

#infomsg
infomsg () {
    echo
    printf "\e[32mℹ️  ===== $1 ===== \e[m\n"
    echo
}

#cmdmsg
cmdmsg () {
    echo
    printf "\e[36m▶️ $1 \e[m\n"
    echo
}

#errmsg
errmsg () {
    echo
    printf "\e[31m⏹️  $1 \e[m\n"
    echo
}


case $1 in
info)
  	infomsg "$2"
    ;;
cmd)
    cmdmsg "$2"
    ;;
err)
    errmsg "$2"
    ;;
*)
	errmsg "Incorrect usage. Please specify one of the following: info [msg], cmd [msg], err [msg]"
	;;
esac