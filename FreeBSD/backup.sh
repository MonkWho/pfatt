#!/bin/csh
#Script to grab all relevant configuration files and installed packages, and back it up to github
/usr/sbin/pkg prime-origins > /root/fw/pkg_prime-origins

foreach i ( "/boot/loader.conf" "/etc/pf.conf" "/etc/rc.conf" "/etc/start_if.eth0" "/usr/local/etc/dhcpd.conf" "/usr/local/etc/namedb/named.conf" "/usr/local/etc/namedb/dynamic/example.com.db" "/var/cron/tabs/root" "/usr/local/etc/dhcp6c.conf" "/etc/rtadvd.conf" "/usr/local/etc/dhcpd6.conf" "/etc/dhclient.conf" )
	echo "Backing up "$i
	/bin/cp $i /root/fw$i
end

echo "git push"
cd /root/fw/
/usr/local/bin/git add .
/usr/local/bin/git commit -S -m "nightly backup"
/usr/local/bin/git push -u origin main
