___tag="vs-tools[$$]"
___message="Start sequence for vserver '$vserver':"

function ___logger
{
logger -t "$___tag" "$___message $1"
}

___logger "BEGIN"

if test -f $__CONFDIR/$vserver/hidden ; then
	___logger "warning: vserver is hidden on this node"
	___logger "ABORTED"
	exit 0
fi

# Modification version majeure du noyau pour le vserveur
___kver=$(uname -r)
echo ${___kver%-*} > ${__CONFDIR}/${vserver}/uts/release

# Recuperation de la liste des interfaces configurees pour ce vserveur
___ifids=$(ls $__CONFDIR/$vserver/interfaces/)
___logger "interface(s) ID(s): $___ifids"

# Recuperation de la configuration des interfaces sous forme de tableau
for ___ifid in $___ifids ; do

	___interface[$___ifid]=$(cat $__CONFDIR/$vserver/interfaces/$___ifid/dev)
	___vlan[$___ifid]=${___interface[$___ifid]#*.}
	___device[$___ifid]=${___interface[$___ifid]%.*}

	___ip[$___ifid]=$(cat ${__CONFDIR}/${vserver}/interfaces/$___ifid/ip)
	___net[$___ifid]=$(cat ${__CONFDIR}/${vserver}/interfaces/$___ifid/net)
	___prefix[$___ifid]=$(cat ${__CONFDIR}/${vserver}/interfaces/$___ifid/prefix)

	if [ -f ${__CONFDIR}/${vserver}/interfaces/$___ifid/table ] ; then
		___table[$___ifid]=$(cat ${__CONFDIR}/${vserver}/interfaces/$___ifid/table)
	fi
	
	if [ -f ${__CONFDIR}/${vserver}/interfaces/$___ifid/gateway ] ; then
		___gateway[$___ifid]=$(cat ${__CONFDIR}/${vserver}/interfaces/$___ifid/gateway)
	fi

	___logger "interface $___ifid: interface=${___interface[$___ifid]} ip=${___ip[$___ifid]} net=${___net[$___ifid]}/${___prefix[$___ifid]} gateway=${___gateway[$___ifid]} table=${___table[$___ifid]}"
	
	# 'echo request': attente 100 millisecondes, interruption sequence
	# demarrage en cas de reponse (adresse en cours d'utilisation
	if fping -c1 -t100 ${___ip[$___ifid]} 2>/dev/null >/dev/null ; then
		echo "error: already in use somewhere ip '${___ip[$___ifid]}'"
		logger "ABORTED"
		exit 1
	fi
	
done

