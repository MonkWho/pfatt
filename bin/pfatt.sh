#!/bin/sh
set -e

ONT_IF='em0'
RG_IF='em1'
RG_ETHER_ADDR='xx:xx:xx:xx:xx:xx'                     

echo "$0: pfSense + AT&T U-verse Residential Gateway for true bridge mode"
echo "Configuration: "
echo "       ONT_IF: $ONT_IF"
echo "        RG_IF: $RG_IF"
echo "RG_ETHER_ADDR: $RG_ETHER_ADDR"

echo -n "loading netgraph kernel modules... "
/sbin/kldload ng_etf
echo "OK! (any 'already loaded' errors can be ignored)"

echo -n "attaching interfaces to ng_ether... "
/usr/local/bin/php -r "pfSense_ngctl_attach('.', '$ONT_IF');" 
/usr/local/bin/php -r "pfSense_ngctl_attach('.', '$RG_IF');"
echo "OK!"

echo "building netgraph nodes..."

echo -n "  creating ng_one2many... "
/usr/sbin/ngctl mkpeer $ONT_IF: one2many lower one
/usr/sbin/ngctl name $ONT_IF:lower o2m
echo "OK!"

echo -n "  creating vlan node and interface... "
/usr/sbin/ngctl mkpeer o2m: vlan many0 downstream
/usr/sbin/ngctl name o2m:many0 vlan0
/usr/sbin/ngctl mkpeer vlan0: eiface vlan0 ether

/usr/sbin/ngctl msg vlan0: 'addfilter { vlan=0 hook="vlan0" }'
/usr/sbin/ngctl msg ngeth0: set $RG_ETHER_ADDR
echo "OK!"

echo -n "  defining etf for $ONT_IF (ONT)... "
/usr/sbin/ngctl mkpeer o2m: etf many1 downstream
/usr/sbin/ngctl name o2m:many1 waneapfilter
/usr/sbin/ngctl connect waneapfilter: $ONT_IF: nomatch upper
echo "OK!"

echo -n "  defining etf for $RG_IF (RG)... "
/usr/sbin/ngctl mkpeer $RG_IF: etf lower downstream
/usr/sbin/ngctl name $RG_IF:lower laneapfilter
/usr/sbin/ngctl connect laneapfilter: $RG_IF: nomatch upper
echo "OK!"

echo -n "  bridging etf for $ONT_IF <-> $RG_IF... "
/usr/sbin/ngctl connect waneapfilter: laneapfilter: eapout eapout
echo "OK!"

echo -n "  defining filters for EAP traffic... "
/usr/sbin/ngctl msg waneapfilter: 'setfilter { matchhook="eapout" ethertype=0x888e }'
/usr/sbin/ngctl msg laneapfilter: 'setfilter { matchhook="eapout" ethertype=0x888e }'
echo "OK!"

echo -n "  enabling one2many links... "
/usr/sbin/ngctl msg o2m: setconfig "{ xmitAlg=2 failAlg=1 enabledLinks=[ 1 1 ] }"
echo "OK!"

echo -n "  removing waneapfilter:nomatch hook... "
/usr/sbin/ngctl rmhook waneapfilter: nomatch
echo "OK!"

echo "enabling interfaces..."
echo -n "  $RG_IF ... "
/sbin/ifconfig $RG_IF up
echo "OK!"

echo -n "  $ONT_IF ... "
/sbin/ifconfig $ONT_IF up
echo "OK!"

echo -n "enabling promiscuous mode on $RG_IF... "
/sbin/ifconfig $RG_IF promisc
echo "OK!"

echo -n "enabling promiscuous mode on $ONT_IF... "
/sbin/ifconfig $ONT_IF promisc
echo "OK!"

echo "ngeth0 should now be available to configure as your pfSense WAN"
echo "done!"
