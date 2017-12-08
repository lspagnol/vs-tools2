function snapshot
{
	
if [ "$1" == "help" ] ; then cat<<EOF

DESCRIPTION

	'snapshot' related functions

SUB-FUNCTIONS

	snapshotExists <pool (LV)>
	snapshotExistsQuiet <pool (LV)>
	snapshotNotExists <pool (LV)>

	snapshotCreate <pool (LV)> [options]
	snapshotDestroy <pool (LV)>

USAGE

	For help about sub-functions, use '<sub-function> help'

EOF
exit 1
fi

}

function snapshotExists
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	snapshotExists

SYNOPSIS

	snapshotExists <pool (LV)>

DESCRIPTION

	Check if snapshot exists for <pool (LV)>.

	Return code: 0 if success or log as error.

EOF
exit 1
fi

local pool=$1
poolExists $pool || return 1

local vg=${pool%/*}
[ -n "$vg" ] || { error "$E_102 ($pool)" ; return 1 ; }

local lv=${pool#*/}
[ -n "$lv" ] || { error "$E_102 ($pool)" ; return 1 ; }

local snap_name="snap.$lv"

lvs $vg/$snap_name 2>/dev/null >/dev/null || { error "$E_241" ; return 1 ; }

return 0

}

function snapshotNotExists
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	snapshotNotExists

SYNOPSIS

	snapshotNotExists <pool (LV)>

DESCRIPTION

	Check if snapshot doest not exists for <pool (LV)>.

	Return code: 0 if success or log as error.

EOF
exit 1
fi

local pool=$1
poolExists $pool || return 1

local vg=${pool%/*}
[ -n "$vg" ] || { error "$E_102 ($pool)" ; return 1 ; }

local lv=${pool#*/}
[ -n "$lv" ] || { error "$E_102 ($pool)" ; return 1 ; }

local snap_name="snap.$lv"

lvs $vg/$snap_name 2>/dev/null >/dev/null && { error "$E_242" ; return 1 ; }

return 0

}

function snapshotExistsQuiet
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	snapshotExists

SYNOPSIS

	snapshotExists <pool (LV)>

DESCRIPTION

	Check if snapshot exists for <pool (LV)>.

	Return code: 0 if success.

EOF
exit 1
fi

local pool=$1
poolExists $pool || return 1

local vg=${pool%/*}
[ -n "$vg" ] || { error "$E_102 ($pool)" ; return 1 ; }

local lv=${pool#*/}
[ -n "$lv" ] || { error "$E_102 ($pool)" ; return 1 ; }

local snap_name="snap.$lv"

lvs $vg/$snap_name 2>/dev/null >/dev/null || return 1

return 0

}

function snapshotCreate
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	snapshotCreate

SYNOPSIS

	snapshotCreate <pool (LV)> [options]

OPTIONS

	extents=<number of extents>

DESCRIPTION

	Create snapshot for <pool (LV)>.

	Return code: 0 if success.

EOF
exit 1
fi

local pool=$1
poolExists $pool || return 1
snapshotNotExists $pool || return 1

local vg=${pool%/*}
local lv=${pool#*/}
local snap_name="snap.$lv"

type=$(blkid -s TYPE /dev/$pool |cut -d"=" -f2 |sed -e 's/"//g ; s/ //g')
[ -n "$type" ] || { error "$E_209 ($pool)" ; return 1 ; }

local mount_point=$(cat /proc/mounts |grep "^/dev/$pool " |awk '{print $2}')

local extents
shift
while [ $? -eq 0 ] ; do # lecture des options
	eval $(echo $1 |egrep "^extents=") >/dev/null
	shift
done

local free_extents=($(vgs $vg --noheadings -o free_count))
[ -n "$free_extents" ] || { error "$E_214" ; return 1 ; }
[ $free_extents -ne 0 ] || { error "$E_215" ; return 1 ; }

extents=${extents:-$free_extents}

[ $free_extents -ge $extents ] || { error "$E_215" ; return 1 ; }

# Debut traitement LVM, mise en place verrou
logexec dotlockfile -p -r 1 -l /var/lock/vs-tools_snapshotCreate.lock || { error "$E_126" ; return 1 ; }

case $type in
	ext3)
		local mount_opts="${_VSTOOLS_MOUNT_OPTS}"
	;;
	xfs)
		# le volume est monte, il faut figer le filesystem

		### reduire la verbosite du noyau (sortie console)
		### printk="$(cat /proc/sys/kernel/printk)"
		### echo "5$(echo "$printk" |cut -c2-)" > /proc/sys/kernel/printk	

		local mount_opts="${_VSTOOLS_MOUNT_OPTS},nouuid"
		[ -n "$mount_point" ] && xfs_freeze -f $mount_point
	;;
esac

# Creation du snapshot -> plusieurs tentatives avant abandon
local count; for (( count=1; count<=${_VSTOOLS_SNAPSHOTS_ATTEMPS} ; count++ )) ; do

	log "$E_246 (${count}/${_VSTOOLS_SNAPSHOTS_ATTEMPS})"
	# Purge 'pagecache', 'dentries' et 'inodes'
	# http://www.pouf.org/archives/111-Feedback-sur-les-snapshots-LVM..html
	# http://www.linuxinsight.com/proc_sys_vm_drop_caches.html
	# -> indispensable sinon echec aleatoire pour 'lvcreate --snapshot'
	sync ; sleep 1
	echo 3 > /proc/sys/vm/drop_caches ; sleep 1

	# Creation snapshot -> sortie boucle si succes
	logexec lvcreate --snapshot --extent $extents --addtag $HOSTNAME --name $snap_name $pool && break
	
	# Nouvelle purge cache
	sync ; sleep 1
	echo 3 > /proc/sys/vm/drop_caches ; sleep 1

	# Echec -> suppression des 'residus' du snapshot
	log "$E_245"
	logexec logexec lvremove -f $vg/$snap_name

	sync
	sleep 1 ; echo 3 > /proc/sys/vm/drop_caches ; sleep 1
	
done

# Fin traitement LVM, suppression verrou
logexec dotlockfile -u /var/lock/vs-tools_snapshotCreate.lock

case $type in
	ext3)
		# RAS pour ext3
	;;
	xfs)
		### verbosite noyau initiale
		### echo "$printk" > /proc/sys/kernel/printk

		# le volume source est monte, il faut defiger le filesystem
		[ -n "$mount_point" ] && xfs_freeze -u $mount_point
	;;
esac

# Abandon si le snapshot n'a pas ete cree
lvs $vg/$snap_name 2>/dev/null >/dev/null || { error "$E_244" ; return 1 ; }

mkdir -p ${_VSTOOLS_SNAPSHOTS}/$pool
logexec mount -o $mount_opts -t $type /dev/$vg/$snap_name ${_VSTOOLS_SNAPSHOTS}/$pool

return 0

}

function snapshotDestroy
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	snapshotDestroy

SYNOPSIS

	snapshotDestroy <pool (LV)>

DESCRIPTION

	Destroy snapshot of <pool (LV)>.

	Return code: 0 if success.

EOF
exit 1
fi

local pool=$1
poolExists $pool || return 1
snapshotExists $pool || return 1

local vg=${pool%/*}
local lv=${pool#*/}
local snap_name="snap.$lv"

logexec dotlockfile -p -r 1 -l /var/lock/vs-tools_snapshotDestroy.lock || { error "$E_126" ; return 1 ; }

logexec umount ${_VSTOOLS_SNAPSHOTS}/$pool
logexec rmdir ${_VSTOOLS_SNAPSHOTS}/$pool
logexec lvremove -f $vg/$snap_name

logexec dotlockfile -u /var/lock/vs-tools_snapshotDestroy.lock

return 0

}
