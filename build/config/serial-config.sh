#!/bin/ash
# Enable getty on ttyS0 and add it to securetty so root login (if used)
# works on the serial console — required for cloud-style "console" access
# on OpenStack and Proxmox.
sed -i "s|^#ttyS0::|ttyS0::|" /etc/inittab
grep -q "^ttyS0$" /etc/securetty || echo "ttyS0" >> /etc/securetty
