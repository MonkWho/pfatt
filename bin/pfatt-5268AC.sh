#!/bin/sh
PING_HOST=8.8.8.8
SLEEP=5
LOG=/var/log/pfatt.log

getTimestamp(){
    echo `date "+%Y-%m-%d %H:%M:%S :: [pfatt-5268AC.sh] ::"`
}

{
    RG_CONNECTED="/usr/sbin/ngctl show laneapfilter:eapout"

    echo "$(getTimestamp) Starting 5268AC ping monitor ..."
    while
    if /sbin/ping -t2 -q -c1 $PING_HOST > /dev/null ; then
        if $RG_CONNECTED >/dev/null 2>&1 ; then
        echo "$(getTimestamp) Connection to $PING_HOST is up, but EAP is being bridged!"
        echo -n "$(getTimestamp) Disconnecting netgraph node ... "
        /usr/sbin/ngctl rmhook laneapfilter: eapout && echo "OK!" || echo "ERROR!"
        fi
    else
        if ! $RG_CONNECTED >/dev/null 2>&1 ; then
        echo "$(getTimestamp) Connection to $PING_HOST is down, but EAP is not being bridged!"
        echo -n "$(getTimestamp) Connecting netgraph node ... "
        /usr/sbin/ngctl connect waneapfilter: laneapfilter: eapout eapout  && echo "OK!" || echo "ERROR!"
        fi
    fi
    sleep $SLEEP
    do :; done 
    echo "$(getTimestamp) Stopping 5268AC ping monitor ..."
} >> $LOG