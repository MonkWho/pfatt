#!/bin/sh
set -e

ONT_IF='em0'
RG_IF='em1'
RG_ETHER_ADDR='xx:xx:xx:xx:xx:xx'
LOG=/var/log/opnatt.log

getTimestamp(){
    echo `date "+%Y-%m-%d %H:%M:%S :: [opnatt.sh] ::"`
}

{
    echo "$(getTimestamp) opnSense + AT&T U-verse Residential Gateway for true bridge mode"
    echo "$(getTimestamp) Configuration: "
    echo "$(getTimestamp)        ONT_IF: $ONT_IF"
    echo "$(getTimestamp)         RG_IF: $RG_IF"
    echo "$(getTimestamp) RG_ETHER_ADDR: $RG_ETHER_ADDR"

    echo -n "$(getTimestamp) loading netgraph kernel modules... "
    /sbin/kldload -nq netgraph
    /sbin/kldload -nq ng_ether
    /sbin/kldload -nq ng_etf
    /sbin/kldload -nq ng_vlan
    /sbin/kldload -nq ng_eiface
    /sbin/kldload -nq ng_one2many
    echo "OK!"

    echo "$(getTimestamp) building netgraph nodes..."

    echo -n "$(getTimestamp)   creating ng_one2many... "
    /usr/sbin/ngctl mkpeer $ONT_IF: one2many lower one
    /usr/sbin/ngctl name $ONT_IF:lower o2m
    echo "OK!"

    echo -n "$(getTimestamp)   creating vlan node and interface... "
    /usr/sbin/ngctl mkpeer o2m: vlan many0 downstream
    /usr/sbin/ngctl name o2m:many0 vlan0
    /usr/sbin/ngctl mkpeer vlan0: eiface vlan0 ether

    /usr/sbin/ngctl msg vlan0: 'addfilter { vlan=0 hook="vlan0" }'
    /usr/sbin/ngctl msg ngeth0: set $RG_ETHER_ADDR
    echo "OK!"

    echo -n "$(getTimestamp)   defining etf for $ONT_IF (ONT)... "
    /usr/sbin/ngctl mkpeer o2m: etf many1 downstream
    /usr/sbin/ngctl name o2m:many1 waneapfilter
    /usr/sbin/ngctl connect waneapfilter: $ONT_IF: nomatch upper
    echo "OK!"

    echo -n "$(getTimestamp)   defining etf for $RG_IF (RG)... "
    /usr/sbin/ngctl mkpeer $RG_IF: etf lower downstream
    /usr/sbin/ngctl name $RG_IF:lower laneapfilter
    /usr/sbin/ngctl connect laneapfilter: $RG_IF: nomatch upper
    echo "OK!"

    echo -n "$(getTimestamp)   bridging etf for $ONT_IF <-> $RG_IF... "
    /usr/sbin/ngctl connect waneapfilter: laneapfilter: eapout eapout
    echo "OK!"

    echo -n "$(getTimestamp)   defining filters for EAP traffic... "
    /usr/sbin/ngctl msg waneapfilter: 'setfilter { matchhook="eapout" ethertype=0x888e }'
    /usr/sbin/ngctl msg laneapfilter: 'setfilter { matchhook="eapout" ethertype=0x888e }'
    echo "OK!"

    echo -n "$(getTimestamp)   enabling one2many links... "
    /usr/sbin/ngctl msg o2m: setconfig "{ xmitAlg=2 failAlg=1 enabledLinks=[ 1 1 ] }"
    echo "OK!"

    echo -n "$(getTimestamp)   removing waneapfilter:nomatch hook... "
    /usr/sbin/ngctl rmhook waneapfilter: nomatch
    echo "OK!"

    echo -n "$(getTimestamp) enabling $RG_IF interface... "
    /sbin/ifconfig $RG_IF up
    echo "OK!"

    echo -n "$(getTimestamp) enabling $ONT_IF interface... "
    /sbin/ifconfig $ONT_IF up
    echo "OK!"

    echo -n "$(getTimestamp) enabling promiscuous mode on $RG_IF... "
    /sbin/ifconfig $RG_IF promisc
    echo "OK!"

    echo -n "$(getTimestamp) enabling promiscuous mode on $ONT_IF... "
    /sbin/ifconfig $ONT_IF promisc
    echo "OK!"

    echo "$(getTimestamp) ngeth0 should now be available to configure as your opnSense WAN"
    echo "$(getTimestamp) done!"
} >> $LOG
