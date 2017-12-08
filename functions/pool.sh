function pool
{

if [ "$1" == "help" ] ; then cat<<EOF

DESCRIPTION

	'pool' related functions

SUB-FUNCTIONS

	poolExists
	poolExistsQuiet
	poolNotExists

	poolEnable
	poolDisable

	poolStart
	poolStop

	poolCreate
	poolDestroy

	poolList
	poolVserversList

	poolGrow

	poolCatch

USAGE

	For help about sub-functions, use '<sub-function> help'

EOF
exit 1
fi

}

function poolExists
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	poolExists

SYNOPSIS

	poolExists <pool>

DESCRIPTION

	Check if <pool> exists on this node.

	Return code: 0 if success or log as error.

EOF
exit 1
fi

local pool=$1
[ -n "$pool" ] || { error "$E_200" ; return 1 ; }

echo "$pool" |grep "/" >/dev/null || { error "$E_102 ($pool)" ; return 1 ; }
lvs $pool 2>/dev/null >/dev/null || { error "$E_201 ($pool)" ; return 1 ; }

return 0

}

function poolNotExists
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	poolNotExists

SYNOPSIS

	poolNotExists <pool>

DESCRIPTION

	Check if <pool> not exists on this node.

	Return code: 0 if success or log as error.

EOF
exit 1
fi

local pool=$1
[ -n "$pool" ] || { error "$E_200" ; return 1 ; }
log "pool -> $pool"

echo "$pool" |grep "/" >/dev/null || { error "$E_102 ($pool)" ; return 1 ; }
lvs $pool 2>/dev/null >/dev/null && { error "$E_202 ($pool)" ; return 1 ; }

return 0

}

function poolExistsQuiet
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	poolExistsQuiet

SYNOPSIS

	poolExists <pool>

DESCRIPTION

	Check if <pool> exists on this node.

	Return code: 0 if success.

EOF
exit 1
fi

local pool=$1
[ -n "$pool" ] || { error "$E_200" ; return 1 ; }

echo "$pool" |grep "/" >/dev/null || { error "$E_102 ($pool)" ; return 1 ; }
lvs $pool 2>/dev/null >/dev/null || return 1

return 0

}

function poolList
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	poolList

SYNOPSIS

	poolList

DESCRIPTION

	Show list of all pools (LV) seen on this node.

	Return code: 0 if success.

EOF
exit 1
fi

printf "%-6s %-8s %-15s %-s\n" ATTR SIZE TAG POOL $(lvs --noheadings -o lv_attr,lv_size,lv_tags,vg_name,lv_name |awk '{print $1" "$2" "$3" "$4"/"$5}')

return $?

}

function poolVserversList
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	poolVserversList

SYNOPSIS

	poolVserversList <pool> [options]

OPTIONS

	node=<node>
	
DESCRIPTION

	Get vservers list of <pool> (LV) seen on local or remote node if
	if specified.

	Return code: 0 if success.

EOF
exit 1
fi

local pool=$1
poolExists $pool || return 1

# Lecture de l'option 'node'
eval local $(echo $2 |egrep "^node=") >/dev/null

if [ -n "$node" ] ; then
	# Le noeud est specifie: lecture a partir du cache du cluster
	dirExists ${_VSTOOLS_CACHE}/cluster/$node/conf || return 1
	cd ${_VSTOOLS_CACHE}/cluster/$node/conf
else
	cd ${_VSERVERS_CONF}
fi

grep -l "^$pool$" */pool 2>/dev/null |sed -e "s/\/pool//g"

return 0
	
}

function poolGetOwner
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	poolGetOwner

SYNOPSIS

	poolGetOwner <pool>

DESCRIPTION

	Get owner (node) of <pool>.

	Return code: 0 if success.

EOF
exit 1
fi

local pool=$1
poolExists $pool || return 1

local owner
owner=($(lvs --noheadings -o tags $pool 2>/dev/null))

[ -n "$owner" ] || { error "$E_216 ($pool)" ; return 1 ; }

echo $owner

return 0

}

function poolCatch
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	poolCatch

SYNOPSIS

	poolCatch <pool>

DESCRIPTION

	Set pool (LV) tag as hostname, and get associated vservers
	configuration from cache.

	Return code: 0 if success.

EOF
exit 1
fi

local pool=$1
poolExists $pool || return 1

local node=$(poolGetOwner $pool) || return 1

# Le noeud doit etre declare dans la configuration
echo " ${_NODES} " |sed -e "s/,/ /g" |grep " $node " >/dev/null || { error "$E_181 ($node)" ; return 1 ; }

# Le noeud doit etre present dans le cache, meme s'il ne contient aucun vserveur
dirExists ${_VSTOOLS_CACHE}/cluster/$node/conf || return 1

# Lecture de l'etat du noeud local et distant
eval $(clusterHeartbeatRead $HOSTNAME |egrep "^hb_health=") # local
eval $(clusterHeartbeatHealth $node |egrep "^hb_node_alive=|^hb_pools_enabled=") # distant

# Le noeud local doit etre operationnel
[ $hb_health -eq 1 ] || { error "$E_184 ($HOSTNAME)" ; return 1 ; }

# Le pool ne doit pas etre utilise si le noeud distant fonctionne
if [ $hb_node_alive -eq 1 ] ; then
	if [ "$(echo " $hb_pools_enabled " |grep " $pool ")" ] ; then
		error "$E_208 ($pool @ $node)"
		return 1
	fi
fi

# Modification du tag LVM
logexec lvchange --deltag $node $pool || { error "$E_210 ($pool @ $node)" ; return 1 ; }
logexec lvchange --addtag $HOSTNAME $pool || { error "$E_211 ($pool @ $HOSTNAME)" ; return 1 ; }

# Mise a jour du cache
clusterCollector nodes=$node

# Construction de la liste des vserveurs du pool a partir du cache
local vservers=$(poolVserversList $pool node=$node)

local vserver
for vserver in $vservers ; do
	rsync -aq ${_VSTOOLS_CACHE}/cluster/$node/conf/$vserver/ ${_VSERVERS_CONF}/$vserver/
done

return 0

}

function poolEnable
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	poolEnable

SYNOPSIS

	poolEnable <pool>

DESCRIPTION

	Enable and mount pool (LV) on this node.

	Return code: 0 if success.

EOF
exit 1
fi

local pool=$1
poolExists $pool || return 1

dirExists ${_VSTOOLS_BASE} || return 1

local mnt=$(cat /proc/mounts |awk '{print $2}')
echo "$mnt" |grep "^${_VSTOOLS_BASE}/$pool$" > /dev/null

[ $? -eq 0 ] && return 0 # volume deja monte => rien a faire

# Activation du volume
logexec lvchange -ay $pool || return 1

# Creation point de montage
[ -d ${_VSTOOLS_BASE}/$pool ] || logexec mkdir -p ${_VSTOOLS_BASE}/$pool

# Montage du pool
logexec mount -o ${_VSTOOLS_MOUNT_OPTS} /dev/$pool ${_VSTOOLS_BASE}/$pool

return 0

}

function poolDisable
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	poolDisable

SYNOPSIS

	poolDisable <pool>

DESCRIPTION

	Disable and umount pool (LV) on this node.

	Return code: 0 if success.

EOF
exit 1
fi

local pool=$1
poolExists $pool || return 1

local mnt=$(cat /proc/mounts |awk '{print $2}')
echo "$mnt" |grep "^${_VSTOOLS_BASE}/$pool$" > /dev/null

[ $? -eq 0 ] || return 0 # volume pas monte => rien a faire

# Verification de l'etat des vserveurs du pool
local vservers=$(ls ${_VSTOOLS_BASE}/$pool 2>/dev/null |sed -e "s/lost+found//g")
local vserver ; for vserver in $vservers ; do
	vmIsStopped $vserver || return 1
done

# Demontage
logexec umount ${_VSTOOLS_BASE}/$pool || return 1
logexec rmdir ${_VSTOOLS_BASE}/$pool || return 1

# Desactivation du volume
logexec lvchange -an $pool || return 1

return 0
	
}

function poolCreate
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	poolCreate

SYNOPSIS

	poolCreate <pool name> [options]

OPTIONS

	lv_size=<pool (LV) size[M|G|T]>
	fs_type=<${_VSTOOLS_KNOWN_FS_TYPES//,/|}>

DESCRIPTION

	Create new storage pool. A pool is a LVM logical volumes, so
	'pool name' is in fact 'vg_name/lv_name'.
	
	Volume group MUST exists:
		pvcreate /dev/<device>
		vgcreate <vg name> /dev/<device>

	Pools are mounted under '${_VSTOOLS_BASE}/vg_name/pool' path

	Optional value will replace default from
	file '${_VSTOOLS_CONF}/build.cf':
	lv_size		-> ${_DEFAULT_LV_SIZE}
	fs_type		-> ${_DEFAULT_FS_TYPE}

	Notes: - online extending of ext3|xfs filesystems is possible,
	       - offline reducing of ext3 filesystems is possible,
	       - reducing of xfs filesystem is impossible.

	Return code: 0 if success.

EOF
exit 1
fi

local pool=$1
poolNotExists $pool || return 1
dirNotExists ${_VSTOOLS_BASE}/$pool || return 1

local vg=${pool%/*}
[ -n "$vg" ] || { error "$E_102 ($pool)" ; return 1 ; }

local lv=${pool#*/}
[ -n "$lv" ] || { error "$E_102 ($pool)" ; return 1 ; }

vgs $vg 2>/dev/null >/dev/null || { error "$E_102 ($pool -> VG not found)" ; return 1 ; }

shift
while [ $? -eq 0 ] ; do # lecture des options
	eval local $(echo $1 |egrep "^lv_size=|^fs_type=") >/dev/null
	shift
done

lv_size=${lv_size-${_DEFAULT_LV_SIZE}}
[ -n "$lv_size" ] || { error "$E_100 (lv_size)" ; return 1 ; }
echo "$lv_size" |egrep "M$|G$|T$" >/dev/null || { error "$E_103 ($lv_size -> M|G|T)" ; return 1 ; }

fs_type=${fs_type-${_DEFAULT_FS_TYPE}}
[ -n "$fs_type" ] || { log "$E_100 (fs_type)" ; return 1 ; }
echo " ${_VSTOOLS_KNOWN_FS_TYPES//,/ } " |grep " $fs_type " >/dev/null || { error "$E_102 ($fs_type -> ${_VSTOOLS_KNOWN_FS_TYPES//,/ })" ; return 1 ; }

logexec lvcreate -n $lv -L ${lv_size} --addtag ${HOSTNAME} $vg || return 1
logexec mkfs.$fs_type /dev/$pool || return 1
logexec mkdir -p ${_VSTOOLS_BASE}/$pool || return 1
logexec mount -o rw,tag /dev/$pool ${_VSTOOLS_BASE}/$pool || return 1
logexec setattr --barrier ${_VSTOOLS_BASE}/$pool || return 1

return 0

}

function poolDestroy
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	poolDestroy

SYNOPSIS

	poolDestroy <pool name>

DESCRIPTION

	Destroy storage pool. A pool is a LVM logical volumes, so
	'pool name' is in fact 'vg_name/pool'.

	Pool (LV) must be empty, and its tag must be the node's hostname.

	Return code: 0 if success.

EOF
exit 1
fi

local pool=$1
poolExists $pool || return 1
dirExists ${_VSTOOLS_BASE}/$pool || return 1

# Le pool DOIT etre monte
mount |grep " on ${_VSTOOLS_BASE}/$pool type " >/dev/null || { error "$E_266 ($pool)" ; return 1 ; }

# Le repertoire DOIT etre vide
[ "$(ls ${_VSTOOLS_BASE}/$pool 2>/dev/null |sed -e "s/lost+found//g")" ] &&  { error "$E_146 (${_VSTOOLS_BASE}/$pool)" ; return 1 ; }

# Le tag du pool doit correspondre au hostname
local tag=$(lvs --noheadings $pool -o lv_tags |awk '{print $1}' 2>/dev/null)
[ "$tag" == "${HOSTNAME}" ] || { error "$E_217 ($tag @  $HOSTNAME)" ; return 1 ; }

logexec umount ${_VSTOOLS_BASE}/$pool || return 1
logexec rmdir ${_VSTOOLS_BASE}/$pool || return 1

# Desactivation et suppression du LV
logexec lvchange -an $pool || return 1
logexec lvremove $pool || return 1

exit 0

}

function poolStart
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	poolStart

SYNOPSIS

	poolStart <pool (LV)>

DESCRIPTION

	Start vservers of <pool (LV)>.

	Return code: 0 if success.

EOF
exit 1
fi

local pool=$1
poolExists $pool || return 1

# Recuperation de la liste des vserveurs du pool
local vservers=$(poolVserversList $pool)

local vserver ; for vserver in $vservers ; do
 # lancer un sous-shell par vserveur en parallele
 ( /usr/sbin/vserver $vserver start 2>/dev/null >/dev/null </dev/null ) &
done

wait

return 0

}

function poolStop
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	poolStop

SYNOPSIS

	poolStop <pool (LV)>

DESCRIPTION

	Stop vservers of <pool (LV)>.

	Return code: 0 if success.

EOF
exit 1
fi

local pool=$1
poolExists $pool || return 1

# Recuperation de la liste des vserveurs du pool
local vservers=$(poolVserversList $pool)

local vserver ; for vserver in $vservers ; do
 # lancer un sous-shell par vserveur en parallele
 ( /usr/sbin/vserver $vserver stop 2>/dev/null >/dev/null </dev/null ) &
done

wait

return 0

}

function poolGrow
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	poolGrow

SYNOPSIS

	poolGrow <pool (LV)> <size[M|G|T]|+sizesize[M|G|T]>

DESCRIPTION

	Grow filesystem of <pool (LV)> to <size[M|G|T]|+sizesize[M|G|T]>.

	Return code: 0 if success.

EOF
exit 1
fi

local pool=$1
poolExists $pool || return 1
type=$(blkid -s TYPE /dev/$pool |cut -d"=" -f2 |sed -e 's/"//g ; s/ //g')
[ -n "$type" ] || { error "$E_209 ($pool)" ; return 1 ; }

local size=$2
[ -n "$size" ] || { error "$E_100 (size)" ; return 1 ; }
echo "$size" |egrep "M$|G$|T$" >/dev/null || { error "$E_103 ($size -> M|G|T)" ; return 1 ; }

logexec lvresize --size $size $pool || { error "$E_212 ($size -> $pool)" ; return 1 ; }

case $type in
	ext3)
		logexec resize2fs /dev/$pool || { error "$E_213 ($pool)" ; return 1 ; }
	;;
	xfs)
		logexec xfs_growfs /dev/$pool || { error "$E_213 ($pool)" ; return 1 ; }
	;;
esac

return 0

}
