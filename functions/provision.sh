function provision
{

if [ "$1" == "help" ] ; then cat<<EOF

DESCRIPTION

	'provision' related functions

SUB-FUNCTIONS

	provisionDebootstrap <vserver> [options]
	provisionTemplate <vserver> [options]
	provisionClone <vserver> [options]

	provisionFinalize <vserver>

USAGE

	For help about sub-functions, use '<sub-function> help'

EOF
exit 1
fi

}

function provisionDebootstrap
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	provisionDebootstrap

SYNOPSIS

	provisionDebootstrap <vserver> [options]

OPTIONS

	debootstrap=<debian dist>
	template=<path/file>
	clone=<vserver>
	arch=<${_VSTOOLS_KNOWN_ARCHS//,/|}>
	mirror=<${_DEFAULT_MIRROR-debootstrap default}>

DESCRIPTION

	Provision <vserver> with 'debootstrap' method.
	Optional value will replace default from
	file '${_VSTOOLS_CONF}/build.cf':
	debootstrap   -> _DEFAULT_DEBOOTSTRAP
	template      -> _DEFAULT_TEMPLATE
	clone         -> _DEFAULT_CLONE
	arch          -> _DEFAULT_ARCH
	mirror        -> _DEFAULT_MIRROR

	You can use this command to see known distros list:
	ls /usr/share/debootstrap/scripts/ |sed -e "s/\..*//g" |sort |uniq

	Return code: 0 if success.

EOF
exit 1
fi

local vserver=$1
[ -n "$vserver" ] || { error "$E_160" ; return 1 ; }
vmIsStopped $vserver || return 1

dirExists ${_VSERVERS_CONF}/$vserver || return 1

local pool=$(vmGetPoolName $vserver) || return 1
dirExists ${_VSTOOLS_BASE}/$pool/$vserver || return 1

local debootstrap arch mirror
shift
while [ $? -eq 0 ] ; do # lecture des options
	eval $(echo $1 |egrep "^debootstrap=|^arch=|^mirror=") >/dev/null
	shift
done

mirror=${mirror-${_DEFAULT_MIRROR}}
# 'mirror' pas indispensable -> pas de verification

debootstrap=${debootstrap-${_DEFAULT_DEBOOTSTRAP}}
[ -n "$debootstrap" ] || { error "$E_100 (debootstrap)" ; return 1 ; }

arch=${arch-${_DEFAULT_ARCH}}
[ -n "$arch" ] || { error "$E_100 (arch)" ; return 1 ; }
echo " ${_VSTOOLS_KNOWN_ARCHS} " |sed -e "s/,/ /g" |grep " $arch " 2>/dev/null >/dev/null || { error "$E_102 ($arch)" ; return 1 ; }

logexec debootstrap --arch $arch $debootstrap ${_VSTOOLS_BASE}/$pool/$vserver $mirror || return 1

return 0

}

function provisionTemplate
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	provisionTemplate

SYNOPSIS

	provisionTemplate <vserver> [options]

OPTIONS

	template=<path/file>

DESCRIPTION

	Provision <vserver> with 'template' method.
	Optional value will replace default from
	file '${_VSTOOLS_CONF}/build.cf':

	template      -> _DEFAULT_TEMPLATE

	Template may be 'tar', 'tgz', or 'bz2' archive.

	Return code: 0 if success.

EOF
exit 1
fi

local vserver=$1
[ -n "$vserver" ] || { error "$E_160" ; return 1 ; }
vmIsStopped $vserver || return 1

dirExists ${_VSERVERS_CONF}/$vserver || return 1

local pool=$(vmGetPoolName $vserver) || return 1
dirExists ${_VSTOOLS_BASE}/$pool/$vserver || return 1

local template
shift
while [ $? -eq 0 ] ; do # lecture des options
	eval $(echo $1 |egrep "^template=") >/dev/null
	shift
done

template=${template-${_DEFAULT_TEMPLATE}}
fileExists $template || return 1

#local opts
local type=$(/usr/bin/file $template |cut -d" " -f2- |cut -d"," -f1)

case "$type" in
	"gzip compressed data")
		opts=-xzf
		;;
	"bzip2 compressed data")
		opts=-xjf
		;;
	"POSIX tar archive")
		opts=-xf
		;;
	*)
		log "unknown file type '${type[1]}'" ; return 1
		;;
esac

cd ${_VSTOOLS_BASE}/$pool/$vserver
logexec "tar $opts $template" || return 1

# Suppression '/etc/hosts' du vserveur
fileExists etc/hosts && rm etc/hosts

return 0

}

function provisionClone
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	provisionClone

SYNOPSIS

	provisionClone <vserver> [options]

OPTIONS

	clone=<vserver>

DESCRIPTION

	Provision <vserver> with 'clone' method.
	Optional value will replace default from
	file '${_VSTOOLS_CONF}/build.cf':

	clone      -> _DEFAULT_CLONE

	Return code: 0 if success.

EOF
exit 1
fi

local vserver=$1
[ -n "$vserver" ] || { error "$E_160" ; return 1 ; }
vmIsStopped $vserver || return 1

dirExists ${_VSERVERS_CONF}/$vserver || return 1

local pool=$(vmGetPoolName $vserver) || return 1
dirExists ${_VSTOOLS_BASE}/$pool/$vserver || return 1

local clone
shift
while [ $? -eq 0 ] ; do # lecture des options
	eval $(echo $1 |egrep "^clone=") >/dev/null
	shift
done
clone=${clone-${_DEFAULT_CLONE}}

[ "$clone" == "$vserver" ] && { error "$E_163" ; return 1 ; }

vmIsStopped $clone || return 1

local src_pool=$(vmGetPoolName $clone) || return 1
dirExists ${_VSTOOLS_BASE}/$src_pool/$clone || return 1

#if [ "$pool" == "$src_pool" ] ; then
#	# Meme volume -> "Hardlinked"
#   # Desactive pour le moment: ecrasement des XID avec liens durs
#	logexec "cp -la ${_VSTOOLS_BASE}/$src_pool/$clone/* ${_VSTOOLS_BASE}/$pool/$vserver" || return 1
#else
#	# Volume different -> copie
	logexec "cp -a ${_VSTOOLS_BASE}/$src_pool/$clone/* ${_VSTOOLS_BASE}/$pool/$vserver" || return 1
#fi

cd ${_VSTOOLS_BASE}/$pool/$vserver

# Suppression '/etc/hosts' du vserveur
fileExists etc/hosts && rm etc/hosts

return 0

}

function provisionFinalize
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	provisionFinalize

SYNOPSIS

	provisionFinalize <vserver>

DESCRIPTION

	Finalize provision of <vserver>.

	Return code: 0 if success.

EOF
exit 1
fi

local vserver=$1
[ -n "$vserver" ] || { error "$E_160" ; return 1 ; }
vmIsStopped $vserver || return 1

dirExists ${_VSERVERS_CONF}/$vserver || return 1

# Affectation d'un xid
local xid=$(xidCounterGet) || return 1

# Creation '/dev/'
baseCreateMknod $vserver

# Creation '/etc/fstab'
baseCreateFstab $vserver

# Configuration
xidVserverSet $vserver $xid

# Mise en place des attributs par defaut
attrSetDefaults $vserver

# Mise en place des quotas / limites par defaut
local ressource
for ressource in ${_DEFAULT_LIMITS//,/ } ; do
	limitSet $vserver ${ressource/=/ }
done

# Propagation du XID
xidVserverSpread $vserver

# Incrementation du compteur XID
(( xid++ )) ; xidCounterSet $xid

# 'uname -v' dans le Vserveur retournera sa date de creation au lieu de
# celle du noyau de l'hote
dirNotExists ${_VSERVERS_CONF}/$vserver/uts && mkdir ${_VSERVERS_CONF}/$vserver/uts
date > ${_VSERVERS_CONF}/$vserver/uts/version

return 0

}
