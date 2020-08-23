#!/bin/sh
ascii2hex() { echo -n "$*" | awk 'BEGIN{for(n=0;n<256;n++)ord[sprintf("%c",n)]=n}{len=split($0,c,"");for(i=1;i<=len;i++)printf("%x",ord[c[i]])}'; }

printhexstring() { awk '{l=split($0,c,"");for(i=1;i<l-1;i=i+2)printf("%s:",substr($0,i,2));print(substr($0,l-1,2))}'; }

echo
echo "Step 1) RG information"
echo
while read -p "  Manufacturer [1=Pace, 2=Motorola/Arris]: " mfg; do
        ([ "$mfg" = "1" ] || [ "$mfg" = "2" ]) && break
done
while read -p "  Serial number: " serial; do [ -n "$serial" ] && break; done
echo

[ "$mfg" = "1" ] && mfg="00D09E" || mfg="001E46"
echo -n "Identifier: "
ascii2hex "$mfg-$serial" | printhexstring

cat << EOF

Step 2) Navigate to System->Advanced->Networking in webConfigurator.

IPv6 Options
    DHCP6 DUID: DUID-EN
    DUID-EN
        Enterprise Number: 3561
        Identifier: As shown above

Click Save.

Step 3) Navigate to Interfaces->WAN in webConfigurator.

General Configuration
    IPv6 Configuration Type: DHCP6
    MAC Address: Same as MAC address of RG

Other options are probably needed, so set those too.

Click Save. This will finally save dhcp6c's DUID file and start the client.

Step 4) Finished, hopefully.

Good luck!

EOF
