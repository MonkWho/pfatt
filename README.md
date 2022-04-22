# About

pfatt is a set of notes and scripts for setting up pfSense with AT&T U-Verse Fiber Internet. pfatt utilizes [netgraph](https://www.freebsd.org/cgi/man.cgi?netgraph(4)), which is a graph based kernel networking subsystem of FreeBSD to enable pfSense to fully manage the WAN address. This kernel-level solution was required to account for the unique issues surrounding bridging 802.1X traffic and/or transmitting 802.1Q Ethernet frames with the VLAN ID tag set to 0. pfatt does NOT enable theft of service, altering service speed or other malicious intent in any way.

# Introduction

I strongly advise reading this introduction, so you understand the background of how everything works. However, you can skip to the **Setup** section if you want to get to the point.

## Residential Gateway

AT&T currently offers a variety of residential gateways to their fiber customers. Depending on what was available at the time of your install, you may have one of these models:

- Motorola NVG589
- Arris NVG599
- Arris BGW210
- Pace 5268AC

While these gateways offer something called _IP Passthrough_, it does not provide the ability to fully utilize your own hardware. For example, the NAT table is still managed by the gateway, which is limited to a measly 8192 sessions on some models (and it becomes unstable at even 60% capacity).

pfatt will allow you to fully utilize your own router either by enabling true bridge mode or by bypassing the gateway completely. It should handle reboots, power/service outages,  re-authentications, IPv6, and new DHCP leases.

## How it Works

Before setting up pfatt, it's important to understand how the stock residential gateway authenticates and acquires its WAN address. This will make pfatt configuration and troubleshooting much easier.

### Stock Procedure

First, let's talk about what happens in the stock residential gateway setup (without pfatt). At a high level, the following process happens when the residential gateway boots up:

1. All traffic on the ONT is protected with [802.1X](https://en.wikipedia.org/wiki/IEEE_802.1X). So in order to talk to anything, the residential gateway must first perform the [EAP-TLS authentication procedure](https://tools.ietf.org/html/rfc5216). This process utilizes a unique keys and certificates that are hardcoded to authorized devices, like your residential gateway.
2. Once the authentication completes, your residential gateway will be to properly "talk" to the outside. However, all of your Ethernet frames will need to be transmitted with a VLAN ID tag of 0 before the internet gateway will respond.  VLAN 0 is a [Cisco feature](https://www.cisco.com/c/en/us/td/docs/ios-xml/ios/atm/configuration/15-mt/atm-15-mt-book/atm-vlan-prty-tag.html) extension of standard 802.1Q. (Thanks for pointing this out @devicelocksmith).
3. Once traffic is tagged as VLAN ID 0, your residential gateway then needs to request its public IPv4 address via DHCP. The MAC address in the DHCP request needs to match that of the MAC address that's assigned to your AT&T account.
4. After the DHCP lease is issued, the WAN setup is complete. Your LAN traffic is then NAT'd and routed to the outside.

### Bypass Procedure

To bypass your residential gateway to fully utilize OPNsense, we can emulate the above stock procedure by either two methods: bridging the 802.1X EAP-TLS authentication traffic or by utilizing the native [wpa_supplicant](https://www.freebsd.org/cgi/man.cgi?wpa_supplicant) client with valid certificates to perform the 802.1X EAP-TLS authentication. 

The bridge method is the easiest, but it requires the residential gateway to be powered on and connected to your OPNsense box during the authentication procedure. 

The supplicant method is more difficult, because it requires extracting valid certificates through the exploitation of known vulnerabilities or by dumping the flash of your residential gateway. However, it comes with the benefit of being able to give full network management to OPNsense (no residential gateway required to be connected at all, even at boot). It is also more stable and resilient to edge cases of reboots, outages, or other conditions.

#### Bridge Method  

If we connect our residential gateway and ONT to our OPNsense box, we can bridge the 802.1X EAP-TLS authentication traffic, tag our WAN traffic as VLAN ID 0, and request a public IPv4 via DHCP using a MAC address that matches our assigned residential gateway.

Unfortunately, there are some challenges with emulating this process. First, it's against RFC to bridge 802.1X traffic and it is not supported in FreeBSD. Second, tagging traffic as VLAN ID 0 is also not supported through the standard interfaces. 

This is where netgraph comes in. Netgraph allows you to break some rules and build the proper plumbing to make this work. So, our cabling looks like this:

```
Residential Gateway
[ONT Port]
  |
  |
[nic0] OPNsense [nic1] 
                 |
                 |
               [ONT]
              Outside
```

With netgraph, our procedure looks like this (at a high level):

1. The residential gateway initiates a 802.1X EAPOL-START packet.
2. The packet then is bridged through netgraph to the ONT interface.
3. If the packet matches an 802.1X type (which is does), it is passed to the ONT interface. If it does not, the packet is discarded. This prevents our residential gateway from initiating DHCP. We want OPNsense to handle that.
4. The AT&T RADIUS server should then see and respond to the EAPOL-START, which is passed back through our netgraph back to the residential gateway. At this point, the 802.1X EAP-TLS authentication should be continue and complete.
5. netgraph has also created an interface for us called `ngeth0`. This interface is connected to `ng_vlan` which is configured to tag all traffic as VLAN0 before sending it on to the ONT interface. 
6. OPNsense can then be configured to use `ngeth0` as the WAN interface.
7. Next, we spoof the MAC address of the residential gateway and request a DHCP lease on `ngeth0`. The packets get tagged as VLAN0 and exit to the ONT. 
8. Now the DHCP handshake should complete and we should be on our way!

#### Supplicant Method

Alternatively, if you have valid certs that have been extracted from an authorized residential gateway device, you can utilize the native wpa_supplicant client in OPNsense to perform 802.1X EAP-TLS authentication. 

I will also note that EAP-TLS authentication authorizes the device, not the subscriber. Meaning, any authorized device (NVG589, NVG599, 5268AC, BGW210, etc) can be used to authorize the link. It does not have to match the RG assigned to your account. For example, an NVG589 purchased of eBay can authorize the link. The subscriber's *service* is authorized separately (probably by the DHCP MAC and/or ONT serial number).

In supplicant mode, the residential gateway can be permanently disconnected. We will still use netgraph to tag our traffic with VLAN0. Our cabling then looks pretty simple:

```
Outside[ONT]---[nic0]OPNsense
```

With netgraph, the procedure also looks a little simpler:

1. netgraph has created an interface for us called `ngeth0`. This interface is connected to `ng_vlan` which is configured to tag all traffic as VLAN0 before sending it on to the ONT interface. 
2. wpa_supplicant binds to `ngeth0` and initiates 802.1X EAP-TLS authentication
3. OPNsense can then be configured to use `ngeth0` as the WAN interface.
4. Next, we spoof the MAC address of the residential gateway and request a DHCP lease on `ngeth0`. The packets get tagged as VLAN0 and exit to the ONT. 
5. Now the DHCP handshake should complete and we should be on our way!

Hopefully, that now gives you an idea of what we are trying to accomplish. See the comments and commands `bin/pfatt.sh` for details about the netgraph setup.

But enough talk. Now for the fun part!

# Setup

First, you need to decide which method to perform EAP authentication: bridge mode or supplicant mode.

Both methods effectively give you the same result, but each have their advantages and disadvantages. 

**Bridge EAP-TLS**

`EAP_MODE="bridge"`

✅ Easiest method

❌ Requires Residential Gateway to always be plugged in and on

❌ Authentication can be slower and less reliable

❌ The 5268AC model requires a hacky workaround

**Supplicant EAP-TLS**

`EAP_MODE="supplicant"`

✅ Residential Gateway can be permanently off and stored

✅ Fast and stable authentication

❌ May be difficult for some. Requires extracting valid certificates from a Residential Gateway

Pick a mode then proceed to confirming that you have your prerequisites.

## Prerequisites

* The MAC address of your assigned Residential Gateway
* pfSense 2.4.x 

For bridge mode:

* __three__ physical network interfaces on your pfSense server

For supplicant mode:

* __two__ physical network interfaces on your pfSense server
* The MAC address of your EAP-TLS Identity (which is the same as your residential gateway if you are using its certificates)
* Valid certificates to perform EAP-TLS authentication (see **Extracting Certificates**)

If you need a third NIC, you can buy this cheap USB 100Mbps NIC [from Amazon](https://amzn.to/2P0yn8k). It has the Asix AX88772 chipset, which is supported in FreeBSD with the [axe](https://www.freebsd.org/cgi/man.cgi?query=axe&sektion=4) driver. I've confirmed it works in my setup. The driver was already loaded and I didn't have to install or configure anything to get it working. 

Also, don't worry about the poor performance of USB or 100Mbps NICs. This third NIC will only send/receive a few packets periodically to authenticate your residential gateway. The rest of your traffic will utilize your other (and much faster) NICs.

Next, proceed to the appropriate installation section.

## Install

1. Grab this repo to your local machine.
```
git clone https://github.com/aus/pfatt
```
2. Next, edit all configuration variables in `pfatt.sh`.

1. Upload the pfatt directory to `/conf` on your pfSense box.
```
scp -r pfatt root@pfsense:/conf/
```
4. If you are using supplicant mode, upload your extracted certs (see **Extracting Certificates**) to `/conf/pfatt/wpa`. You should have three files in the wpa directory as such. You may also need to match the permissions.
```
[2.4.4-RELEASE][root@pfsense.knox.lan]/conf/pfatt/wpa: ls -al
total 19
drwxr-xr-x  2 root  wheel     5 Jan 10 16:32 .
drwxr-xr-x  4 root  wheel     5 Jan 10 16:33 ..
-rw-------  1 root  wheel  5150 Jan 10 16:32 ca.pem
-rw-------  1 root  wheel  1123 Jan 10 16:32 client.pem
-rw-------  1 root  wheel   887 Jan 10 16:32 private.pem
```
5. Edit your `/conf/config.xml` to include `<earlyshellcmd>/conf/pfatt/bin/pfatt.sh</earlyshellcmd>` above `</system>`. 

1. Connect cables
    - `$EAP_BRIDGE_IF` to Residential Gateway on the ONT port (not the LAN ports!)
    - `$ONT_IF` to ONT (outside)
    - `LAN NIC` to local switch (as normal)

1. Prepare for console access.
1. Reboot.
1. pfSense will detect new interfaces on bootup. Follow the prompts on the console to configure `ngeth0` as your pfSense WAN. Your LAN interface should not normally change. However, if you moved or re-purposed your LAN interface for this setup, you'll need to re-apply any existing configuration (like your VLANs) to your new LAN interface. pfSense does not need to manage `$EAP_BRIDGE_IF` or `$ONT_IF`. I would advise not enabling those interfaces in pfSense as it can cause problems with the netgraph.
1. In the webConfigurator, configure the  WAN interface (`ngeth0`) to DHCP using the MAC address of your Residential Gateway.

If everything is setup correctly, EAP authentication should complete. Netgraph should be tagging the WAN traffic with VLAN0, and your WAN interface is configured with a public IPv4 address via DHCP.

### Extracting Certificates

Certificates can be extracted by either the exploitation of the residential gateway to get a root shell or by desoldering and dumping the NAND. Public research and tools to do so are most available for the NVG589 and the NVG599.

#### Exploit

TODO

References
- https://www.devicelocksmith.com/2018/12/eap-tls-credentials-decoder-for-nvg-and.html
- https://www.nomotion.net/blog/sharknatto/
- https://github.com/MakiseKurisu/NVG589/wiki


#### Dumping the NAND

User @KhoasT posted instructions for dumping the NAND. See the comment on devicelocksmith's site [here](https://www.devicelocksmith.com/2018/12/eap-tls-credentials-decoder-for-nvg-and.html?showComment=1549236760112#c5606196700989186087).

### Notes on ng_etf 

If you do not trust my provided ng_etf kernel module (and you shouldn't because I am a random internet stranger), you can compile your own.

From another, trusted FreeBSD machine, run the following. _You cannot build packages directly on pfSense._ Your FreeBSD version should match that of your pfSense version. (Example: pfSense 2.4.4 = FreeBSD 11.2

```
    # from a FreeBSD machine (not pfSense!)
    fetch ftp://ftp.freebsd.org/pub/FreeBSD/releases/amd64/amd64/11.2-RELEASE/src.txz
    tar -C / -zxvf src.txz
    cd /usr/src/sys/modules/netgraph
    make
    scp etf/ng_etf.ko root@pfsense:/boot/kernel/
    ssh root@pfsense chmod 555 /boot/kernel/ng_etf.ko
```
**NOTE:** The `ng_etf.ko` in this repo was compiled for amd64 from the FreeBSD 11.2 release source code. It may also work on other/future versions of pfSense depending if there have been [significant changes](https://github.com/freebsd/freebsd/commits/master/sys/netgraph/ng_etf.c).  

**NOTE:** You'll need to tweak your compiler parameters if you need to build for another architecture, like ARM.

# IPv6 Setup

Once your netgraph setup is in place and working, there aren't any netgraph changes required to the setup to get IPv6 working. These instructions can also be followed with a different bypass method other than the netgraph method. Big thanks to @pyrodex1980's [post](http://www.dslreports.com/forum/r32118263-) on DSLReports for sharing your notes.

This setup assumes you have a fairly recent version of pfSense. I'm using 2.4.4.

**DUID Setup**

1. Go to _System > Advanced > Networking_
2. Configure **DHCP6 DUID** to _DUID-EN_
3. Configure **DUID-EN** to _3561_
4. Configure your **IANA Private Enterprise Number**. This number is unique for each customer and (I believe) based off your Residential Gateway serial number. You can generate your DUID using [gen-duid.sh](https://github.com/aus/pfatt/blob/master/bin/gen-duid.sh), which just takes a few inputs. Or, you can take a pcap of the Residential Gateway with some DHCPv6 traffic. Then fire up Wireshark and look for the value in _DHCPv6 > Client Identifier > Identifier_. Add the value as colon separated hex values `00:00:00`.
5. Save

**WAN Setup**

1. Go to _Interfaces > WAN_
1. Enable **IPv6 Configuration Type** as _DHCP6_
1. Scroll to _DCHP6 Client Configuration_
1. Enable **DHCPv6 Prefix Delegation size** as _60_
1. Enable _Send IPv6 prefix hint_
1. Enable _Do not wait for a RA_
1. Save

**LAN Setup**

1. Go to _Interfaces > LAN_
1. Change the **IPv6 Configuration Type** to _Track Interface_
1. Under Track IPv6 Interface, assign **IPv6 Interface** to your WAN interface.
1. Configure **IPv6 Prefix ID** to _1_. We start at _1_ and not _0_ because pfSense will use prefix/address ID _0_ for itself and it seems AT&T is flakey about assigning IPv6 prefixes when a request is made with a prefix ID that matches the prefix/address ID of the router.
1. Save

If you have additional LAN interfaces repeat these steps for each interface except be sure to provide an **IPv6 Prefix ID** that is not _0_ and is unique among the interfaces you've configured so far.

**DHCPv6 Server & RA**

1. Go to _Services > DHCPv6 Server & RA_
1. Enable DHCPv6 server on interface LAN
1. Configure a range of ::0001 to ::ffff:ffff:ffff:fffe
1. Configure a **Prefix Delegation Range** to _64_
1. Save
1. Go to the _Router Advertisements_ tab
1. Configure **Router mode** as _Stateless DHCP_
1. Save

That's it! Now your clients should be receiving public IPv6 addresses via DHCP6.

# Troubleshooting

## Logging

Output from `pfatt.sh` and `pfatt-5268AC.sh` can be found in `/var/log/pfatt.log`.

## tcpdump

Use tcpdump to watch the authentication, vlan and dhcp bypass process (see above). Run tcpdumps on the `$ONT_IF` interface and the `$RG_IF` interface:
```
tcpdump -ei $ONT_IF
tcpdump -ei $RG_IF
```

Restart your Residential Gateway. From the `$RG_IF` interface, you should see some EAPOL starts like this:
```
MAC (oui Unknown) > MAC (oui Unknown), ethertype EAPOL (0x888e), length 60: POL start
```

If you don't see these, make sure you're connected to the ONT port.

These packets come every so often. I think the RG does some backoff / delay if doesn't immediately auth correctly. You can always reboot your RG to initiate the authentication again.

If your netgraph is setup correctly, the EAP start packet from the `$RG_IF` will be bridged onto your `$ONT_IF` interface. Then you should see some more EAP packets from the `$ONT_IF` interface and `$RG_IF` interface as they negotiate 802.1/X EAP authentication.

Once that completes, watch `$ONT_IF` and `ngeth0` for DHCP traffic.
```
tcpdump -ei $ONT_IF port 67 or port 68
tcpdump -ei ngeth0 port 67 or port 68
```

Verify you are seeing 802.1Q (tagged as vlan0) traffic on your `$ONT_IF ` interface and untagged traffic on `ngeth0`. 

Verify the DHCP request is firing using the MAC address of your Residential Gateway.

If the VLAN0 traffic is being properly handled, next pfSense will need to request an IP. `ngeth0` needs to DHCP using the authorized MAC address. You should see an untagged DCHP request on `ngeth0` carry over to the `$ONT_IF` interface tagged as VLAN0. Then you should get a DHCP response and you're in business.

If you don't see traffic being bridged between `ngeth0` and `$ONT_IF`, then netgraph is not setup correctly. 

## Promiscuous Mode

`pfatt.sh` will put `$RG_IF` in promiscuous mode via `/sbin/ifconfig $RG_IF promisc`. Otherwise, the EAP packets would not bridge. I think this is necessary for everyone but I'm not sure. Turn it off if it's causing issues. 

## netgraph

The netgraph system provides a uniform and modular system for the implementation of kernel objects which perform various networking functions. If you're unfamiliar with netgraph, this [tutorial](http://www.netbsd.org/gallery/presentations/ast/2012_AsiaBSDCon/Tutorial_NETGRAPH.pdf) is a great introduction. 

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
3. Inspect the various nodes and hooks. Example for `ue0`:
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

Proxmox uses a bridged networking model, and thus utilizes Linux's native bridge capability. To use this netgraph method, you do a PCI passthrough for the `$RG_IF` and `$ONT_IF` NICs. The bypass procedure should then be the same.

You can also solve the EAP/802.1X and VLAN0/802.1Q problem by setting the `group_fwd_mask` and creating a vlan0 interface to bridge to your VM. See *Other Methods* below. 

## ESXi

I haven't tried to do this with ESXi. Feel free to submit a PR with notes on your experience. PCI passthrough is probably the best approach here though.

# Other Methods

## Linux

If you're looking how to do this on a Linux-based router, please refer to [this method](http://blog.0xpebbles.org/Bypassing-At-t-U-verse-hardware-NAT-table-limits) which utilizes ebtables and some kernel features.  The method is well-documented there and I won't try to duplicate it. This method is generally more straight forward than doing this on BSD. However, please submit a PR for any additional notes for running on Linux routers.

## VLAN Swap

There is a whole thread on this at [DSLreports](http://www.dslreports.com/forum/r29903721-AT-T-Residential-Gateway-Bypass-True-bridge-mode). The gist of this method is that you connect your ONT, RG and WAN to a switch. Create two VLANs. Assign the ONT and RG to VLAN1 and the WAN to VLAN2. Let the RG authenticate, then change the ONT VLAN to VLAN2. The WAN the DHCPs and your in business.

However, I don't think this works for everyone. I had to explicitly tag my WAN traffic to VLAN0 which wasn't supported on my switch. 

## OPNSense / FreeBSD

I haven't tried this with OPNSense or native FreeBSD, but I imagine the process is ultimately the same with netgraph. Feel free to submit a PR with notes on your experience.

# U-verse TV

See [issue #3](https://github.com/aus/pfatt/issues/3).

# References

- http://blog.0xpebbles.org/Bypassing-At-t-U-verse-hardware-NAT-table-limits
- https://forum.netgate.com/topic/99190/att-uverse-rg-bypass-0-2-btc/
- http://www.dslreports.com/forum/r29903721-AT-T-Residential-Gateway-Bypass-True-bridge-mode
- https://www.dslreports.com/forum/r32127305-True-Bridge-mode-on-pfSense-with-netgraph
- https://www.dslreports.com/forum/r32116977-AT-T-Fiber-RG-Bypass-pfSense-IPv6
- http://www.netbsd.org/gallery/presentations/ast/2012_AsiaBSDCon/Tutorial_NETGRAPH.pdf
- https://www.devicelocksmith.com/

# Credits

- [dls](https://www.devicelocksmith.com/) - for mfg_dat_decode and many other tips
- [rajl](https://forum.netgate.com/user/rajl) - for the netgraph idea
- [pyrodex](https://www.dslreports.com/profile/1717952) - for IPv6 notes
- [aus](https://github.com/aus) 

