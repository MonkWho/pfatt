#!/bin/sh
set -e

ONT_IF='xx0'
RG_ETHER_ADDR='xx:xx:xx:xx:xx:xx'
LOG=/var/log/pfatt.log

getTimestamp(){
    echo `date "+%Y-%m-%d %H:%M:%S :: [pfatt.sh] ::"`
}

{
    echo "$(getTimestamp) pfSense + AT&T U-verse Residential Gateway bypass mode"
    echo "$(getTimestamp) Configuration: "
    echo "$(getTimestamp)        ONT_IF: $ONT_IF"
    echo "$(getTimestamp) RG_ETHER_ADDR: $RG_ETHER_ADDR"

    echo -n "$(getTimestamp) attaching interfaces to ng_ether... "
    /usr/local/bin/php -r "pfSense_ngctl_attach('.', '$ONT_IF');"
    echo "OK!"

    echo "$(getTimestamp) building netgraph nodes..."
    
    echo -n "$(getTimestamp)   creating vlan node and interface... "
    /usr/sbin/ngctl mkpeer $ONT_IF: vlan lower downstream
    /usr/sbin/ngctl name $ONT_IF:lower vlan0
    /usr/sbin/ngctl mkpeer vlan0: eiface vlan0 ether
    
    /usr/sbin/ngctl msg vlan0: 'addfilter { vlan=0 hook="vlan0" }'
    /usr/sbin/ngctl msg ngeth0: set $RG_ETHER_ADDR
    echo "OK!" 
        
    echo -n "$(getTimestamp) enabling $ONT_IF interface... "
    /sbin/ifconfig $ONT_IF up
    echo "OK!"

    echo -n "$(getTimestamp) enabling promiscuous mode on $ONT_IF... "
    /sbin/ifconfig $ONT_IF promisc
    echo "OK!"

    echo "$(getTimestamp) ngeth0 should now be available to configure as your pfSense WAN"
    echo "$(getTimestamp) done!"
} >> $LOG
