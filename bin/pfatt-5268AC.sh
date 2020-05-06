#!/usr/bin/env sh
#
# CONFIG
# ======
#
# PING_HOST - IP where ping should check for connectivity
#
# SLEEP     - How often to check connectivity in seconds
#

PING_HOST=8.8.8.8
SLEEP=5

###############################################################################

RG_CONNECTED="/usr/sbin/ngctl show laneapfilter:eapout"

/usr/bin/logger -sit "pfatt-5268AC" "starting 5268AC ping monitor..."
while
if /sbin/ping -t2 -q -c1 $PING_HOST > /dev/null ; then
    if $RG_CONNECTED >/dev/null 2>&1 ; then
      /usr/bin/logger -sit "pfatt-5268AC" "connection to $PING_HOST is up, but EAP is being bridged!"
      /usr/bin/logger -sit "pfatt-5268AC" "removing laneapfilter: eapout netgraph hook..."
      /usr/sbin/ngctl rmhook laneapfilter: eapout
    fi
else
    if ! $RG_CONNECTED >/dev/null 2>&1 ; then
      /usr/bin/logger -sit "pfatt-5268AC" "connection to $PING_HOST is down, but EAP is not being bridged!"
      /usr/bin/logger -sit "pfatt-5268AC" "connecting waneapfilter: -> laneapfilter: netgraph nodes..."
      /usr/sbin/ngctl connect waneapfilter: laneapfilter: eapout eapout
    fi
fi
sleep $SLEEP
do :; done
/usr/bin/logger -sit "pfatt-5268AC" "stopping 5268AC ping monitor ..."
