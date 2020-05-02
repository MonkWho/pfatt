# U-verse TV 

If you have a U-verse TV subscription, you will need to perform some additional setup in order to get it working with your new pfSense system in-line with the residential gateway (RG).

## Preface

This guide was intially written by [0xC0ncord](https://github.com/0xC0ncord) in conjunction with the setup detailed by [/u/MisterBazz](https://www.reddit.com/r/PFSENSE/comments/ag43rb/att_bgw210_true_independent_bridge_mode_uverse/) and my personal experience in getting this entire setup working properly. The reason why I am mentioning this is to ~~shamelessly credit myself~~ make note that [aus had previously stated he does not have a TV subscription](https://github.com/aus/pfatt/issues/3#issue-362961147) at the time of writing and that there may be a disconnect between my point of view and his. Therefore, I want to point out that this portion of the guide is a community effort, and if you run into any issues or need assistance even after [troubleshooting](#Troubleshooting), please do not be afraid to ask for support.

## Overview / Prerequisites

Bypassing your AT&T residential gateway (RG) for U-verse TV is mostly straightforward (albeit sometimes a pain) from here on, but there is one major consideration that needs to be addressed.

U-verse TV streams are received through both IPv4 unicast and multicast streams. When selecting a channel through the Digital Video Receiver (DVR), the DVR will request the channel video stream while simultaneously sending an IGMP membership report and will receive the unicast stream for approximately 10 seconds before seamlessly switching to multicast. The amount of bandwidth consumed by the digital video stream for TV in general is a force to be reckoned with, and depending on how you choose to proceed with the setup may introduce noticeable network degradation. Because of the way IPv4 multicast traffic operates, you will end up in a situation where digital video traffic is being propogated throughout your network in ways that may not be desireable.To quote [/u/MisterBazz](https://www.reddit.com/r/PFSENSE/comments/ag43rb/att_bgw210_true_independent_bridge_mode_uverse/) on where I obtained most of this documentation, "it is way easier to set up a whole separate U-verse LAN than to pump all of this through your switch and configure the switch appropriately. It also makes it easy in setting up firewall rules as well."

For this guide, there are two paths to take:
1. Isolate the DVR on its own internal network (recommended).
2. Keep the DVR on the same internal LAN.

The prerequisites and so forth for each of these are documented below in their respective sections. Personally, I chose to put the DVR in its own network and so I cannot say for sure whether not doing so would actually result in noticeable network degradation, but your mileage may vary depending on your setup.

In summary, these are the basic steps performed by the DVR when selecting a channel to watch:
1. The DVR requests the unicast stream and sends an IGMP membership report for the desired channel.
2. The DVR begins playing the unicast stream and waits for the multicast stream.
3. The DVR begins receiving the multicast stream and stops receiving the unicast stream after approximately 10 seconds of video output.
4. Periodically, the DVR receives an IGMP general membership query from AT&T's network and will respond with another IGMP membership report while the channel is still being watched.

If the DVR were to change channels, it sends an IGMP leave group message for the current channel and repeats the steps above for the new channel.

On a final note, you need to ensure that the U-verse TV DVR you have supports IP video input. At the time of writing, I was unable to find any documentation of any sort of U-verse DVR that did not support this, especially since the manuals for them did not explicitly say so. In my case, I had an AT&T/Motorola VIP 2250, which was previously receiving video via a coaxial cable plugged into the back of the residential gateway before doing this setup. The manual for this particular DVR documents the RJ45 port on the back of the device but states it is for output and says nothing about input. After a little Google-fu I just barely confirmed my suspicious that this port could also be used for video input, but your DVR may be different if you have a different model.

With all that mess out of the way, let's get started!

## Setup

Refer to the above two paths and pick whichever works for you.

### Isolate the DVR on its Own Internal Network (Recommended)

#### Prerequisites

Since we will be plugging the DVR more or less directly into your pfSense box, you will need an additional physical interface. If you followed the rest of the pfatt guide, this brings the total number of required interfaces to **4**. Obviously, this means you must also have a way to physically connect the RJ45 port on your DVR to the interface on your pfSense box. The coaxial port on your DVR will no longer be needed if you were using it previously.

#### Setup

1. Re-cable your DVR.
    - Start by unplugging the coaxial cable from the back of the DVR if you are using it. You may as well unplug the coaxial cable from the back of your residential gateway as well.
    - Connect your DVR to your pfSense box using the RJ45 port on the back next to the coaxial port.
2. Configure the UVerseDVR interface.
    1. On pfSense, navigate to _Interfaces > Interface Assignments_
    2. Under **Available network ports** find and add the interface you connected your DVR to. Take note of the name it is added as.
    3. Navigate to the interface's configuration by going to _Interfaces > (Newly created interface)_
    4. Change the interface's description to something more meaningful. I chose `UverseDVR`
    5. Ensure that **Enable** is checked.
    6. Set your pfSense's static IPv4 address for this new interface under **Static IPv4 Configuration**. This should be an RFC 1918 address that is not already in use on any other LAN in your network. You should also keep the size of the network relatively small. I chose `10.5.5.1/29`.
    7. Hit **Save**
3. Configure the DHCP server on the DVR interface.
    1. Navigate to _Services > DHCP Server_
    2. Select the DVR interface tab.
    3. Check **Enable**
    4. Configure the DHCP address range in **Range**. Make sure this range is inside the network you allocated in step 2-6. I chose `10.5.5.2` - `10.5.5.5`
    5. Enter AT&T's DNS servers in **DNS Servers** (optional but highly recommended):
        - `68.94.156.1`
        - `68.94.157.1`
        (These may be different depending on your location)
    6. Hit **Save**
4. Configure the IGMP Proxy.
    1. Navigate to _Services > IGMP Proxy_
    2. Check **Enable IGMP**
    3. Click **Add**
    4. Select your WAN interface under **Interface**
    5. Enter a meaningful description if you so choose. I used `U-verse IPTV`
    6. Set **Type** to `Upstream interface`
    7. For _Networks_, enter `0.0.0.1/1`
    8. Hit **Save**
    9. Click **Add**
    10. Select your DVR interface under **Interface**
    11. Enter a meaningful description if you so choose. I used `U-verse IPTV`
    12. Set **Type** to `Downstream interface`
    13. For **Networks**, enter the network you created in step 2-6. I chose `10.5.5.0/29`
    14. Hit **Save**
5. Configure the firewall.
    1. Navigate to _Firewall > Rules_
    2. Select the _Floating_ tab.
    3. Create a rule as follows:
        - **Action**: `Pass`
        - **Quick**: `Checked`
        - **Interface**: `WAN, UverseDVR`
        - **Protocol**: `Any`
        - **Destination**: `Network` `224.0.0.0/8`
        - **Description**: `Allow multicast to U-verse IPTV`
        - **Allow IP options**: `Checked`
    4. Create another rule as follows:
        - **Action**: `Pass`
        - **Quick**: `Checked`
        - **Interface**: `WAN, UverseDVR`
        - **Protocol**: `Any`
        - **Destination**: `Network` `239.0.0.0/8`
        - **Description**: `Allow multicast to U-verse IPTV`
        - **Allow IP options**: `Checked`
    5. Save and apply your new rules.

If you made it this far your new setup should be complete!

### Keep the DVR on the Same Internal LAN

#### Prerequisites

If you were previously using the coaxial port on your DVR to connect it to your residential gateway, you will need to now connect your DVR to your LAN using the RJ45 next to it. The coaxial port on your DVR will no longer be needed if you were using it.

#### Setup
1. Re-cable your DVR.
    - Start by unplugging the coaxial cable from the back of the DVR if you are using it. You may as well unplug the coaxial cable from the back of your residential gateway as well.
    - Connect your DVR to your LAN using the RJ45 port on the back next to the coaxial port.
2. Create a static DHCP lease for the DVR.
    1. Go to _Services > DHCP Server > LAN_
    2. Under **DHCP Static Mappings for this Interface** choose **Add**
    3. Enter your DVR's MAC address in **MAC Address**
    4. Assign some IP address to the DVR in **IP Address**. It **must** be an IPv4 address.
    5. Enter AT&T's DNS servers in **DNS Servers** (optional but highly recommended):
        - `68.94.156.1`
        - `68.94.157.1`
        (These may be different depending on your location.)
    6. Hit **Save**
3. Configure the IGMP Proxy.
    1. Navigate to _Services > IGMP Proxy_
    2. Check **Enable IGMP**
    3. Click **Add**
    4. Select your WAN interface under **Interface**
    5. Enter a meaningful description if you so choose. I used `U-verse IPTV`
    6. Set **Type** to `Upstream interface`
    7. For **Networks**, enter `0.0.0.1/1`
    8. Hit **Save**
    9. Click **Add**
    10. Select your LAN interface under **Interface**
    11. Enter a meaningful description if you so choose. I used `U-verse IPTV`
    12. Set **Type** to `Downstream interface`
    13. For **Networks**, enter the network address in CIDR notation of your LAN.
    14. Hit **Save**
4. Configure the firewall.
    1. Navigate to _Firewall > Rules_
    2. Select the _Floating_ tab.
    3. Create a rule as follows:
        - **Action**: `Pass`
        - **Quick**: `Checked`
        - **Interface**: `WAN, LAN`
        - **Protocol**: `Any`
        - **Destination**: `Network` `224.0.0.0/8`
        - **Description**: `Allow multicast to U-verse IPTV`
        - **Allow IP options**: `Checked`
    4. Create another rule as follows:
        - **Action**: `Pass`
        - **Quick**: `Checked`
        - **Interface**: `WAN, LAN`
        - **Protocol**: `Any`
        - **Destination**: `Network 239.0.0.0/8`
        - **Description**: `Allow multicast to U-verse IPTV`
        - **Allow IP options**: `Checked`
    5. Save and apply your new rules.

If you made it this far your new setup should be complete!

## Troubleshooting

### My DVR isn't getting any channels!

Make sure that your DVR has a proper connection to the internet. Double-check your configuration and make sure that the DVR is allowed to receive traffic.

### I can select a channel and watch it, but after about 10 seconds the TV goes black or the video freezes!

This means your DVR isn't able to receive the multicast video stream. Recall that the first 10 seconds of watching a new channel are done via unicast while the DVR simultaneously requests IGMP membership, and then after about 10 seconds you should start seeing multicast traffic passing through your firewall. If you don't see multicast traffic at all, make sure that your IGMP proxy is setup correctly. It's possible that the server sending the video stream is not receiving your DVR's IGMP membership request. If you *do* see the multicast traffic, double-check your firewall rules and make sure that multicast traffic is allowed to pass and that it can reach the DVR.

## Afterthoughts

For the purposes of this guide, when configuring the upstream networks for the IGMP proxy, we entered `0.0.0.1/1`, when in fact this is just a catch-all for a majority of the IPv4 address space. While I was still doing my initial research on the proper setup for this, I could not find a definitive list of source IP addresses that AT&T's U-verse TV streams seem to come from, and other sources claimed there were just too many. The proper configuration for this would be to enter each of those networks/addresses, but I simply could not get an accurate list of them. If you're reading this and you would like to share your findings, please consider submitting an issue or pull request to edit this documentation.

If you did not isolate your DVR on its own network in your setup, you may need to configure additional network devices on your LAN if you have any. Since multicast traffic is now propogating throughout your LAN, if you are able to, you should do what is possible to limit the areas of your network where this traffic is allowed to propogate, especially if it is not needed except towards the DVR. This is especially true for wireless networks. Unfortunately, the exact procedures for doing this for each network device vary from vendor to vendor and are far beyond the scope of this guide, but the end goal is to simply disallow multicast traffic from passing through devices and into areas of the network where it is not needed.
