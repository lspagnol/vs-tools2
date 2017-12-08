function limit
{

if [ "$1" == "help" ] ; then cat<<EOF

DESCRIPTION

	'limit' related functions

SUB-FUNCTIONS

	limitGet <vserver> <ressource>
	limitSet <vserver> <ressource> <value>

	limitGetAll <vserver>

USAGE

	For help about sub-functions, use '<sub-function> help'

EOF
exit 1
fi

}

function limitGet
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	limitGet

SYNOPSIS

	limitGet <vserver> <ressource>

DESCRIPTION

	Get usage and limit of <ressource> for <vserver>.

	Value is '-1' for unlimited ressource.

	Return code: 0 if success.

RESSOURCES

	NAME      PROCFS  UNIT  DESCRIPTION

	rss       rss     MB    Maximum resident set size
	disk      disk    MB    Maximum disk usage ( / )
	tmpfs     disk    MB    Maximum disk usage ( /tmp )
	nproc     proc    1     Maximum number of processes

	as        vm      MB    Maximum address space size
	memlock   vml     MB    Maximum locked-in-memory address space
	anon      anon    MB    Maximum anonymous memory size
	shmem     shm     MB    Maximum shared memory size
	nsock     sock    1     Maximum number of open sockets
	nofile    files   1     Maximum number of open files
	locks     locks   1     Maximum file locks held
	msgqueue  msgq    1     Maximum bytes in POSIX mqueues
	openfd    ofd     1     Maximum number of open file descriptors
	semary    sema    1     Maximum number of semaphore arrays
	nsems     sems    1     Maximum number of semaphores
	dentry    dent    1     Maximum number of dentry structs 

EOF
exit 1
fi

local vserver=$1
[ -n "$vserver" ] || { error "$E_160" ; return 1 ; }
dirExists ${_VSERVERS_CONF}/$vserver || return 1

local xid=$(xidVserverGet $vserver) || return 1
local pool=$(vmGetPoolName $vserver) || return 1

[ -n "$2" ] || { error "$E_100 (ressource)" ; return 1 ; }
ressource=($(grep "^$2 " ${_VSTOOLS_BIN}/ressources))
[ -n "$ressource" ] || { error "$E_104 ($2)" ; return 1 ; }
local name=${ressource[0]}
local procfs=${ressource[1]}

local value cur max

if vmIsRunningQuiet $vserver ; then

	case $procfs in
		rss|proc|vm|vml|anon|shm|sock|files|locks|msgq|ofd|sema|sems|dent)
			value=($(cat /proc/virtual/$xid/limit|sed "s/\///g ; y/ABCDEFGHIJKLMNOPQRSTUVWXYZ/abcdefghijklmnopqrstuvwxyz/" |grep "^$procfs:"))
			cur=${value[1]} # ressource consommee
			max=${value[5]} # limite dure
			;;
		disk)
			value=($(vserver $vserver exec df -P -B 1M |grep -v "^Filesystem" |grep " /$"))
			;;
		tmpfs)
			value=($(vserver $vserver exec df -P -B 1M |grep -v "^Filesystem" |grep " /tmp$"))
			;;
	esac

	case $procfs in
		rss|vm|vml|anon|shm) # Conversion nombre de pages memoire en Mo
			[ $cur -ne -1 ] && cur=$(( $cur * ${_LINUX_PAGESIZE} / 1048576 ))
			[ $max -ne -1 ] && max=$(( $max * ${_LINUX_PAGESIZE} / 1048576 ))
		;;
		disk|tmpfs)
			cur=${value[2]:--1} # ressource consommee
			max=${value[1]:--1} # limite dure
		;;
	esac

else

	case $procfs in
		rss|proc|vm|vml|anon|shm|sock|files|locks|msgq|ofd|sema|sems|dent)
			[ -f ${_VSERVERS_CONF}/$vserver/rlimits/$procfs ] && value=$(cat ${_VSERVERS_CONF}/$vserver/rlimits/$procfs)
			cur=-1
			max=${value:--1}
			case $procfs in
				rss|vm|vml|anon|shm) # Conversion nombre de pages memoire en Mo
					[ $max -ne -1 ] && max=$(( $max * ${_LINUX_PAGESIZE} / 1048576 ))
				;;
			esac
		;;
		disk)
			if [ -f ${_VSERVERS_CONF}/$vserver/dlimits/dlimit/space_total ] ; then
				max=$(cat ${_VSERVERS_CONF}/$vserver/dlimits/dlimit/space_total)
			else
				value=($(df -P -B 1K ${_VSTOOLS_BASE}/$pool |grep -v "^Filesystem" |grep " ${_VSTOOLS_BASE}/$pool$"))
				cur=${value[2]}
				max=${value[1]}
			fi
		
			local file="$(xidVserverGet $vserver)${_VSTOOLS_BASE}/${pool}/${vserver}"
			file="${_VSERVERS_CONF}/$vserver/cache/dlimits/${file////_}"

			if [ -f $file ] ; then
				cur=$(cat $file |grep "^space_used=" |cut -d"=" -f2)
			fi
			
			# Eviter la division par 0 si pas de valeur ...
			cur=${cur:--1024}
			max=${max:--1024}
			cur=$(( $cur / 1024 ))
			max=$(( $max / 1024 ))
		;;
		tmpfs)
			max=$(cat ${_VSERVERS_CONF}/$vserver/fstab 2>/dev/null |\
			grep "^none /tmp tmpfs size=" |cut -d= -f2 |cut -d, -f1 |tr -d "mM")
		;;
	esac

fi

echo "${cur:--1} ${max:--1}"

}

function limitSet
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	limitSet

SYNOPSIS

	limitSet <vserver> <ressource> <value>

DESCRIPTION

	Set limit of <ressource> to <value> for <vserver>.

	All limit of ressources can be changed / added / removed when
	vserver is running, exept for 'tmpfs' who can't be added / removed
	when '/tmp' is not empty.

	Value is '-1' for unlimited ressource.

	Return code: 0 if success.

RESSOURCES

	NAME      PROCFS  UNIT  DESCRIPTION

	rss       rss     MB    Maximum resident set size
	disk      disk    MB    Maximum disk usage ( / )
	tmpfs     disk    MB    Maximum disk usage ( /tmp )
	nproc     proc    1     Maximum number of processes

	as        vm      MB    Maximum address space size
	memlock   vml     MB    Maximum locked-in-memory address space
	anon      anon    MB    Maximum anonymous memory size
	shmem     shm     MB    Maximum shared memory size
	nsock     sock    1     Maximum number of open sockets
	nofile    files   1     Maximum number of open files
	locks     locks   1     Maximum file locks held
	msgqueue  msgq    1     Maximum bytes in POSIX mqueues
	openfd    ofd     1     Maximum number of open file descriptors
	semary    sema    1     Maximum number of semaphore arrays
	nsems     sems    1     Maximum number of semaphores
	dentry    dent    1     Maximum number of dentry structs 

EOF
exit 1
fi

local vserver=$1
[ -n "$vserver" ] || { error "$E_160" ; return 1 ; }
dirExists ${_VSERVERS_CONF}/$vserver || return 1
local xid=$(xidVserverGet $vserver) || return 1
local pool=$(vmGetPoolName $vserver) || return 1

[ -n "$2" ] || { error "$E_100 (ressource)" ; return 1 ; }
ressource=($(grep "^$2 " ${_VSTOOLS_BIN}/ressources))
[ -n "$ressource" ] || { error "$E_104 ($2)" ; return 1 ; }
local name=${ressource[0]}
local procfs=${ressource[1]}

local value=$3
[ -n "$value" ] || { error "$E_100 (value)" ; return 1 ; }
if [ "$value" != "-1" ] ; then
	if [ "$(echo "$value" |tr -d "[[:digit:]]")" ] ; then
		error "$E_102 ($value)"
		return 1
	fi
	[ $value -eq 0 ] && { log "$E_104 ($value)" ; return 1 ; }
fi

case $procfs in
	rss|vm|vml|anon|shm) # Mo en nombre de pages memoire
		[ $value -ne -1 ] && value=$(( 1048576 * $value /${_LINUX_PAGESIZE} ))
	;;
esac

# Modification 'a chaud'
if vmIsRunningQuiet $vserver ; then

	case $name in
		rss|nproc|as|memlock|anon|shmem|nsock|nofile|locks|msgqueue|openfd|semary|nsems|dentry)
			logexec /usr/sbin/vlimit --xid $xid -S -H --${name} $value
		;;
		disk)
			local space
			if [ $value -ne -1 ] ; then
				if [ ! -d ${_VSERVERS_CONF}/$vserver/dlimits/dlimit ] ; then
					# Pas de quota persistant, forcer le calcul de l'espace utilise
					space=($(/usr/sbin/vdu --xid $vserver --space --inodes ${_VSTOOLS_BASE}/$pool/$vserver))
					logexec /usr/sbin/vdlimit --xid $xid --set space_used=${space[1]} --set inodes_used=${space[2]} ${_VSTOOLS_BASE}/$pool/$vserver
				fi
				space=$(( $value * 1024 ))
				logexec /usr/sbin/vdlimit --xid $xid --set space_total=${space} --set inodes_total=${space} --set reserved=5 ${_VSTOOLS_BASE}/$pool/$vserver
			else
				logexec /usr/sbin/vdlimit --xid $xid --remove ${_VSTOOLS_BASE}/$pool/$vserver
			fi
		;;
		tmpfs)
			if [ $value -ne -1 ] ; then # modification taille
				if /usr/sbin/vserver $vserver exec mount |grep "^none on /tmp type tmpfs " >/dev/null ; then
					# /tmp est deja en tmpfs -> changement taille
					logexec /usr/sbin/vnamespace -e $xid -- mount -n -t tmpfs -o remount,size=${value}M,mode=1777 none ${_VSTOOLS_BASE}/$pool/$vserver/tmp/
				else # tmpfs pas monte -> verifier si /tmp est vide
					if [ $(/usr/sbin/vserver $vserver exec ls -1a /tmp |wc -l) -eq 2 ] ; then
						# Le repertoire est vide -> montage tmpfs
						logexec /usr/sbin/vnamespace -e $xid -- chroot ${_VSTOOLS_BASE}/$pool/$vserver mount -t tmpfs -o size=${value}M,mode=1777 none /tmp/
					else
						error "unable to mount tmpfs to not empty directory (/tmp for vserver $vserver)"
						return 1
					fi
				fi
			else # Suppression / demontage
				if /usr/sbin/vserver $vserver exec mount |grep "^none on /tmp type tmpfs " >/dev/null ; then
					# /tmp est deja en tmpfs -> verifier si /tmp est vide
					if [ $(/usr/sbin/vserver $vserver exec ls -1a /tmp |wc -l) -eq 2 ] ; then
						# Le repertoire est vide -> demontage
						logexec /usr/sbin/vnamespace -e $xid -- chroot ${_VSTOOLS_BASE}/$pool/$vserver umount /tmp/
					else
						error "unable to umount tmpfs from not empty directory (/tmp for vserver $vserver)"
						return 1
					fi
				fi
			fi
		;;
	esac

fi

# Modification persistante
case $name in
	rss|nproc|as|memlock|anon|shmem|nsock|nofile|locks|msgqueue|openfd|semary|nsems|dentry)
	#rss|proc|vm|vml|anon|shm|sock|files|locks|msgq|ofd|sema|sems|dent)
		if [ $value -ne -1 ] ; then
			[ -d ${_VSERVERS_CONF}/$vserver/rlimits ] || mkdir ${_VSERVERS_CONF}/$vserver/rlimits
			echo $value > ${_VSERVERS_CONF}/$vserver/rlimits/$name
		else
			[ -f ${_VSERVERS_CONF}/$vserver/rlimits/$name ] && rm ${_VSERVERS_CONF}/$vserver/rlimits/$name
		fi
	;;
	disk)
		if [ $value -ne -1 ] ; then
			[ -d ${_VSERVERS_CONF}/$vserver/dlimits/dlimit ] || mkdir -p ${_VSERVERS_CONF}/$vserver/dlimits/dlimit
			cd ${_VSERVERS_CONF}/$vserver/dlimits/dlimit
			echo ${_VSTOOLS_BASE}/$pool/$vserver > directory
			echo $(( $value * 1024 )) > inodes_total
			cp inodes_total space_total
			echo 5 > reserved
		else
			[ -d ${_VSERVERS_CONF}/$vserver/dlimits/dlimit ] && rm -rf ${_VSERVERS_CONF}/$vserver/dlimits
			[ -d ${_VSERVERS_CONF}/$vserver/cache/dlimits ] && rm -rf ${_VSERVERS_CONF}/$vserver/cache/dlimits
		fi
	;;
	tmpfs)
		local file=${_VSERVERS_CONF}/$vserver/fstab
		local fstab="$(cat $file |grep -v "^none /tmp tmpfs size=")"
		echo "$fstab" > $file
		if [ $value -ne -1 ] ; then
			echo "none /tmp tmpfs size=${value}M,mode=1777 0 0" >> $file
		fi
	;;
esac

}

function limitGetAll
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	limitGetAll

SYNOPSIS

	limitGetAll <vserver>

DESCRIPTION

	Get usage and limit of all ressources for <vserver>.

	Value is '-1' for unlimited ressource.

	Return code: 0 if success.

EOF
exit 1
fi

local vserver=$1
[ -n "$vserver" ] || { error "$E_160" ; return 1 ; }
dirExists ${_VSERVERS_CONF}/$vserver || return 1

local ressources="rss nproc disk tmpfs as memlock anon shmem nsock nofile locks msgqueue openfd semary nsems dentry"
printf "%-8s %-8s %-8s \n" NAME CURRENT LIMIT $(
for ressource in $ressources ; do
	echo "$ressource $(limitGet $vserver $ressource)"
done
)

return 0

}
