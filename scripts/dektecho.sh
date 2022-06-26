#!/usr/bin/env bash

#infomsg
infomsg () {
    echo
    printf "\e[32mℹ️  ===== $1 ===== \e[m\n"
    echo
}

#statusmsg
statusmsg () {
    echo
    printf "\e[37mℹ️  $1 ...\e[m\n"
    echo
}

#cmdmsg
cmdmsg () {
    echo
    printf "\e[35m▶ $1 \e[m\n"
    echo
}

#errmsg
errmsg () {
    echo
    printf "\e[31m⏹  $1 \e[m\n"
    echo
}

#prompt
prompt() {

    while true; do
        printf "\e[33m⏯  $1 (y/n) \e[m"
        read yn
        case $yn in
            [Yy]* ) exit 0;;
            [Nn]* ) exit 1;;
            * ) errmsg "Please answer yes or no.";;
        esac
    done
}


case $1 in
info)
  	infomsg "$2"
    ;;
status)
    statusmsg "$2"
    ;;
cmd)
    cmdmsg "$2"
    ;;
err)
    errmsg "$2"
    ;;
prompt)
    prompt "$2"
    ;;
*)
	errmsg "Incorrect usage. Please specify one of the following: info [msg], cmd [msg], err [msg], prompt [msg]"
	;;
esac