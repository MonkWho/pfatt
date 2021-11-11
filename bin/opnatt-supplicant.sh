#!/usr/bin/env sh
#Required Config
# ===============
ONT_IF=""
RG_ETHER_ADDR=""
EAP_MODE="supplicant"

# Supplicant Config
# =================
EAP_SUPPLICANT_IDENTITY=""

##### DO NOT EDIT BELOW #################################################################################

/usr/bin/logger -st "pfatt" "starting pfatt..."
/usr/bin/logger -st "pfatt" "configuration:"
/usr/bin/logger -st "pfatt" "  ONT_IF = $ONT_IF"
/usr/bin/logger -st "pfatt" "  RG_ETHER_ADDR = $RG_ETHER_ADDR"
/usr/bin/logger -st "pfatt" "  EAP_MODE = $EAP_MODE"
/usr/bin/logger -st "pfatt" "  EAP_SUPPLICANT_IDENTITY = $EAP_SUPPLICANT_IDENTITY"

/usr/bin/logger -st "pfatt" "resetting netgraph..."
/usr/sbin/ngctl shutdown waneapfilter: 
/usr/sbin/ngctl shutdown laneapfilter: 
/usr/sbin/ngctl shutdown $ONT_IF: 
/usr/sbin/ngctl shutdown o2m: 
/usr/sbin/ngctl shutdown vlan0: 
/usr/sbin/ngctl shutdown ngeth0: 

/usr/bin/logger -st "pfatt" "configuring EAP environment for $EAP_MODE mode..."
/usr/bin/logger -st "pfatt" "cabling should look like this:"
/usr/bin/logger -st "pfatt" "  ONT---[] [$ONT_IF]$HOST"
/usr/bin/logger -st "pfatt" "creating vlan node and ngeth0 interface..."

#/usr/sbin/ngctl mkpeer $ONT_IF: vlan lower downstream
/usr/sbin/ngctl mkpeer em1: vlan lower downstream

#/usr/sbin/ngctl name $ONT_IF:lower vlan0
/usr/sbin/ngctl name em1:lower vlan0

/usr/sbin/ngctl mkpeer vlan0: eiface vlan0 ether
/usr/sbin/ngctl msg vlan0: 'addfilter { vlan=0 hook="vlan0" }'

/usr/sbin/ngctl msg ngeth0: set $RG_ETHER_ADDR

/usr/bin/logger -st "pfatt" "enabling promisc for $ONT_IF..."

/sbin/ifconfig $ONT_IF ether $RG_ETHER_ADDR
/sbin/ifconfig $ONT_IF up

/sbin/ifconfig $ONT_IF promisc

/usr/bin/logger -st "pfatt" "starting wpa_supplicant..."

WPA_DAEMON_CMD="/usr/sbin/wpa_supplicant -Dwired -i$ONT_IF -B -C /var/run/wpa_supplicant -c /conf/pfatt/wpa/wpa_supplicant.conf"

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
  echo $STR
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
