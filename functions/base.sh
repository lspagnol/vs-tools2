function base
{

if [ "$1" == "help" ] ; then cat<<EOF

DESCRIPTION

	'base' related functions

SUB-FUNCTIONS

	baseList
	baseTree

	baseCreate <vserver> [options]
		baseCreateMknod <vserver>
		baseCreateFstab <vserver>
		baseCreateLinks <vserver>
		baseCreateScripts <vserver>

	baseDestroy <vserver>

	baseMove <vserver> <pool>

USAGE

	For help about sub-functions, use '<sub-function> help'

EOF
exit 1
fi

}

function baseList
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	baseList

SYNOPSIS

	baseList

DESCRIPTION

	Show list of pools/vservers.

	Return code: 0 if success.

EOF
exit 1
fi

dirExists ${_VSTOOLS_BASE} || return 1

pushd ${_VSTOOLS_BASE} >/dev/null

printf "%-20s %-s\n" POOL VM $(\
find  . -maxdepth 3 -mindepth 3 -type d \
	|grep -v "/lost+found$"\
	|sed -e "s/^.\///g ; s/\// /g" \
	|awk '{print $1"/"$2" "$3}'\
	|sort
)

popd >/dev/null

return 0
	
}

function baseTree
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	baseTree

SYNOPSIS

	baseTree

DESCRIPTION

	Show tree of pools/vservers.

	Return code: 0 if success.

EOF
exit 1
fi

dirExists ${_VSTOOLS_BASE} || return 1

tree --noreport -nd -L 3 -I "*lost+found*" ${_VSTOOLS_BASE}

return 0
	
}

function baseCreate
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	baseCreate

SYNOPSIS

	baseCreate <vserver> [options]

OPTIONS

	pool=<pool name>
	disk_limit=<quota in MB>

DESCRIPTION

	Build storage for <vserver> and call functions:
	baseCreateLinks
	baseCreateScripts
	
	Optional value will replace default from
	file '${_VSTOOLS_CONF}/build.cf':
	pool		-> ${_DEFAULT_POOL}

	Return code: 0 if success.

EOF
exit 1
fi

dirExists ${_VSERVERS_CONF} || return 1
dirExists ${_VSTOOLS_BASE} || return 1

local vserver=$1
[ -n "$vserver" ] || { error "$E_160" ; return 1 ; }
vmIsStopped $vserver || return 1
dirNotExists ${_VSERVERS_CONF}/$vserver || return 1

local pool
shift
while [ $? -eq 0 ] ; do # lecture des options
	eval $(echo $1 |egrep "^pool=") >/dev/null
	shift
done

pool=${pool-${_DEFAULT_POOL}}
poolExists $pool || return 1
dirNotExists ${_VSTOOLS_BASE}/$pool/$vserver || return 1

# Creation repertoires
mkdir ${_VSERVERS_CONF}/$vserver
mkdir ${_VSTOOLS_BASE}/$pool/$vserver
mkdir ${_VSERVERS_CACHE}/$vserver

# Stockage des infos dans la configuration
cd ${_VSERVERS_CONF}/$vserver
echo "$pool" > lv_name ; ln -s lv_name pool
echo $(lvs -o uuid --noheadings --nosuffix $pool) > lv_uuid
eval local $(blkid /dev/$pool |cut -d: -f2) >/dev/null
echo "$UUID" > fs_uuid
echo "$TYPE" > fs_type
echo $vserver > name

baseCreateLinks $vserver
baseCreateScripts $vserver

return 0

}

function baseDestroy
{

if [ "$1" == "help" ] ; then cat<<EOF


NAME

	baseDestroy

SYNOPSIS

	baseDestroy <vserver>

DESCRIPTION

    Destroy storage for <vserver>

	Dedicated LVs can be removed only if they have '$HOSTNAME' tag
	Only one tag is allowed, so if you need to remove LVs with multiple
	tags, you will have to remove other than '$HOSTNAME' first.

	Return code: 0 if success.

EOF
exit 1
fi

local vserver=$1
[ -n "$vserver" ] || { error "$E_160" ; return 1 ; }
vmIsStopped $vserver || return 1

local pool=$(cat ${_VSERVERS_CONF}/$vserver/pool 2>/dev/null)
local xid=$(cat ${_VSERVERS_CONF}/$vserver/context 2>/dev/null)

# Suppression repertoires
[ -d ${_VSERVERS_CONF}/$vserver ] && logexec rm -rf ${_VSERVERS_CONF}/$vserver
[ -d ${_VSERVERS_CACHE}/$vserver ] && logexec rm -rf ${_VSERVERS_CACHE}/$vserver
[ -d ${_VSTOOLS_CACHE}/stats/vservers/$vserver ] && logexec rm -rf ${_VSTOOLS_CACHE}/stats/vservers/$vserver

[ -n "$pool" ] && [ -d ${_VSTOOLS_BASE}/$pool/$vserver ] && logexec rm -rf ${_VSTOOLS_BASE}/$pool/$vserver
[ -n "$xid" ] && [ -L /var/run/vservers.rev/$xid ] && logexec rm /var/run/vservers.rev/$xid
[ -L ${_VSERVERS_BASE}/$vserver ] && logexec rm ${_VSERVERS_BASE}/$vserver

return 0

}

function baseCreateMknod
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	baseCreateMknod

SYNOPSIS

	baseCreateMknod <vserver>

DESCRIPTION

	Create '/dev/' (mknod) entries for <vserver>.

	Return code: 0 if success.

EOF
exit 1
fi

local vserver=$1
[ -n "$vserver" ] || { error "$E_160" ; return 1 ; }
vmIsStopped $vserver || return 1

local pool=$(vmGetPoolName $vserver) || return 1
dirExists ${_VSTOOLS_BASE}/$pool/$vserver ] || return 1

cd ${_VSTOOLS_BASE}/$pool/$vserver
rm -rf dev ; mkdir dev ; chmod 755 dev
cd dev

local line array
while read line ; do
        # 0=node, 1=major, 2=minor, 3=rights
        array=($line)
        mknod ${array[0]} c ${array[1]} ${array[2]}
        chmod ${array[3]} ${array[0]}
done << EOF
full 1 7 666
null 1 3 666
ptmx 5 2 666
tty 5 0 666
zero 1 5 666
random 1 8 644
urandom 1 9 644
EOF
mkdir pts
chmod 755 pts

return 0
	
}

function baseCreateFstab
{
if [ "$1" == "help" ] ; then cat<<EOF

NAME

	baseCreateFstab

SYNOPSIS

	baseCreateFstab <vserver>

DESCRIPTION

	Create '/etc/fstab' <vserver>.

	Return code: 0 if success.

EOF
exit 1
fi

local vserver=$1
[ -n "$vserver" ] || { error "$E_160" ; return 1 ; }
vmIsStopped $vserver || return 1

dirExists ${_VSERVERS_CONF}/$vserver || return 1

cat<<EOF > ${_VSERVERS_CONF}/$vserver/fstab
none /proc proc defaults 0 0
none /dev/pts devpts gid=5,mode=620 0 0
EOF

return 0

}

function baseCreateLinks
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	baseCreateLinks

SYNOPSIS

	baseCreateLinks <vserver>

DESCRIPTION

	Create 'Util-Vserver' symlinks for <vserver>.

	Return code: 0 if success.

EOF
exit 1
fi

local vserver=$1
[ -n "$vserver" ] || { error "$E_160" ; return 1 ; }
vmIsStopped $vserver || return 1

dirExists ${_VSERVERS_CONF}/$vserver || return 1

local pool=$(vmGetPoolName $vserver) || return 1
dirExists ${_VSTOOLS_BASE}/$pool/$vserver ] || return 1

mkdir -p ${_VSERVERS_CONF}/.defaults/cachebase/$vserver

[ -L ${_VSERVERS_CONF}/$vserver/cache ] && rm ${_VSERVERS_CONF}/$vserver/cache
[ -L ${_VSERVERS_CONF}/$vserver/vdir ] && rm ${_VSERVERS_CONF}/$vserver/vdir
[ -L ${_VSERVERS_BASE}/$vserver ] && rm ${_VSERVERS_BASE}/$vserver
[ -L ${_VSERVERS_CONF}/$vserver/run ] && rm ${_VSERVERS_CONF}/$vserver/run

ln -fs ${_VSERVERS_CONF}/.defaults/cachebase/$vserver ${_VSERVERS_CONF}/$vserver/cache
ln -fs ${_VSTOOLS_BASE}/$pool/$vserver ${_VSERVERS_CONF}/$vserver/vdir
ln -fs ${_VSTOOLS_BASE}/$pool/$vserver ${_VSERVERS_BASE}/$vserver
ln -fs ${_VSERVERS_RUN}/$vserver ${_VSERVERS_CONF}/$vserver/run

return 0
	
}

function baseCreateScripts
{
if [ "$1" == "help" ] ; then cat<<EOF

NAME

	baseCreateScripts

SYNOPSIS

	baseCreateScripts <vserver>

DESCRIPTION

	Create 'vs-tools' start/stop sequence symlinks for <vserver>.

	Return code: 0 if success.

EOF
exit 1
fi

local vserver=$1
[ -n "$vserver" ] || { error "$E_160" ; return 1 ; }
vmIsStopped $vserver || return 1

dirExists ${_VSERVERS_CONF}/$vserver || return 1

mkdir -p ${_VSERVERS_CONF}/$vserver/scripts
mkdir -p ${_VSERVERS_CONF}/$vserver/scripts/{initialize,post-start,post-stop,postpost-stop,pre-start,pre-stop,prepre-start}.d
find ${_VSERVERS_CONF}/$vserver/scripts -type l -exec rm {} \;

local scripts=${_VSTOOLS_BIN}/scripts
cd ${_VSERVERS_CONF}/$vserver/scripts

ln -s $scripts/start-begin.sh initialize.d/00_start-begin
ln -s $scripts/start-end.sh post-start.d/99_start-end

ln -s $scripts/stop-begin.sh pre-stop.d/00_stop-begin
ln -s $scripts/stop-end.sh postpost-stop.d/99_stop-end

ln -s $scripts/vlan-up.sh prepre-start.d/10_vlan-up
ln -s $scripts/vlan-down.sh postpost-stop.d/90_vlan-down

ln -s $scripts/route-up.sh pre-start.d/10_route-up
ln -s $scripts/route-down.sh postpost-stop.d/80_route-down

return 0
	
}

function baseMove
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	baseMove

SYNOPSIS

	baseMove <vserver> <pool>

DESCRIPTION

	Move base of <vserver> to <pool>.

	Return code: 0 if success.

EOF
exit 1
fi

dirExists ${_VSERVERS_CONF} || return 1
dirExists ${_VSTOOLS_BASE} || return 1

local vserver=$1
[ -n "$vserver" ] || { error "$E_160" ; return 1 ; }
dirExists ${_VSERVERS_CONF}/$vserver || return 1

local new_pool=$2
[ -n "$new_pool" ] || { error "$E_200" ; return 1 ; }
poolExists $new_pool|| return 1
dirNotExists ${_VSTOOLS_BASE}/$new_pool/$vserver || return 1

local old_pool=$(vmGetPoolName $vserver) || return 1
dirExists ${_VSTOOLS_BASE}/$old_pool/$vserver || return 1

local xid=$(xidVserverGet $vserver) || return 1

local dlimit=($(limitGet $vserver disk))

if vmIsRunning $vserver ; then
	warning "Vserver is running and will be restarted"
	confirm || abort "by user"
	# Copie base (1ere passe a chaud)
	if logexec rsync -a --numeric-ids --stats ${_VSTOOLS_BASE}/$old_pool/$vserver/ ${_VSTOOLS_BASE}/$new_pool/$vserver/ ; then
		vmStop $vserver
		local restart=1
	else
		error "$E_147 (${_VSTOOLS_BASE}/$old_pool/$vserver/ -> ${_VSTOOLS_BASE}/$new_pool/$vserver/)"
		logexec rm -rf ${_VSTOOLS_BASE}/$new_pool/$vserver
		return 1
	fi
fi

# Copie base (2eme passe)
if logexec rsync -a --delete --numeric-ids --stats ${_VSTOOLS_BASE}/$old_pool/$vserver/ ${_VSTOOLS_BASE}/$new_pool/$vserver/ ; then
	logexec rm -rf ${_VSTOOLS_BASE}/$old_pool/$vserver/
else
	error "$E_147 (${_VSTOOLS_BASE}/$old_pool/$vserver/ -> ${_VSTOOLS_BASE}/$new_pool/$vserver/)"
	[ -n "$restart" ] && vmStart $vserver
	logexec rm -rf ${_VSTOOLS_BASE}/$new_pool/$vserver
	return 1
fi

# Stockage des infos dans la configuration
cd ${_VSERVERS_CONF}/$vserver
echo "$new_pool" > lv_name ; ln -fs lv_name pool
echo $(lvs -o uuid --noheadings --nosuffix $new_pool) > lv_uuid
eval local $(blkid /dev/$new_pool |cut -d: -f2) >/dev/null
echo "$UUID" > fs_uuid
echo "$TYPE" > fs_type

# Propagation du xid sur la nouvelle base
xidVserverSpread $vserver

baseCreateLinks $vserver

# RAZ et remise en place quota disque
if [ ${dlimit[1]} -ne -1 ] ; then
	limitSet $vserver disk -1
	limitSet $vserver disk ${dlimit[1]}
fi

[ -n "$restart" ] && vmStart $vserver

return 0

}

