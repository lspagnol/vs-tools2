function xid
{

if [ "$1" == "help" ] ; then cat<<EOF

DESCRIPTION

	'xid' related functions
	 
SUB-FUNCTIONS

	xidValueCheck <xid>

	xidCounterGet
	xidCounterSet
	
	xidVserverGet <vserver>
	xidVserverSet <vserver> <xid>
	xidVserverSpread <vserver>

USAGE

	For help about sub-functions, use '<sub-function> help'.

EOF
exit 1
fi

}

function xidValueCheck
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	xidValueCheck

SYNOPSIS

	xidValueCheck <xid>

DESCRIPTION

	Check <xid> value.
	
	<xid> must be numerical value, '2 < xid > 49151'.
	
	Return code: 0 if success.

EOF
exit 1
fi

local xid="$1"

# Le xid ne doit pas etre vide
test -n "$xid" || { log "$E_100 (xid)" ; return 1 ; }

# Le xid ne doit contenir que des chiffres
[ "$(echo "$xid" |tr -d "[0-9]")" ] && { log "$E_102 ($xid)" ; return 1 ; }

# Le xid doit etre compris entre 2 et 49151
[ $xid -lt 2 ] || [ $xid -gt 49151 ] && { log "$E_104 ($xid)" ; return 1 ; }

return 0

}

function xidCounterGet
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	xidCounterGet

SYNOPSIS

	xidCounterGet

DESCRIPTION

	Read, check and return <xid> from file that MUST exists.
	
	File is '${_VSERVERS_CONF}/.defaults/context.next'.
	
	Return code: 0 if success.

EOF
exit 1
fi

fileExists ${_VSERVERS_CONF}/.defaults/context.next || return 1

cat ${_VSERVERS_CONF}/.defaults/context.next

return 0

}

function xidCounterSet
{
	
if [ "$1" == "help" ] ; then cat<<EOF

NAME

	xidCounterSet

SYNOPSIS

	xidCounterSet <xid>

DESCRIPTION

	Check and write <xid> to file that MUST exists.
	
	File is '${_VSERVERS_CONF}/.defaults/context.next'.

	Return code: 0 if success.

EOF
exit 1
fi

fileExists ${_VSERVERS_CONF}/.defaults/context.next || return 1

local xid=$1
xidValueCheck $xid || return 1

echo $xid > ${_VSERVERS_CONF}/.defaults/context.next

return 0

}

function xidVserverGet
{
	
if [ "$1" == "help" ] ; then cat<<EOF

NAME

	xidVserverGet

SYNOPSIS

	xidVserverGet <vserver>

DESCRIPTION

	Read, check and return <xid> from <vserver> configuration.
	
	File is '${_VSERVERS_CONF}/<vserver>/context'.

	Return code: 0 if success.

EOF
exit 1
fi

local vserver=$1
[ -n "$vserver" ] || { error "$E_160" ; return 1 ; }

fileExists ${_VSERVERS_CONF}/$vserver/context || return 1

cat ${_VSERVERS_CONF}/$vserver/context

return 0

}

function xidVserverSet
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	xidVserverSet

SYNOPSIS

	xidVserverSet <vserver> <xid>

DESCRIPTION

	Check and write <xid> to <vserver> configuration.
	
	File is '${_VSERVERS_CONF}/<vserver>/context'.
	<xid> is also writen on 'ncontext' and 'tag' files.

	Return code: 0 if success.

EOF
exit 1
fi

local vserver=$1
[ -n "$vserver" ] || { error "$E_160" ; return 1 ; }
vmIsStopped $vserver || return 1

local xid=$2
xidValueCheck $xid || return 1

dirExists ${_VSERVERS_CONF}/$vserver || return 1
cd ${_VSERVERS_CONF}/$vserver

local file
for file in context ncontext tag ; do
	echo $xid > $file
done

return 0

}

function xidVserverSpread
{
if [ "$1" == "help" ] ; then cat<<EOF

NAME

	xidVserverSpread

SYNOPSIS

	xidVserverSpread <vserver>

DESCRIPTION

	Check and spread XID to <vserver> base.
	
	XID is read from <vserver> configuration.

	Return code: 0 if success.

EOF
exit 1
fi

local vserver=$1
[ -n "$vserver" ] || { error "$E_160" ; return 1 ; }
vmIsStopped $vserver || return 1

local xid=$(xidVserverGet $vserver) || return 1
local pool=$(vmGetPoolName $vserver) || return 1

dirExists ${_VSTOOLS_BASE}/$pool/$vserver || return 1

logexec chxid -c $xid -R ${_VSTOOLS_BASE}/$pool/$vserver

return $?

}
