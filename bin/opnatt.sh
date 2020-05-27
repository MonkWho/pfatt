#!/usr/bin/env sh
#
# CONFIG
# ======
#
# ONT_IF                  Interface connected to the ONT
#
# RG_ETHER_ADDR           MAC address of your assigned Residential Gateway
#
# EAP_MODE                EAP authentication mode: supplicant or bridge
#
#    supplicant           Use wpa_supplicant to authorize your connection.
#                         Requires valid certs in /conf/pfatt/wpa. No
#                         Residential Gateway connection required.
#
#    bridge               Bridge EAPoL traffic from your Residential Gateway to
#                         authorize your connection. Residential Gateway
#                         connection required.
#
# EAP_SUPPLICANT_IDENTITY Required only with supplicant mode. MAC address associated
#                         with your cert used as your EAP-TLS identity. If you extracted
#                         the cert from your stock issue residential gateway, this is the
#                         same as $RG_ETHER_ADDR.
#
# EAP_BRIDGE_IF           Required only with bridge mode. Interface that is connected
#                         to your Residential Gateway.
#
# EAP_BRIDGE_5268AC       Required only with bridge mode. Enable workaround for 5268AC.
#                         Enable if you have the 5268AC. See https://github.com/aus/pfatt/issues/5
#                         for details. 0=OFF 1=ON
#

# Required Config
# ===============
ONT_IF="xx0"
RG_ETHER_ADDR="xx:xx:xx:xx:xx:xx"
EAP_MODE="bridge"

# Supplicant Config
# =================
EAP_SUPPLICANT_IDENTITY="xx:xx:xx:xx:xx:xx"

# Bridge Config
# =============
EAP_BRIDGE_IF="xx1"
EAP_BRIDGE_5268AC=0

##### DO NOT EDIT BELOW #################################################################################

/usr/bin/logger -st "pfatt" "starting pfatt..."
/usr/bin/logger -st "pfatt" "configuration:"
/usr/bin/logger -st "pfatt" "  ONT_IF = $ONT_IF"
/usr/bin/logger -st "pfatt" "  RG_ETHER_ADDR = $RG_ETHER_ADDR"
/usr/bin/logger -st "pfatt" "  EAP_MODE = $EAP_MODE"
/usr/bin/logger -st "pfatt" "  EAP_SUPPLICANT_IDENTITY = $EAP_SUPPLICANT_IDENTITY"
/usr/bin/logger -st "pfatt" "  EAP_BRIDGE_IF = $EAP_BRIDGE_IF"
/usr/bin/logger -st "pfatt" "  EAP_BRIDGE_5268AC = $EAP_BRIDGE_5268AC"

/usr/bin/logger -st "pfatt" "resetting netgraph..."
/usr/sbin/ngctl shutdown waneapfilter: >/dev/null 2>&1
/usr/sbin/ngctl shutdown laneapfilter: >/dev/null 2>&1
/usr/sbin/ngctl shutdown $ONT_IF: >/dev/null 2>&1
/usr/sbin/ngctl shutdown $EAP_BRIDGE_IF: >/dev/null 2>&1
/usr/sbin/ngctl shutdown o2m: >/dev/null 2>&1
/usr/sbin/ngctl shutdown vlan0: >/dev/null 2>&1
/usr/sbin/ngctl shutdown ngeth0: >/dev/null 2>&1

/sbin/kldload -nq netgraph
/sbin/kldload -nq ng_ether
/sbin/kldload -nq ng_vlan
/sbin/kldload -nq ng_eiface
/sbin/kldload -nq ng_one2many

if [ "$EAP_MODE" = "bridge" ] ; then
  /usr/bin/logger -st "pfatt" "configuring EAP environment for $EAP_MODE mode..."
  /usr/bin/logger -st "pfatt" "cabling should look like this:"
  /usr/bin/logger -st "pfatt" "  ONT---[] [$ONT_IF]$HOST[$EAP_BRIDGE_IF] []---[] [ONT_PORT]ResidentialGateway"
  /usr/bin/logger -st "pfatt" "loading netgraph kernel modules..."
  /sbin/kldload -nq ng_etf
  /usr/bin/logger -st "pfatt" "attaching interfaces to ng_ether..."
  /usr/local/bin/php -r "pfSense_ngctl_attach('.', '$ONT_IF');"
  /usr/local/bin/php -r "pfSense_ngctl_attach('.', '$EAP_BRIDGE_IF');"

  /usr/bin/logger -st "pfatt" "building netgraph nodes..."

  /usr/bin/logger -st "pfatt" "creating ng_one2many..."
  /usr/sbin/ngctl mkpeer $ONT_IF: one2many lower one
  /usr/sbin/ngctl name $ONT_IF:lower o2m

  /usr/bin/logger -st "pfatt" "creating vlan node and interface..."
  /usr/sbin/ngctl mkpeer o2m: vlan many0 downstream
  /usr/sbin/ngctl name o2m:many0 vlan0
  /usr/sbin/ngctl mkpeer vlan0: eiface vlan0 ether
  /usr/sbin/ngctl msg vlan0: 'addfilter { vlan=0 hook="vlan0" }'
  /usr/sbin/ngctl msg ngeth0: set $RG_ETHER_ADDR

  /usr/bin/logger -st "pfatt" "defining etf for $ONT_IF (ONT)..."
  /usr/sbin/ngctl mkpeer o2m: etf many1 downstream
  /usr/sbin/ngctl name o2m:many1 waneapfilter
  /usr/sbin/ngctl connect waneapfilter: $ONT_IF: nomatch upper

  /usr/bin/logger -st "pfatt" "defining etf for $EAP_BRIDGE_IF (RG)... "
  /usr/sbin/ngctl mkpeer $EAP_BRIDGE_IF: etf lower downstream
  /usr/sbin/ngctl name $EAP_BRIDGE_IF:lower laneapfilter
  /usr/sbin/ngctl connect laneapfilter: $EAP_BRIDGE_IF: nomatch upper

  /usr/bin/logger -st "pfatt" "bridging etf for $ONT_IF <-> $EAP_BRIDGE_IF... "
  /usr/sbin/ngctl connect waneapfilter: laneapfilter: eapout eapout

  /usr/bin/logger -st "pfatt" "defining filters for EAP traffic... "
  /usr/sbin/ngctl msg waneapfilter: 'setfilter { matchhook="eapout" ethertype=0x888e }'
  /usr/sbin/ngctl msg laneapfilter: 'setfilter { matchhook="eapout" ethertype=0x888e }'

  /usr/bin/logger -st "pfatt" "enabling one2many links... "
  /usr/sbin/ngctl msg o2m: setconfig "{ xmitAlg=2 failAlg=1 enabledLinks=[ 1 1 ] }"

  /usr/bin/logger -st "pfatt" "removing waneapfilter:nomatch hook... "
  /usr/sbin/ngctl rmhook waneapfilter: nomatch

  /usr/bin/logger -st "pfatt" "enabling interfaces..."
  /sbin/ifconfig $EAP_BRIDGE_IF up
  /sbin/ifconfig $ONT_IF up

  /usr/bin/logger -st "pfatt" "enabling promiscuous mode..."
  /sbin/ifconfig $EAP_BRIDGE_IF promisc
  /sbin/ifconfig $ONT_IF promisc

  logger -st "pfatt" "waiting for EAP to complete authorization (unimplemented!)..."
  # TODO: detect, wait for EAP
  # TODO: force DHCP if needed

  if [ "$EAP_BRIDGE_5268AC" = "1" ] ; then
    # install proper rc script
    /bin/cp /conf/pfatt/bin/pfatt-5268AC.rc /usr/local/etc/rc.d/pfatt-5268AC.sh
    # kill any existing pfatt-5268AC process
    PID=$(pgrep -f "pfatt-5268AC")
    if [ ${PID} > 0 ]; then
      /usr/bin/logger -st "pfatt" "terminating existing pfatt-5268AC on PID ${PID}..."
      RES=$(kill ${PID})
      /usr/local/etc/rc.d/pfatt-5268AC.sh stop
    fi
    /usr/bin/logger -st "pfatt" "enabling 5268AC workaround..."
    /usr/local/etc/rc.d/pfatt-5268AC.sh start
  fi
  /usr/bin/logger -st "pfatt" "ngeth0 should now be available to configure as your WAN..."
  /usr/bin/logger -st "pfatt" "done!"

elif [ "$EAP_MODE" = "supplicant" ] ; then
  /usr/bin/logger -st "pfatt" "configuring EAP environment for $EAP_MODE mode..."
  /usr/bin/logger -st "pfatt" "cabling should look like this:"
  /usr/bin/logger -st "pfatt" "  ONT---[] [$ONT_IF]$HOST"
  /usr/bin/logger -st "pfatt" "creating vlan node and ngeth0 interface..."
  /usr/sbin/ngctl mkpeer $ONT_IF: vlan lower downstream
  /usr/sbin/ngctl name $ONT_IF:lower vlan0
  /usr/sbin/ngctl mkpeer vlan0: eiface vlan0 ether
  /usr/sbin/ngctl msg vlan0: 'addfilter { vlan=0 hook="vlan0" }'
  /usr/sbin/ngctl msg ngeth0: set $RG_ETHER_ADDR

  /usr/bin/logger -st "pfatt" "enabling promisc for $ONT_IF..."
  /sbin/ifconfig $ONT_IF up
  /sbin/ifconfig $ONT_IF promisc

  /usr/bin/logger -st "pfatt" "starting wpa_supplicant..."

  WPA_PARAMS="\
    set eapol_version 2,\
    set fast_reauth 1,\
    ap_scan 0,\
    add_network,\
    set_network 0 ca_cert \\\"/conf/pfatt/wpa/ca.pem\\\",\
    set_network 0 client_cert \\\"/conf/pfatt/wpa/client.pem\\\",\
    set_network 0 eap TLS,\
    set_network 0 eapol_flags 0,\
    set_network 0 identity \\\"$EAP_SUPPLICANT_IDENTITY\\\",\
    set_network 0 key_mgmt IEEE8021X,\
    set_network 0 phase1 \\\"allow_canned_success=1\\\",\
    set_network 0 private_key \\\"/conf/pfatt/wpa/private.pem\\\",\
    enable_network 0\
  "

  WPA_DAEMON_CMD="/usr/sbin/wpa_supplicant -Dwired -ingeth0 -B -C /var/run/wpa_supplicant"

  # kill any existing wpa_supplicant process
  PID=$(pgrep -f "wpa_supplicant.*ngeth0")
  if [ ${PID} > 0 ];
  then
    /usr/bin/logger -st "pfatt" "terminating existing wpa_supplicant on PID ${PID}..."
    RES=$(kill ${PID})
  fi

  # start wpa_supplicant daemon
  RES=$(${WPA_DAEMON_CMD})
  PID=$(pgrep -f "wpa_supplicant.*ngeth0")
  /usr/bin/logger -st "pfatt" "wpa_supplicant running on PID ${PID}..."

  # Set WPA configuration parameters.
  /usr/bin/logger -st "pfatt" "setting wpa_supplicant network configuration..."
  IFS=","
  for STR in ${WPA_PARAMS};
  do
    STR="$(echo -e "${STR}" | sed -e 's/^[[:space:]]*//')"
    RES=$(eval wpa_cli ${STR})
  done

  # wait until wpa_cli has authenticated.
  WPA_STATUS_CMD="wpa_cli status | grep 'suppPortStatus' | cut -d= -f2"
  IP_STATUS_CMD="ifconfig ngeth0 | grep 'inet\ ' | cut -d' ' -f2"

  /usr/bin/logger -st "pfatt" "waiting EAP for authorization..."

  # TODO: blocking for bootup
  while true;
  do
    WPA_STATUS=$(eval ${WPA_STATUS_CMD})
    if [ X${WPA_STATUS} = X"Authorized" ];
    then
      /usr/bin/logger -st "pfatt" "EAP authorization completed..."

      IP_STATUS=$(eval ${IP_STATUS_CMD})

      if [ -z ${IP_STATUS} ] || [ ${IP_STATUS} = "0.0.0.0" ];
      then
        /usr/bin/logger -st "pfatt" "no IP address assigned, force restarting DHCP..."
        RES=$(eval /etc/rc.d/dhclient forcerestart ngeth0)
        IP_STATUS=$(eval ${IP_STATUS_CMD})
      fi
      /usr/bin/logger -st "pfatt" "IP address is ${IP_STATUS}..."
      break
    else
      sleep 1
    fi
  done
  /usr/bin/logger -st "pfatt" "ngeth0 should now be available to configure as your WAN..."
  /usr/bin/logger -st "pfatt" "done!"
else
  /usr/bin/logger -st "pfatt" "error: unknown EAP_MODE. '$EAP_MODE' is not valid. exiting..."
  exit 1
fi
