function scsi
{

if [ "$1" == "help" ] ; then cat<<EOF

DESCRIPTION

	'scsi' related functions

SUB-FUNCTIONS

	scsiScanLUNs
	scsiScanFC
	scsiScanLVM

	scsiShowLUNs
	scsiShowFC
	scsiShowLVM

USAGE

	For help about sub-functions, use '<sub-function> help'

EOF
exit 1
fi

}

function scsiScanFC
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	scsiScanFC

SYNOPSIS

	scsiScanFC

DESCRIPTION

	Force rescan of FC buses.

	Return code: 0 if success.

EOF
exit 1
fi

if [ -d /sys/class/fc_host ] ; then
	local fc_hosts=$(ls /sys/class/fc_host)
	local fc_host ; for fc_host in $fc_hosts ; do
			if grep "^unknown$" /sys/class/fc_host/$fc_host/speed 2>/dev/null >/dev/null ; then
				# vitesse inconnue -> pas de lien sur le SAN
				log "no link on FC host '$fc_host'"
			else
				# purge des caches
				echo 3 > /proc/sys/vm/drop_caches
				# reinitialisation du port FC
				echo 1 > /sys/class/fc_host/$fc_host/issue_lip
			fi
	done
fi

return 0

}

function scsiScanLUNs
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	scsiScanLUNs

SYNOPSIS

	scsiScanLUNs

DESCRIPTION

	Force scanning of LUNs.

	Return code: 0 if success.

EOF
exit 1
fi

logexec scsiShowLUNs

local host device

for host in $(ls /sys/class/scsi_host/) ; do
	echo "- - -">/sys/class/scsi_host/$host/scan
	for device in $(ls /sys/class/scsi_disk/ |grep ^${host/host/}) ; do
		echo 1 > /sys/class/scsi_disk/$device/device/rescan
	done
done

logexec scsiShowLUNs

return 0

}

function scsiShowLUNs
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	scsiShowLUNs

SYNOPSIS

	scsiShowLUNs

DESCRIPTION

	Show disk devices.

	Return code: 0 if success.

EOF
exit 1
fi

local host device

echo "LUN	Vendor		Model			Dev	Block"
for host in $(ls /sys/class/scsi_host/) ; do
	for device in $(ls /sys/class/scsi_disk/ |grep ^${host/host/}) ; do
		echo "$device\
	$(cat /sys/class/scsi_disk/$device/device/vendor)\
	$(cat /sys/class/scsi_disk/$device/device/model)\
	$(ls /sys/class/scsi_disk/$device/device |grep ^block: |sed -e s/^block://g)\
	$(cat /sys/class/scsi_disk/$device/device/block:*/dev)"
		done
done

return 0

}

function scsiShowFC
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	scsiShowFC

SYNOPSIS

	scsiShowFC

DESCRIPTION

	Show WWN of FC buses.

	Return code: 0 if success.

EOF
exit 1
fi

local host

echo "HOST	WWN			State	Speed"
for host in $(ls /sys/class/fc_host/) ; do
	echo "$host\
	$(cat /sys/class/fc_host/$host/port_name)\
	$(cat /sys/class/fc_host/$host/port_state)\
	$(cat /sys/class/fc_host/$host/speed)"
done

return 0

}

function scsiScanLVM
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	scsiScanLVM

SYNOPSIS

	scsiScanLVM

DESCRIPTION

	Force scanning of LVM components, refresh multipath if required.

	Return code: 0 if success.

EOF
exit 1
fi

if ps ax |grep " /sbin/multipathd$" >/dev/null ; then
	#logexec dmsetup remove_all
	#logexec multipath -F
	logexec /etc/init.d/multipath-tools restart
fi

[ -f /etc/lvm/cache/.cache ] && rm /etc/lvm/cache/.cache

logexec scsiShowLVM

logexec pvscan
logexec vgscan
logexec lvscan

logexec scsiShowLVM

return 0

}

function scsiShowLVM
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	scsiShowLVM

SYNOPSIS

	scsiShowLVM

DESCRIPTION

	Show LVM components.

	Return code: 0 if success.

EOF
exit 1
fi

pvs |sed -e "s/^ *//g"
echo

vgs |sed -e "s/^ *//g"
echo

lvs -o +tags,kernel_major,kernel_minor |sed -e "s/^ *//g"

if ps ax |grep " /sbin/multipathd$" >/dev/null ; then
	echo
	multipath -v2 -ll
	echo
	multipath -ll -v3 |grep tgt_node_name
fi

return 0

}
