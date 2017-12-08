function net
{

if [ "$1" == "help" ] ; then cat<<EOF

DESCRIPTION

	'net' related functions
	 
SUB-FUNCTIONS

	netIfCheckvalue <ifid>
	netIfList <vserver>
	netIfAdd <vserver> <ifid>
	netIfDel <vserver> <ifid>
	
	netIpIsv6 <ip>
	netIpCheckValue <ip>[/netmask]
	netIpGet <vserver> [options]
	netIpSet <vserver> <ip> [options]
	netIpAdd <vserver> <ip>
	netIpReset <vserver> [options]

	netTestPing <ip|host>
	netTestSsh <ip|host>
	netTestRsync <ip|host>
	netTestDev <network device>

	netVlanSelect <ip>

USAGE

	For help about sub-functions, use '<sub-function> help'.

EOF
exit 1
fi

}

function netIfCheckvalue
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	netIfCheckvalue

SYNOPSIS

	netIfCheckvalue <ifid>

DESCRIPTION

	Check value for 'ifid'.
	
	<ifid> must be numerical value, '0 < ifid > 16'.
	
	Return code: 0 if success.

EOF
exit 1
fi

local ifid=$1
[ -n "$ifid" ] || { log "$E_100 (ifid)" ; return 1 ; }

# Chiffres uniquement
[ "$(echo "$ifid" |tr -d [0-9])" ] && return 1

# 1 < ifid > 16
[ $ifid -gt 0 ] && [ $ifid -lt 16 ] || return 1

return 0

}

function netIfList
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	netIfList

SYNOPSIS

	netIfList <vserver>
	Return code 1 if no network interface found

DESCRIPTION

	Returns list of <vserver> network interfaces.
	
	Return code: 0 if success.

EOF
exit 1
fi

local vserver=$1
[ -n "$vserver" ] || { error "$E_160" ; return 1 ; }
dirExists ${_VSERVERS_CONF}/$vserver/interfaces || return 1

local ifids=$(ls ${_VSERVERS_CONF}/$vserver/interfaces)
[ -n "$ifids" ] || { log "$E_101 'ifids" ; return 1 ; }

local ifid ; for ifid in $ifids ; do
	echo "$ifid $(cat ${_VSERVERS_CONF}/$vserver/interfaces/$ifid/dev 2>/dev/null || echo "*") $(cat ${_VSERVERS_CONF}/$vserver/interfaces/$ifid/ip 2>/dev/null || echo "*")"
done

return 0

}

function netIfAdd
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	netIfAdd

SYNOPSIS

	netIfAdd <vserver> <ifid>

DESCRIPTION

	Add <ifid> directory to <vserver>.
	
	Return code: 0 if success.

EOF
exit 1
fi

local vserver=$1
[ -n "$vserver" ] || { error "$E_160" ; return 1 ; }
dirExists ${_VSERVERS_CONF}/$vserver/interfaces || return 1

local ifid=$2
netIfCheckvalue $ifid || return 1

dirNotExists ${_VSERVERS_CONF}/$vserver/interfaces/$ifid || return 1

mkdir ${_VSERVERS_CONF}/$vserver/interfaces/$ifid

return 0

}

function netIfDel
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	netIfDel

SYNOPSIS

	netIfDel <vserver> <ifid>
	
DESCRIPTION

	Del <ifid> directory from <vserver> and hot remove ip when vserver
	is running.
	
	Primary <ifid> '0' can't be removed.
	
	Return code: 0 if success.

EOF
exit 1
fi

local vserver=$1
[ -n "$vserver" ] || { error "$E_160" ; return 1 ; }
dirExists ${_VSERVERS_CONF}/$vserver/interfaces || return 1

local ifid=$2
netIfCheckvalue $ifid || return 1

dirExists ${_VSERVERS_CONF}/$vserver/interfaces/$ifid || return 1

local old_ip=$(cat ${_VSERVERS_CONF}/$vserver/interfaces/$ifid/ip 2>/dev/null)
local old_dev=$(cat ${_VSERVERS_CONF}/$vserver/interfaces/$ifid/dev 2>/dev/null)
local old_prefix=$(cat ${_VSERVERS_CONF}/$vserver/interfaces/$ifid/prefix 2>/dev/null)

rm -rf ${_VSERVERS_CONF}/$vserver/interfaces/$ifid

# Reconfiguration a chaud des interfaces si necessaire
if vmIsRunningQuiet $vserver ; then
	[ -n "$old_ip" ] && logexec /sbin/ip addr del dev ${old_dev} ${old_ip}/${old_prefix}
	logexec naddress --nid $vserver $(cat ${_VSERVERS_CONF}/$vserver/interfaces/*/ip |sed -e "s/^/--set --ip /g")
fi

return 0

}

function netIpIsv6
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	netIpIsv6

SYNOPSIS

	netIpIsv6 <ip>

DESCRIPTION

	Check if <ip> is an IPv6 address.

	Return code: 0 if true.

EOF
exit 1
fi

local ip=$1
[ -n "$ip" ] || { log "$E_100 'ip'" ; return 1 ; }

# On ne tient pas compte d'un eventuel prefixe de reseau
[ "$(echo $ip |cut -d"/" -f1 |tr -d "[:xdigit:]")" == ":::::" ] && return 0

return 1

}

function netIpCheckValue
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	netIpCheckValue

SYNOPSIS

	netIpCheckValue <ip>[/netmask]

DESCRIPTION

	Check <ip>[/netmask] is an IPv4 address.

	Return code: 0 if success.

EOF
exit 1
fi

local ip=$1
[ -n "$ip" ] || { log "$E_100 'ip'" ; return 1 ; }

# IPv6 -> OK sans faire plus de verification
netIpIsv6 $ip && return 0

# IPv4 -> verification coherence de l'adresse
ipcalc -nb $ip |grep "^INVALID " 2>/dev/null >/dev/null && return 1

return 0

}

function netIpGet
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	netIpGet

SYNOPSIS

	netIpGet <vserver> [options]

OPTIONS

	ifid=<interface id>

DESCRIPTION

	Return ip address from <vserver> configuration.
	
	When (ifid) is not specified, it will be assumed as '0'.

	Return code: 0 if success.

EOF
exit 1
fi

local vserver=$1
[ -n "$vserver" ] || { error "$E_160" ; return 1 ; }
dirExists ${_VSERVERS_CONF}/$vserver/interfaces || return 1

shift
while [ $? -eq 0 ] ; do # lecture des options
	eval local $(echo $1 |egrep "^ifid=") >/dev/null
	shift
done

if [ -z "$ifid" ] ; then
	ifid=0
else
	netIfCheckvalue $ifid
fi

cat ${_VSERVERS_CONF}/$vserver/interfaces/$ifid/ip 2>/dev/null || return 1

return 0

}

function netIpSet
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	netIpSet

SYNOPSIS

	netIpSet <vserver> <ip> [options]

OPTIONS

	ifid=<interface id>

DESCRIPTION

	Check and write <ip> to <vserver> configuration, then configure
	files for  the vserver:
	/etc/hosts
		
	When <ifid> is not specified, it will be assumed as '0'.
	Primary <ifid> '0' can't be set on running vservers.
	
	Secondary addresses will be hot reconfigured on running vservers.
	
	Return code: 0 if success.

EOF
exit 1
fi

local vserver=$1
[ -n "$vserver" ] || { error "$E_160" ; return 1 ; }
dirExists ${_VSERVERS_CONF}/$vserver || return 1

local pool=$(vmGetPoolName $vserver) || return 1
dirExists ${_VSTOOLS_BASE}/$pool/$vserver ] || return 1

local ip=$2
netIpCheckValue $ip || return 1

local ifid
shift ; shift
while [ $? -eq 0 ] ; do # lecture des options
	eval $(echo $1 |egrep "^ifid=") >/dev/null
	shift
done
if test -z "$ifid" ; then
	ifid=0
	mkdir -p ${_VSERVERS_CONF}/$vserver/interfaces/$ifid
else
	test -d ${_VSERVERS_CONF}/$vserver/interfaces/$ifid || abort "$E_141 '${_VSERVERS_CONF}/$vserver/interfaces/$ifid'"
fi

if [ $ifid -eq 0 ] ; then # pas de changement de l'adresse primaire si le vserveur fonctionne
	vmIsStopped $vserver || return 1
fi

if netTestPing $ip ; then # cette adresse est deja active sur le reseau
	vmIsStopped $vserver || return 1 # cette addresse ne doit pas etre affectee si le vserveur fonctionne
	warning "ip '$ip' is already active somewhere, vserver ($vserver) may be unable to start"
fi

local old_ip=$(cat ${_VSERVERS_CONF}/$vserver/interfaces/$ifid/ip 2>/dev/null)
local old_prefix=$(cat ${_VSERVERS_CONF}/$vserver/interfaces/$ifid/prefix 2>/dev/null)

local xid=$(xidVserverGet $vserver) || return 1
local vid=$(netVlanSelect $ip)

# Selection parametres reseau, fallback valeurs par defaut sur index 0

local net=${_NET[$vid]:-${_NET[0]}}
[ -n "$net" ] || { error "$E_100 (_NET)" ; return 1 ; }

local dev=${_NET_DEV[$vid]:-${_NET_DEV[0]}}
[ -n "$dev" ] || { error "$E_100 (_NET_DEV)" ; return 1 ; }
[ -n "$vid" ] && dev=${dev}.${vid} # Ajout du vid si necessaire

local prefix=${_CIDR[$vid]:-${_CIDR[0]}}
[ -n "$prefix" ] || { error "$E_100 (_CIDR)" ; return 1 ; }

local table=${_TABLE[$vid]:-${_TABLE[0]}}
local gateway=${_GATEWAY[$vid]:-${_GATEWAY[0]}}

# 'domain name'
local domain=${_DOMAIN[$vid]:-${_DOMAIN[0]}}
[ -n "$domain" ] || { error "$E_100 (domain)" ; return 1 ; }

if [ $ifid -eq 0 ] ; then

	# Configuration 'resolv.conf' uniquement pour l'interface primaire

	# 'search domains' -> affecte 'domain name' si rien n'est trouve
	local searchdomains=${_SEARCHDOMAINS[$vid]:-${_SEARCHDOMAINS[0]}}
	searchdomains=${searchdomains:-$domain}
	searchdomains=${searchdomains//,/ }

	# 'nameservers'
	local nameservers=${_NAMESERVERS[$vid]:-${_NAMESERVERS[0]}}
	[ -n "$nameservers" ] || { error "$E_100 (nameservers)" ; return 1 ; }
	nameservers=${nameservers//,/ }
	
fi

# Calcul de l'adresse de broadcast
local bcast=$(ipcalc -nb $net/$prefix |grep "^Broadcast:" |awk '{print $2}')

# Configuration Util-Vserver
cd ${_VSERVERS_CONF}/$vserver/interfaces/$ifid
[ -f ip ] && local old_ip=$(cat ip)
echo $ip > ip
echo $dev > dev
echo $net > net
echo $bcast > bcast
echo $prefix > prefix
if [ -n "$table" ] ; then
	echo $table > table
else
	test -f table && rm table
fi
if [ -n "$gateway" ] ; then
	echo $gateway > gateway
else
	test -f gateway && rm gateway
fi
echo ${xid}-${ifid} > name
echo $dev |grep "\." > /dev/null && touch novlandev
mkdir -p ${_VSERVERS_CONF}/$vserver/uts
cd ${_VSERVERS_CONF}/$vserver/uts
echo $vserver.$domain > nodename

# Configuration Vserveur
cd ${_VSTOOLS_BASE}/$pool/$vserver/etc/
test -f mailname || echo $vserver > mailname
chxid -c $xid mailname

# Configuration 'hosts'
if [ -f hosts ] ; then
	if [ -n "$old_ip" ] ; then
		local hosts="$(cat hosts |awk -v ip1=$old_ip -v ip2=$ip '{if ($1==ip1) { $1=ip2 } ; {print $0}}')"
		echo "$hosts" > hosts
	fi
else
	echo "$ip $vserver.$domain $vserver" > hosts
	echo "$ip localhost.localdomain localhost" >> hosts
fi
chxid -c $xid hosts

if [ $ifid -eq 0 ] ; then
	#Configuration 'resolv.conf' uniquement pour l'interface primaire

	cd ${_VSTOOLS_BASE}/$pool/$vserver/etc/
	local resolv="$(cat resolv.conf 2>/dev/null |egrep -v "^$|^search.*|^domain.*|^nameserver.*")"
	echo "domain $domain" > resolv.conf
	echo "search $searchdomains" >> resolv.conf
	local nameserver
	for nameserver in $nameservers ; do
		echo "nameserver $nameserver" >> resolv.conf
	done
	echo "$resolv" >> resolv.conf
	chxid -c $xid resolv.conf
fi

# Reconfiguration a chaud des interfaces si necessaire
if vmIsRunningQuiet $vserver ; then
	[ -n "$old_ip" ] && logexec /sbin/ip addr del dev ${dev} ${old_ip}/${old_prefix}
	logexec /sbin/ip addr add dev ${dev} label ${dev}:${xid}-${ifid} broadcast ${bcast} ${ip}/${prefix}
	logexec naddress --nid $vserver $(cat ${_VSERVERS_CONF}/$vserver/interfaces/*/ip |sed -e "s/^/--set --ip /g")
fi

return 0

}

function netIpAdd
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	netIpAdd

SYNOPSIS

	netIpAdd <vserver> <ip>

DESCRIPTION

	Add <ip> address to <vserver>.

	(ifid) is automaticaly choosen from free ones.
	
	Return code: 0 if success.

EOF
exit 1
fi

local vserver=$1
[ -n "$vserver" ] || { error "$E_160" ; return 1 ; }
dirExists ${_VSERVERS_CONF}/$vserver/interfaces || return 1

local ip=$2
netIpCheckValue $ip || return 1

local ifid=$(echo "$(ls ${_VSERVERS_CONF}/$vserver/interfaces 2>/dev/null ; seq 0 9)" |sort -n |uniq -u |head -n 1)
[ -n "$ifid" ] || { log "$E_100 (ifid)" ; return 1 ; }

netIfAdd $vserver $ifid
netIpSet $vserver $ip ifid=$ifid

return 0

}


function netIpReset
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	netIpReset

SYNOPSIS

	netIpReset <vserver> [options]

OPTIONS

	ifid=<interface id>

DESCRIPTION

	Check an rewrite ip configuration of <vserver>.

	When (ifid) is not specified, it will be assumed as '0'.

	Return code: 0 if success.

EOF
exit 1
fi

local vserver=$1
[ -n "$vserver" ] || { error "$E_160" ; return 1 ; }
dirExists ${_VSERVERS_CONF}/$vserver || return 1

local ip=$(netIpGet $vserver $2) || return 1
netIpSet $vserver $ip $2

return 0

}

function netTestPing
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	netTestPing

SYNOPSIS

	netTestPing <ip/host>

DESCRIPTION

	Send one 'echo request' to  <ip/host> (wait about 100ms).

	Return code: 0 if success.

EOF
exit 1
fi

local ip=$1
[ -n "$ip" ] || { log "$E_100 (ip|host)" ; return 1 ; }

# 'echo request': attente 100 millisecondes
fping -c1 -t100 $ip 2>/dev/null >/dev/null && return 0

return 1

}

function netTestSsh
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	netTestSsh

SYNOPSIS

	netTestSsh <ip/host>

DESCRIPTION

	Try to open ssh connexion to <ip/host>.

	Return code: 0 if success.

EOF
exit 1
fi

local ip=$1
[ -n "$ip" ] || { log "$E_100 (ip|host)" ; return 1 ; }

ssh -o "NumberOfPasswordPrompts 0" -o "StrictHostKeyChecking yes" $ip 2>/dev/null >/dev/null && return 0

return 1

}

function netTestRsync
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	netTestRsync

SYNOPSIS

	netTestRsync <ip/host>

DESCRIPTION

	Try to open rsync connexion to <ip/host>.

	Return code: 0 if success.

EOF
exit 1
fi

local ip=$1
[ -n "$ip" ] || { log "$E_100 (ip|host)" ; return 1 ; }

rsync $ip:: 2>/dev/null >/dev/null  && return 0

return 1

}

function netTestDev
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	netTestDev

SYNOPSIS

	netTestDev <network device>

DESCRIPTION

	Check if <network device> is enabled and carrier available.

	Return code: 0 if success.

EOF
exit 1
fi

local dev=$1
[ -n "$dev" ] || { log "$E_100 (network device)" ; return 1 ; }

grep "^1$" /sys/class/net/$dev/carrier 2>/dev/null >/dev/null && return 0

return 1

}

function netVlanSelect
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	netVlanSelect

SYNOPSIS

	netVlanSelect <ip>

DESCRIPTION

	Parse networks configuration file ('${_VSTOOLS_CONF}/networks.cf')

	Return matching vlan id that matching with <ip>.

	Return code: 0 if success.

EOF
exit 1
fi

local ip=$1
netIpCheckValue $ip || return 1

local vid cidr

if netIpIsv6 $ip ; then

	# IPv6 -> comparaison sur /64 uniquement

	for vid in $(echo ${_KNOWN_VLANS} |sed -e "s/,/ /g") ; do

		if netIpIsv6 ${_NET[$vid]} ; then
			if [ "$(echo $ip |sed -e "s/::/:0:/g" |cut -d: -f-5)" == "$(echo ${_NET[$vid]} |sed -e "s/::/:0:/g" |cut -d: -f-5)" ] ; then
				echo $vid 
				return 0
			fi
		fi

	done

else

	for vid in $(echo ${_KNOWN_VLANS} |sed -e "s/,/ /g") ; do
		
		cidr=${_CIDR[$vid]}
		test -z "$cidr" && cidr=${_CIDR[0]}
		test -z "$cidr" && abort "$E_100 (cidr)"
		
		ipcalc -nb $ip/$cidr |egrep -i "^Network: +${_NET[$vid]}/$cidr +$" 2>/dev/null >/dev/null
		if [ $? -eq 0 ] ; then
			echo $vid
			return 0
		fi

	done

fi

return 1

}
