function vm
{

if [ "$1" == "help" ] ; then cat<<EOF

DESCRIPTION

	'vm' related functions

SUB-FUNCTIONS

	vmIsRunning <vserver>
	vmIsRunningQuiet <vserver>
	vmIsStopped <vserver>

	vmIsEnabled <vserver>
	vmIsEnabledQuiet <vserver>
	vmIsDisabled <vserver>

	vmList
	vmState <vserver>
	vmStats <vserver>

	vmGetPoolName <vserver>
	
	vmEnable <vserver>
	vmDisable <vserver>

	vmStart <vserver>
	vmStop <vserver>

	vmBuild <vserver> <ip> [options]
	vmDestroy <vserver>

USAGE

	For help about sub-functions, use '<sub-function> help'.

EOF
exit 1
fi

}

function vmIsRunning
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	vmIsRunning

SYNOPSIS

	vmIsRunning <vserver>

DESCRIPTION

	Test running state of vserver.
	Return code: 0 if success or log as error.

EOF
exit 1
fi

local vserver=$1
[ -n "$vserver" ] || { error "$E_160" ; return 1 ; }

test -f ${_VSERVERS_RUN}/$vserver || { error "$E_161 ($vserver)" ; return 1 ; }

return 0

}

function vmIsStopped
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	vmIsStopped

SYNOPSIS

	vmIsStopped <vserver>

DESCRIPTION

	Test stopped state of vserver.
	Return code: 0 if success or log as error.

EOF
exit 1
fi

local vserver=$1
[ -n "$vserver" ] || { error "$E_160" ; return 1 ; }

test -f ${_VSERVERS_RUN}/$vserver && { error "$E_162 ($vserver)" ; return 1 ; }

return 0

}

function vmStart
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	vmStart

SYNOPSIS

	vmStart <vserver>

DESCRIPTION

	Start <vserver>.
	
	Return code: 0 if success.

EOF
exit 1
fi

local vserver=$1
[ -n "$vserver" ] || { error "$E_160" ; return 1 ; }
dirExists ${_VSERVERS_CONF}/$vserver || return 1

vmIsStopped $vserver || return 0

logexec /usr/sbin/vserver $vserver start

return $?

}

function vmStop
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	vmStop

SYNOPSIS

	vmStop <vserver>

DESCRIPTION

	Stop <vserver>.
	
	Return code: 0 if success.

EOF
exit 1
fi

local vserver=$1
[ -n "$vserver" ] || { error "$E_160" ; return 1 ; }
dirExists ${_VSERVERS_CONF}/$vserver || return 1

vmIsRunning $vserver || return 0

logexec /usr/sbin/vserver $vserver stop

return $?

}

function vmList
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	vmList

SYNOPSIS

	vmList

DESCRIPTION

	Shows list of all available Vservers.
	
	Return code: 0 if success.

EOF
exit 1
fi

dirExists ${_VSTOOLS_BASE} || return 1

pushd ${_VSTOOLS_BASE} >/dev/null

find  . -maxdepth 3 -mindepth 3 -type d \
 |grep -v "/lost+found$" \
 |cut -d"/" -f4 \
 |sort

popd >/dev/null >/dev/null

return 0

}

function vmState
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	vmState

SYNOPSIS

	vmState

DESCRIPTION

	Shows state of all available Vservers.

	Return code: 0 if success.

EOF
exit 1
fi

local vservers=$(vmList) || return 1
local vserver
local run
local xid
local ena

printf "%-5s %-3s %-3s %-s\n" XID ENA RUN VM $( 
for vserver in $vservers ; do

	vmIsRunning 2>/dev/null $vserver && run=yes || run=no
	vmIsEnabled 2>/dev/null $vserver && ena=yes || ena=no

	xid=$(xidVserverGet $vserver 2>/dev/null) ; xid=${xid:-ERR}

	echo "$xid $ena $run $vserver"

done |sort -n
)

return 0

}

function vmStats
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	vmStats

SYNOPSIS

	vmStats

DESCRIPTION

	Shows stats of all running Vservers.
	
	Return code: 0 if success.

EOF
exit 1
fi

/usr/sbin/vserver-stat |sed -e 's/^CTX /XID /g ; s/UPTIME NAME$/UPTIME VM/g'

return 0

}

function vmIsEnabled
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	vmIsEnabled

SYNOPSIS

	vmIsEnabled <vserver>

DESCRIPTION

	Test 'enabled' tag of vserver.
	
	Vservers that have 'enabled' tag will automatically start/stop
	during the node boot/shutdown sequence.

	Return code: 0 if success.

EOF
exit 1
fi

local vserver=$1
dirExists ${_VSERVERS_CONF}/$vserver || return 1

grep "^default$" ${_VSERVERS_CONF}/$vserver/apps/init/mark 2>/dev/null >/dev/null || return 1

return 0

}

function vmIsDisabled
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	vmIsDisabled

SYNOPSIS

	vmIsDisabled <vserver>

DESCRIPTION

	Test 'enabled' tag of vserver.
	
	Vservers that have 'enabled' tag will automatically start/stop
	during the node boot/shutdown sequence.

	Return code: 0 if success.

EOF
exit 1
fi

local vserver=$1
dirExists ${_VSERVERS_CONF}/$vserver || return 1

grep "^default$" ${_VSERVERS_CONF}/$vserver/apps/init/mark 2>/dev/null >/dev/null && return 1

return 0

}

function vmEnable
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	vmEnable

SYNOPSIS

	vmEnable <vserver>

DESCRIPTION

	Set 'enabled' tag of <vserver>.
	
	Return code: 0 if succes (or already enabled).

EOF
exit 1
fi

local vserver=$1
[ -n "$vserver" ] || { error "$E_160" ; return 1 ; }
dirExists ${_VSERVERS_CONF}/$vserver || return 1

vmIsEnabledQuiet $vserver && return 0

mkdir -p ${_VSERVERS_CONF}/$vserver/apps/init
echo default > ${_VSERVERS_CONF}/$vserver/apps/init/mark

return 0

}

function vmDisable
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	vmDisable

SYNOPSIS

	vmDisable <vserver>

DESCRIPTION

	Remove 'enabled' tag of <vserver>.
	
	Return code: 0 if succes (or already disabled).

EOF
exit 1
fi

local vserver=$1
[ -n "$vserver" ] || { error "$E_160" ; return 1 ; }
dirExists ${_VSERVERS_CONF}/$vserver || return 1

vmIsEnabledQuiet $vserver || return 0

fileExists ${_VSERVERS_CONF}/$vserver/apps/init/mark && rm ${_VSERVERS_CONF}/$vserver/apps/init/mark

return 0

}

function vmGetPoolName
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	vmGetPoolName

SYNOPSIS

	vmGetPoolName <vserver>

DESCRIPTION

	Get pool (LV) name of <vserver>.

	Return code: 0 if success.

EOF
exit 1
fi

local vserver=$1
[ -n "$vserver" ] || { error "$E_160" ; return 1 ; }
dirExists ${_VSERVERS_CONF}/$vserver || return 1
fileExists ${_VSERVERS_CONF}/$vserver/pool || return 1

cat ${_VSERVERS_CONF}/$vserver/pool

return 0
	
}

function vmBuild
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	vmBuild

SYNOPSIS

	vmBuild <vserver> <ip> [options]

OPTIONS

	pool=<logical volume>

	template=<file> | debootstrap=<debian_dist> | clone=<vserver>
	
		arch=<${_VSTOOLS_KNOWN_ARCHS//,/|}>
		mirror=<url>

		Examples:
		mirror=ftp://ftp.fr.debian.org/debian
		mirror=ftp://ftp.free.fr/mirrors/ftp.ubuntu.com/ubuntu/
	
	enable=<yes|no>
	start=<yes|no>

DESCRIPTION

	build <vserver> with <ip>.

	Return code: 0 if success.

EOF
exit 1
fi

local vserver=$1
dirNotExists ${_VSERVERS_CONF}/$vserver || return 1

local ip=$2
netIpCheckValue $ip || return 1

netTestPing $ip && warning "this address is already active somewhere, so vserver may be unable to start"

confirm || abort "by user"

local pool debootstrap template arch mirror enable start
shift ; shift
while [ $? -eq 0 ] ; do # lecture des options
	eval $(echo $1 |egrep "^pool=|^method=|^debootstrap=|^template=|^clone=|^arch=|^mirror=|^enable=|^start=") >/dev/null
	shift
done

[ -z "$debootstrap" ] && [ -z "$template" ] && [ -z "$clone" ] && { error "unspecified provision method" ; return 1 ; }

local opts

[ -n "$pool" ] && opts="pool=$pool"

baseCreate $vserver $opts

if [ -n "$debootstrap" ] ; then

	opts="debootstrap=$debootstrap"
	[ -n "$arch" ] && opts="$opts arch=$arch"
	[ -n "$mirror" ] && opts="$opts mirror=$mirror"

	provisionDebootstrap $vserver $opts || return 1

elif [ -n "$template" ] ; then

	opts="template=$template"
	provisionTemplate $vserver $opts || return 1

elif [ -n "$clone" ] ; then

	opts="clone=$clone"
	provisionClone $vserver $opts || return 1

fi

provisionFinalize $vserver
netIpSet $vserver $ip

[ ${_DEFAULT_ENABLE} == "yes" ] || [ "$enable" == "yes" ] && [ "$enable" != "no" ] && vmEnable $vserver
[ ${_DEFAULT_START} == "yes" ] || [ "$start" == "yes" ] && [ "$start" != "no" ] && vmStart $vserver

fileExistsQuiet ${_VSTOOLS_BASE}/$pool/$vserver/root/post-install.sh && logexec /usr/sbin/vserver $vserver exec sh /root/post-install.sh

exit 0

}

function vmDestroy
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	vmDestroy

SYNOPSIS

	vmDestroy <vserver>

DESCRIPTION

	Destroy <vserver>.

	Return code: 0 if success.

EOF
exit 1
fi

local vserver=$1
vmIsStopped $vserver || abort "$E_162"

warning "vserver ($vserver) will be definitively removed"

confirm && baseDestroy $vserver || abort "by user"

exit 0

}

function vmIsRunningQuiet
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	vmIsRunningQuiet

SYNOPSIS

	vmIsRunningQuiet <vserver>

DESCRIPTION

	Test running state of vserver.
	Return code: 0 if success.

EOF
exit 1
fi

local vserver=$1
[ -n "$vserver" ] || { error "$E_160" ; return 1 ; }

test -f ${_VSERVERS_RUN}/$vserver || return 1

return 0

}

function vmIsEnabledQuiet
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	vmIsEnabled

SYNOPSIS

	vmIsEnabled <vserver>

DESCRIPTION

	Test 'enabled' tag of vserver.
	
	Vservers that have 'enabled' tag will automatically start/stop
	during the node boot/shutdown sequence.

	Return code: 0 if success.

EOF
exit 1
fi

local vserver=$1
dirExists ${_VSERVERS_CONF}/$vserver || return 1

grep "^default$" ${_VSERVERS_CONF}/$vserver/apps/init/mark 2>/dev/null >/dev/null || return 1

return 0

}
