function attr
{

if [ "$1" == "help" ] ; then cat<<EOF

DESCRIPTION

	'attr' related functions

SUB-FUNCTIONS

	attrGet <vserver> <bcaps|ccaps|flags>
	attrSet <vserver> <bcaps|ccaps|flags> <attribute>
	
	attrSetDefaults <vserver>

USAGE

	For help about sub-functions, use '<sub-function> help'.

EOF
exit 1
fi

}

function attrGet
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	attrGet

SYNOPSIS

	attrGet <vserver> <bcaps|ccaps|flags>

DESCRIPTION

	Get attributes of type bcaps, ccaps or flags from <vserver>.

	See http://linux-vserver.org/Capabilities_and_Flags for more help.

	Return code: 0 if success.

EOF
exit 1
fi

local vserver=$1
[ -n "$vserver" ] || { error "$E_160" ; return 1 ; }
dirExists ${_VSERVERS_CONF}/$vserver || return 1
local xid=$(xidVserverGet $1) || return 1

local type=$2
[ -n "$type" ] || { error "$E_100 'ccaps|bcaps|flags'" ; return 1 ; }
echo " ccaps bcaps flags " |grep " $type " >/dev/null || { error "$E_104 '$type'" ; return 1 ; }

if vmIsRunningQuiet $vserver ; then

	local attrs=$(echo $(vattribute --xid $xid --get))

	case $type in
		ccaps)
			echo $attrs |sed -e "\
			y/ABCDEFGHIJKLMNOPQRSTUVWXYZ/abcdefghijklmnopqrstuvwxyz/;\
			s/^bcapabilities:.*ccapabilities://g;\
			s/flags:.*//g;\
			s/ //g;\
			s/,/\n/g" |sort |grep -v "^$"
		;;
		bcaps)
			echo $attrs |sed -e "\
			y/ABCDEFGHIJKLMNOPQRSTUVWXYZ/abcdefghijklmnopqrstuvwxyz/;\
			s/^bcapabilities://g;\
			s/ccapabilities:.*//g;\
			s/ //g;\
			s/,/\n/g" |sort |grep -v "^$"
		;;
		flags)
			echo $attrs |sed -e "\
			y/ABCDEFGHIJKLMNOPQRSTUVWXYZ/abcdefghijklmnopqrstuvwxyz/;\
			s/^bcapabilities:.*flags://g;\
			s/ //g;\
			s/,/\n/g" |sort |grep -v "^$"
		;;
	esac

else

	case $type in
		ccaps)
			{ cat ${_VSERVERS_CONF}/$vserver/ccapabilities 2>/dev/null ; echo "$_VSERVERS_CCAPS" |sed -e "s/,/\n/g" ; } \
				|sort |uniq |sed -e "s/^~//g" |sort |uniq -u |grep -v "^$"
		;;
		bcaps)
			{ cat ${_VSERVERS_CONF}/$vserver/bcapabilities 2>/dev/null ; echo "$_VSERVERS_BCAPS" |sed -e "s/,/\n/g" ; } \
				|sort |uniq |sed -e "s/^~//g" |sort |uniq -u |grep -v "^$"
		;;
		flags)
			{ cat ${_VSERVERS_CONF}/$vserver/flags 2>/dev/null ; echo "$_VSERVERS_FLAGS" |sed -e "s/,/\n/g" ; } \
				|sort |uniq |sed -e "s/^~//g" |sort |uniq -u |grep -v "^$"
		;;
	esac

fi

return 0

}

function attrSet
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	attrSet

SYNOPSIS

	attrSet <vserver> <bcaps|ccaps|flags> <attribute>

DESCRIPTION

	Set <attributes> of type bcaps, ccaps or flags to <vserver>.

	See http://linux-vserver.org/Capabilities_and_Flags for more help.

	Return code: 0 if success.

EOF
exit 1
fi

local vserver=$1
[ -n "$vserver" ] || { error "$E_160" ; return 1 ; }
dirExists ${_VSERVERS_CONF}/$vserver || return 1
local xid=$(xidVserverGet $1) || return 1

local type=$2
[ -n "$type" ] || { error "$E_100 'ccaps|bcaps|flags'" ; return 1 ; }
echo " ccaps bcaps flags " |grep " $type " >/dev/null || { error "$E_104 '$type'" ; return 1 ; }

local attrs=$(echo $3 |sed -e "y/ABCDEFGHIJKLMNOPQRSTUVWXYZ/abcdefghijklmnopqrstuvwxyz/")
[ -n "$attrs" ] || { error "$E_100 'attrs'" ; return 1 ; }
attrs="$(echo $attrs |sed -e "s/,/ /g")"

# Verification des attributs
for attr in $attrs ; do
	egrep "^${attr}$|${attr#\~}$" ${_VSTOOLS_BIN}/$type >/dev/null || { error "$E_104 '$attr'" ; return 1 ; }
done

type=${type%s} # suppression du 's' a la fin de la chaine

# Traitement 'a chaud'
if vmIsRunningQuiet $vserver ; then
	logexec vattribute --xid $xid --set --$type $attrs || return 1
fi

# Modification persistante -> les attributs sont declares explicitement

local file
case $type in
	ccap)
		file=${_VSERVERS_CONF}/$vserver/ccapabilities
	;;
	bcap)
		file=${_VSERVERS_CONF}/$vserver/bcapabilities
	;;
	flag)
		file=${_VSERVERS_CONF}/$vserver/flags
	;;
esac
touch $file

# Creation du filtre d'attributs
local defaults="${_VSERVERS_BCAPS//,/ } ${_VSERVERS_CCAPS//,/ },${_VSERVERS_FLAGS//,/ }"

local attr content
for attr in $attrs ; do

	content="$(cat $file)"
	content="$(echo "$content" |egrep -v "^${attr}$|^\~${attr}$|^${attr#\~}$")"

	echo "$content" > $file

	if [ "$(echo $attr |grep "^~")" ] ; then
		# Les attributs a supprimer peuvent etre ajoutes a la configuration.
		echo " $defaults " |grep " ${attr#\~} " >/dev/null && echo "$attr" >> $file
	else
		# Les attributs par defaut du systeme ne doivent pas etre ajoutes a la configuration.
		echo " $defaults " |grep " $attr " >/dev/null || echo "$attr" >> $file
	fi

done

return 0

}

function attrSetDefaults
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	attrSetDefaults

SYNOPSIS

	attrSetDefaults <vserver>

DESCRIPTION

	Set all default attributes to <vserver>. Theses attributes are added
	or removed from default ones.
	
	'Util-Vserver' defaults: ${_VSTOOLS_CONF}/util-vserver.cf
		-> _VSERVERS_BCAPS _VSERVERS_CCAPS _VSERVERS_FLAGS

	'vs-tools' defaults: ${_VSTOOLS_CONF}/build.cf
		-> _DEFAULT_BCAPS, _DEFAULT_CCAPS, _DEFAULT_FLAGS

	See http://linux-vserver.org/Capabilities_and_Flags for more help.

	Return code: 0 if success.

EOF
exit 1
fi

local vserver=$1
[ -n "$vserver" ] || { error "$E_160" ; return 1 ; }
dirExists ${_VSERVERS_CONF}/$vserver || return 1

[ -n "${_DEFAULT_BCAPS}" ] && attrSet $vserver bcaps ${_DEFAULT_BCAPS}
[ -n "${_DEFAULT_CCAPS}" ] && attrSet $vserver ccaps ${_DEFAULT_CCAPS}
[ -n "${_DEFAULT_FLAGS}" ] && attrSet $vserver flags ${_DEFAULT_FLAGS}

return 0
	
}
