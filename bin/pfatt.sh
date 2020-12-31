#!/bin/sh
set -e

ONT_IF='xx0'
RG_ETHER_ADDR='xx:xx:xx:xx:xx:xx'
CA_PEM='insert filename.pem'
CLIENT_PEM='insert filename.pem'
PRIVATE_PEM='insert filename.pem'

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
    
    # Enable this if Need to map physical port to RG MAC address:
    # echo -n "$(getTimestamp) mapping physical port to RG MAC address... "
    # /sbin/ifconfig $ONT_IF ether $RG_ETHER_ADDR
    # echo "OK!"

    echo "$(getTimestamp) ngeth0 should now be available to configure as your pfSense WAN"
    echo "$(getTimestamp) done!"
} >> $LOG


## Added code

{
    echo "$(getTimestamp) starting wpa_supplicant..."

    WPA_PARAMS="\
        set eapol_version 1,\
        set fast_reauth 1,\
        ap_scan 0,\
        add_network,\
        set_network 0 ca_cert \\\"/conf/pfatt/wpa/$CA_PEM\\\",\
        set_network 0 client_cert \\\"/conf/pfatt/wpa/$CLIENT_PEM\\\",\
        set_network 0 eap TLS,\
        set_network 0 eapol_flags 0,\
        set_network 0 identity \\\"$RG_ETHER_ADDR\\\",\
        set_network 0 key_mgmt IEEE8021X,\
        set_network 0 phase1 \\\"allow_canned_success=1\\\",\
        set_network 0 private_key \\\"/conf/pfatt/wpa/$PRIVATE_PEM\\\",\
        enable_network 0\
    "

    WPA_DAEMON_CMD="/usr/sbin/wpa_supplicant -Dwired -ingeth0 -B -C /var/run/wpa_supplicant"
    # if the above doesn't work try: WPA_DAEMON_CMD="/usr/sbin/wpa_supplicant -Dwired -i$ONT_IF -B -C /var/run/wpa_supplicant"

    # kill any existing wpa_supplicant process
    PID=$(pgrep -f "wpa_supplicant.*ngeth0")
    if [ ${PID} > 0 ];
    then
        echo "$(getTimestamp) pfatt terminating existing wpa_supplicant on PID ${PID}..."
        RES=$(kill ${PID})
    fi

    # start wpa_supplicant daemon
    RES=$(${WPA_DAEMON_CMD})
    PID=$(pgrep -f "wpa_supplicant.*ngeth0")
    echo "$(getTimestamp) pfatt wpa_supplicant running on PID ${PID}..."

    # Set WPA configuration parameters.
    echo "$(getTimestamp) pfatt setting wpa_supplicant network configuration..."
    IFS=","
    for STR in ${WPA_PARAMS};
    do
        STR="$(echo -e "${STR}" | sed -e 's/^[[:space:]]*//')"
        RES=$(eval wpa_cli ${STR})
    done

    # wait until wpa_cli has authenticated.
    WPA_STATUS_CMD="wpa_cli status | grep 'suppPortStatus' | cut -d= -f2"
    IP_STATUS_CMD="ifconfig ngeth0 | grep 'inet\ ' | cut -d' ' -f2"

    echo "$(getTimestamp) pfatt waiting EAP for authorization..."

    # TODO: blocking for bootup
    while true;
    do
        WPA_STATUS=$(eval ${WPA_STATUS_CMD})
        if [ X${WPA_STATUS} = X"Authorized" ];
        then
        echo "$(getTimestamp) pfatt EAP authorization completed..."

        IP_STATUS=$(eval ${IP_STATUS_CMD})

        if [ -z ${IP_STATUS} ] || [ ${IP_STATUS} = "0.0.0.0" ];
        then
            echo "$(getTimestamp) pfatt no IP address assigned, force restarting DHCP..."
            RES=$(eval /etc/rc.d/dhclient forcerestart ngeth0)
            IP_STATUS=$(eval ${IP_STATUS_CMD})
        fi
        echo "$(getTimestamp) pfatt IP address is ${IP_STATUS}..."
        break
        else
            sleep 1
        fi
    done
    echo "$(getTimestamp) pfatt ngeth0 should now be available to configure as your WAN..."
    echo "$(getTimestamp) pfatt done!"
    else
    echo "$(getTimestamp) pfatt error: unknown EAP_MODE. '$EAP_MODE' is not valid. exiting..."
    exit 1
    fi
} >> $LOG
