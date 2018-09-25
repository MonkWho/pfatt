# About

This repository includes my notes on enabling a true bridge mode setup with AT&T U-Verse and pfSense. I've tested and confirmed this setup with the ARRIS NVG589 and BGW210-700. There are a few other methods to accomplish this, so be sure to see what easiest for you. True Bridge Mode is also possible in a Linux via ebtables or using hardware with a VLAN swap trick. I did not have a Linux router and the VLAN swap did not seem to work for me.

While many residential gateways offer something called _IP Passthrough_, it does not provide the same advantages of a true bridge mode. For example, the NAT table is still managed by the gateway, which is limited to a measily 8192 sessions (although it becomes unstable at even 60% capacity).

This method will allow you to fully utilize your own router and finally solve that pesky NAT table limit.

# Quick Setup

## Prerequisites

* You need at least __three__ network interfaces on your pfSense server. 
* The MAC address of your Residential Gateway
* Local or console access to pfSense
* pfSense 2.4.3 _(confirmed working, other versions should work but YMMV)_

If you don't have three NICs, you can buy this cheap USB NIC one [from Amazon](TODO). I've confirmed it works in my setup. It is compatible with FreeBSD 11.1 and I didn't have to install anything to get it working. Also, don't worry about the poor performance of USB NICs. This third NIC will only send/recieve a few packets periodicaly to authenticate your Router Gateway. The rest of your traffic will utilize your other (and much faster) NICs.

## Install

1. Copy the `bin/ng_etf.ko` kernel module to `/boot/kernel` on your pfSense box (because it isn't included):

    a) Use the pre-compiled kernel module from me, a random internet stranger:
    ```
    scp bin/ng_etf.ko root@pfsense:/boot/kernel/
    ssh root@pfsense chmod 555 /boot/kernel/ng_etf.ko
    ```

    b) Or you, a responsible sysadmin, can compile the module yourself from another, trusted FreeBSD machine. _You cannot build packages directly on pfSense._ Your FreeBSD version should match that of your pfSense version. (Example: pfSense 2.4.3 = FreeBSD 11.1)
    ```
    # from a FreeBSD machine (not pfSense!)
    fetch ftp://ftp.freebsd.org/pub/FreeBSD/releases/amd64/amd64/11.1-RELEASE/src.txz
    tar -C / -zxvf src.txz
    cd /usr/src/sys/modules/netgraph
    make
    scp etf/ng_etf.ko root@pfsense:/boot/kernel/
    ssh root@pfsense chmod 555 /boot/kernel/ng_etf.ko
    ```

1. Edit the following configuration variables in `bin/pfatt.sh` as noted below. `$RG_ETHER_ADDR` should match the MAC address of your Residential Gateway. AT&T will only grant a DHCP lease to the MAC they assigned your device. In my environment, it's:
    ```shell
    ONT_IF='bce0' # NIC -> ONT / Outside
    RG_IF='ue0'  # NIC -> Residential Gateway's ONT port
    RG_ETHER_ADDR='xx:xx:xx:xx:xx:xx' # MAC address of Residential Gateway
    ```

1. Copy `bin/pfatt.sh` to `/usr/local/etc/rc.d` to enable it to run at boot:
    ```
    scp bin/pfatt.sh root@pfsense:/usr/local/etc/rc.d/
    ssh root@pfsense chmod +x /usr/local/etc/rc.d/pfatt.sh
    ```

1. Connect cables:
    - `$RG_IF` to Residiential Gateway on the ONT port (not the LAN ports!)
    - `$ONT_IF` to ONT (outside)
    - `LAN NIC` to local switch (as normal)

1. Prepare for console access.
1. Reboot.
1. pfSense will detect new interfaces on bootup. Follow the prompts on the console to configure `ngeth0` as your pfSense WAN. Your LAN interface should not change.
1. In the webConfigurator, configure the  WAN interface (`ngeth0`) to DHCP using the MAC address of your Residential Gateway.

If everything is setup correctly, netgraph should be bridging EAP traffic between the ONT and RG, tagging the WAN traffic with VLAN0, and your WAN interface configured with an IPv4 address via DHCP.

# IPv6 Setup

Once your netgraph setup is in place and working, there aren't any netgraph changes required to the setup to get IPv6 working. These instructions can also be followed with a different bypass method other than the netgraph method. Big thanks to @pyrodex1980's [post](http://www.dslreports.com/forum/r32118263-) on DSLReports for sharing your notes.

This setup assumes you have a fairly recent version of pfSense. I'm using 2.4.3.

**DUID Setup**

1. Go to _System > Advanced > Networking_
1. Configure **DHCP6 DUID** to _DUID-EN_
1. Configure **DUID-EN** to _3561_
1. Configure your **IANA Private Enterprise Number**. This number is unique for each customer and (I believe) based off your Residential Gateway serial number. I grabbed mine off a pcap of the Residential Gateway. Fire up Wireshark and look for the value in _DHCPv6 > Client Identifier > Identifier_. Add the value as colon separated hex values `00:00:00`.
1. Save

**WAN Setup**

1. Go to _Interfaces > WAN_
1. Enable **IPv6 Configuration Type** as _DHCP6_
1. Scroll to _DCHP6 Client Configuration_
1. Enable _Advanced Configuration_
1. Enable _Configuration Override_
1. Enable _Debug_
1. Enable _Do not wait for a RA_
1. Configure **Configuration File** to `/cf/conf/att_dhcp6.conf`
1. Save

**Configuration File**

1. Logon to your pfsense box and add the following file to `/cf/conf/att_dhcp6.conf` changing the WAN / LAN interface names to match your setup:
```
# WAN
interface ngeth0 {
        send ia-na 1;   # request stateful address
        send ia-pd 1;   # request prefix delegation - LAN
        request domain-name-servers;
};
id-assoc na 1 { };
id-assoc pd 1 {
        prefix ::/60 infinity;
        # LAN
        prefix-interface bce1 {
                sla-id 0;
                sla-len 4;
        };
};
```

**LAN Setup**

1. Go to _Interfaces > LAN_
1. Change the **IPv6 Configuration Type** to _Track Interface_
1. Under Track IPv6 Interface, assign **IPv6 Interface** to your WAN interface.
1. Configure **IPv6 Prefix ID** to _0_
1. Save

**DHCPv6 Server & RA**

1. Go to _Services > DHCPv6 Server & RA_
1. Enable DHCPv6 server on interface LAN
1. Configure a range of ::1000 to ::2000
1. Configure a **Prefix Delegation Range** to _64_
1. Add a few IPv6 DNS servers
1. Save
1. Go to the _Router Advertisements_ tab
1. Configure **Router mode** as _Stateless DHCP_
1. Save

That's it! Now your clients should be recieving public IPv6 addresses via DHCP6.

# Troubleshooting Netgraph

## tcpdump

You should run tcpdumps on the `$ONT_IF` interface and the `$RG_IF` interface:
```
tcpdump -ei $ONT_IF
tcpdump -ei $RG_IF
```

From the `$RG_IF` interface, you should see some EAPOL starts like this:
```
MAC (oui Unknown) > MAC (oui Unknown), ethertype EAPOL (0x888e), length 60: POL start
```

These packets come every so often. I think the RG does some backoff / delay if doesn't immediately auth correctly. You can always reboot your RG to initiate the authentication.

If your netgraph is setup correctly, the EAP start packet from the `$RG_IF` will be bridged onto your `$ONT_IF` interface. Then you should see some more EAP packets from the `$ONT_IF` interface and `$RG_IF` interface as they negotiate 802.1/X EAP authentication.

Once that completes, you should start seeing 802.1Q (tagged as vlan0) traffic on your `$ONT_IF ` interface.

Then, you can start another tcpdump on the `vlan0` interface to see if netgraph is bridging over the VLAN0 traffic to `ngeth0`:
```
tcpdump -ei ngeth0
```

If you don't see traffic being bridged between `ngeth0` and `$ONT_IF`, then netgraph is not  setup correctly. 

If the VLAN0 traffic is being properly handled, next pfSense will need to request an IP. `ngeth0` needs to DHCP using the authorized MAC address. You should see an untagged DCHP request on `ngeth0` carry over to the `$ONT_IF` interface tagged as VLAN0. Then you should get a DHCP response and you're in business.

## Promiscuous Mode

I had to put my `$RG_IF` in promiscuous mode with `/sbin/ifconfig $RG_IF promisc`. Otherwise, the EAP packets would not bridge. I'm not sure if this is due to my USB NIC or a requirement for everyone.

## netgraph

The netgraph system provides a uniform and modular system for the implementation of kernel objects which perform various networking functions. If you're unfamilar with netgraph, this [tutorial](http://www.netbsd.org/gallery/presentations/ast/2012_AsiaBSDCon/Tutorial_NETGRAPH.pdf) is a great introduction. 

Your netgraph should look something like this:

![netgraph](img/ngctl.png)

In this setup, the `ue0` interface is my `$RG_IF` and the `bce0` interface is my `$ONT_IF`. You can generate your own graphviz via `ngctl dot`. Copy the output and paste it at [webgraphviz.com](http://www.webgraphviz.com/).

Try these commands to inspect whether netgraph is configured properly.

1. Confirm kernel modules are loaded with `kldstat -v`. The following modules are required:
    - netgraph
    - ng_ether
    - ng_eiface
    - ng_one2many
    - ng_vlan
    - ng_etf

2. Issue `ngctl list` to list netgraph nodes. Inspect `pfatt.sh` to verify the netgraph output matches the configuration in the script. It should look similar to this:
```
$ ngctl list
There are 9 total nodes:
  Name: o2m             Type: one2many        ID: 000000a0   Num hooks: 3
  Name: vlan0           Type: vlan            ID: 000000a3   Num hooks: 2
  Name: ngeth0          Type: eiface          ID: 000000a6   Num hooks: 1
  Name: <unnamed>       Type: socket          ID: 00000006   Num hooks: 0
  Name: ngctl28740      Type: socket          ID: 000000ca   Num hooks: 0
  Name: waneapfilter    Type: etf             ID: 000000aa   Num hooks: 2
  Name: laneapfilter    Type: etf             ID: 000000ae   Num hooks: 3
  Name: bce0            Type: ether           ID: 0000006e   Num hooks: 1
  Name: ue0             Type: ether           ID: 00000016   Num hooks: 2
```
3. Inspect the node and hooks. Example for `ue0`:
```
$ ngctl show ue0:
  Name: ue0             Type: ether           ID: 00000016   Num hooks: 2
  Local hook      Peer name       Peer type    Peer ID         Peer hook
  ----------      ---------       ---------    -------         ---------
  upper           laneapfilter    etf          000000ae        nomatch
  lower           laneapfilter    etf          000000ae        downstream
```

### Reset netgraph

`pfatt.sh` expects a clean netgraph before it can be ran. To reset a broken netgraph state, try this:

```shell
/usr/sbin/ngctl shutdown waneapfilter:
/usr/sbin/ngctl shutdown laneapfilter:
/usr/sbin/ngctl shutdown $ONT_IF:
/usr/sbin/ngctl shutdown $RG_IF:
/usr/sbin/ngctl shutdown o2m:
/usr/sbin/ngctl shutdown vlan0:
/usr/sbin/ngctl shutdown ngeth0:
```

## pfSense

In some circumstances, pfSense may alter your netgraph. This is especially true if pfSense manages either your `$RG_IF` or `$ONT_IF`. If you make some interface changes and your connection breaks, check to see if your netgraph was changed.

# Virtualization Notes

This setup has been tested on physical servers and virtual machines. Virtualization adds another layer of complexity for this setup, and will take extra consideration.

## QEMU / KVM / Proxmox

Proxmox uses a bridged networking model, and thus utilizes Linux's native bridge capability. Unfortunately due to the two types of traffic we are bridging (EAP/802.1X and VLAN0/802.1Q), I could never get the traffic to forward through the Linux bridge to the virtual interface of my pfSense VM. Instead, I had to utilize PCI passthrough for my `$RG_IF` and `$ONT_IF` NICs. 

I believe EAP/802.1X just requires setting the `group_fwd_mask`, but I'm not sure how to get the VLAN0/802.1Q traffic to bridge. If you know why, please open an issue!

Alternatively, you can also do the EAP / VLAN0 magic at the Linux hypervisor layer. Apply the Linux method, then bridge the Linux vlan0 interface to your pfSense VM.

## ESXi

I haven't tried to do this with ESXi. Feel free to submit a PR with notes on your experience.

# Other Methods

## Linux

If you're looking how to do this on a Linux-based router, please refer to [this method](http://blog.0xpebbles.org/Bypassing-At-t-U-verse-hardware-NAT-table-limits) which utilizes ebtables and some kernel features.  The method is well-documented there and I won't try to duplicate it. This method is generally more straight forward than doing this on BSD. However, please submit a PR for any additional notes for running on Linux routers.

## VLAN Swap

There is a whole thread on this at [DSLreports](http://www.dslreports.com/forum/r29903721-AT-T-Residential-Gateway-Bypass-True-bridge-mode). The gist of this method is that you connect your ONT, RG and WAN to a switch. Create two VLANs. Assign the ONT and RG to VLAN1 and the WAN to VLAN2. Let the RG authenticate, then change the ONT VLAN to VLAN2. The WAN the DHCPs and your in business.

However, I don't think this works for everyone. I had to explicity tag my WAN traffic to VLAN0 which wasn't supported on my switch. 

## OPNSense / FreeBSD

I haven't tried this with OPNSense or native FreeBSD, but I imagine the process is the same with netgraph. Feel free to submit a PR with notes on your experience.

# U-verse TV

TODO

# References

- http://blog.0xpebbles.org/Bypassing-At-t-U-verse-hardware-NAT-table-limits
- https://forum.netgate.com/topic/99190/att-uverse-rg-bypass-0-2-btc/
- http://www.dslreports.com/forum/r29903721-AT-T-Residential-Gateway-Bypass-True-bridge-mode
- http://www.netbsd.org/gallery/presentations/ast/2012_AsiaBSDCon/Tutorial_NETGRAPH.pdf

# Credits

This took a lot of testing and a lot of hours to figure out. A unique solution was required for this to work in pfSense. If this helped you out, please buy us a coffee.

- rajl - 1H8CaLNXembfzYGDNq1NykWU3gaKAjm8K5
- [aus](https://github.com/aus) - 31m9ujhbsRRZs4S64njEkw8ksFSTTDcsRU
