function cluster
{

if [ "$1" == "help" ] ; then cat<<EOF

DESCRIPTION

	'cluster' related functions

SUB-FUNCTIONS

	clusterHeartbeatWrite
	clusterHeartbeatRead <node>
	clusterHeartbeatHealth <node>

	clusterPoolStop <pool>
	clusterPoolStart <pool>

	clusterCollector [options]

USAGE

	For help about sub-functions, use '<sub-function> help'.

EOF
exit 1
fi

}

function clusterPoolStop
{

if [ "$1" == "help" ] ; then cat<<EOF
NAME

	clusterPoolStop

SYNOPSIS

	clusterPoolStop <pool>

DESCRIPTION

	Stop and disable <pool> on this node.

	Return code: 0 if success.

EOF
exit 1
fi

local pool=$1
poolExists $pool || return 1

local owner=$(poolGetOwner $pool)
[ "$owner" == "$HOSTNAME" ] || { error "$E_217 ($HOSTNAME -> $pool @ $owner)" ; return 1 ; }

poolStop $pool
poolDisable $pool || return 1

return 0

}

function clusterPoolStart
{

if [ "$1" == "help" ] ; then cat<<EOF
NAME

	clusterPoolStart

SYNOPSIS

	clusterPoolStart <pool>

DESCRIPTION

	Catch, enable and start <pool> on this node.

	Return code: 0 if success.

EOF
exit 1
fi

local pool=$1
poolExists $pool || return 1

local owner=$(poolGetOwner $pool)
[ "$owner" == "$HOSTNAME" ] && { error "$E_218 ($pool @ $owner)" ; return 1 ; }

poolCatch $pool || return 1
poolEnable $pool || return 1
poolStart $pool || return 1

return 0

}

function clusterHeartbeatWrite
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	clusterHeartbeatWrite

SYNOPSIS

	clusterHeartbeatWrite

DESCRIPTION

	Write heartbeat datas of local node.

	Return code: 0 if success.

EOF
exit 1
fi

# Ne pas lancer deux instances en meme temps
dotlockfile -p -r 1 -l /var/lock/clusterHeartbeatWrite.lock || return 0

local node error
local hb_node=$(hostname -s)
local date=$(date)
local hb_time=$(date -d "$date" +"%F %T")
local hb_timestamp=$(date -d "$date" +%s)
local hb_uptime=$(cat /proc/uptime)
local hb_loadavg=$(cat /proc/loadavg)
local hb_vservers_running=$(echo $(ls ${_VSERVERS_RUN}/ 2>/dev/null))
local hb_pools_enabled=$(echo $(lvs --noheadings --separator / -o vg_name,lv_name,lv_attr |sed -e "s/ *//g" |egrep "^.+/.+/....ao$" |cut -d"/" -f-2))
local hb_rss_used=$(echo $(cat /proc/virtual/*/limit 2>/dev/null |grep "^RSS:" |awk '{print $2}') |sed -e "s/ /+/g" |bc)
if [ ! -z  $hb_rss_used ] ; then
	hb_rss_used=$(( $hb_rss_used * ${_LINUX_PAGESIZE} / 1048576 ))
else
	hb_rss_used=0
fi
hb_rss_used="${hb_rss_used}/${_LINUX_RSS}"
local hb_nodes_ranking=($(
	for node in $(ls ${_VSTOOLS_CACHE}/cluster/) ; do
		if [ -f ${_VSTOOLS_CACHE}/cluster/$node/stats/heartbeat ] ; then
			eval $(cat ${_VSTOOLS_CACHE}/cluster/$node/stats/heartbeat |sed -e "s/^hb_/local rhb_/g")
			if [ $rhb_health -eq 1 ] ; then
				echo -n "$node "
				rhb_loadavg=($rhb_loadavg)
				echo "((${rhb_loadavg[0]} * 15) + (${rhb_loadavg[1]} * 5) + ${rhb_loadavg[2]}) * 100" |bc
			fi
		fi
	done |awk '{print $2" "$1}' |sort -n |awk '{print $2}' |grep -v "^$hb_node$"
	))
local hb_pools_rw=""

# Test de l'acces R/W aux pools
local pools=$(cat /proc/mounts |awk '{print $2}' |grep ^${_VSTOOLS_BASE})
if [ -n "$pools" ] ; then
	local pool
	for pool in $pools ; do
		touch $pool/heartbeat 2>/dev/null
		if [ $? -eq 0 ] ; then
			rm $pool/heartbeat
		else
			log "RW error on /dev/$pool"
			error=1
		fi
	done
	[ -z $error ] && hb_pools_rw=1 || hb_pools_rw=0 ; unset error
else # Pas de pool actif
	hb_pools_rw=-1
fi

# Verification porteuse reseau sur toutes les interfaces actives
local nic
for nic in $(ls /sys/class/net/ |egrep "^eth[0-9]+$") ; do
	grep "^1$" /sys/class/net/$nic/carrier 2>/dev/null >/dev/null
	if [ $? -eq 1 ] ; then
		log "carrier down on $nic"
		error=1
	fi
done
[ -z $error ] && hb_ifs_carrier=1 || hb_ifs_carrier=0 ; unset error

# Verification passerelles
fping -c1 -t100 $(ip route list table main |grep ^default |awk '{print $3}') 2>/dev/null >/dev/null
if [ $? -ne 0 ] ; then
	error=1
	log "gateway unreachable $gateway"
fi
for gateway in $(cat ${_VSERVERS_CONF}/*/interfaces/*/gateway 2>/dev/null |sort |uniq) ; do
	fping -c1 -t100 $gateway 2>/dev/null >/dev/null
	if [ $? -ne 0 ] ; then
		log "gateway unreachable $gateway"
		error=1
	fi
done
[ -z $error ] && hb_gws_alive=1 || hb_gws_alive=0 ; unset error

# ToDo: Etat DRDB
#if [ -b /dev/drdb0 ] ; then # drbd actif
#	local hb_drbd=$(drbdsetup /dev/drbd0 state 2>/dev/null)
#	# Etats possibles: Primary/Secondary/Unknown
#fi

# Etat general du noeud -> definition du test dans /etc/vs-tools/cluster.cf
eval $_HEALTH && hb_health=1 || hb_health=0

# Mode block
local hb_block_write=0
if [ -n "${_HB_BLOCK_DEV}" ] && [ -b ${_HB_BLOCK_DEV} ] && [ -n "${_HB_BLOCK_SIZE}" ]  ; then

	# Recherche d'un numero d'index de block lvm
	local i ; for ((i=1; i <= ${#_HB_BLOCK_IDX[@]} ; i++)) ; do
		if [ "${_HB_BLOCK_IDX[$i]}" == "$hb_node" ] ; then
			local idx=$i ; local hb_block_write=1 ; break
		fi
	done
	
fi

# Ecriture dans le cache
cat<<EOF>/tmp/heartbeat
hb_node="$hb_node"
hb_time="$hb_time"
hb_timestamp="$hb_timestamp"
hb_uptime="$hb_uptime"
hb_loadavg="$hb_loadavg"
hb_rss_used="$hb_rss_used"
hb_vservers_running="$hb_vservers_running"
hb_pools_enabled="$hb_pools_enabled"
hb_pools_rw="$hb_pools_rw"
hb_ifs_carrier="$hb_ifs_carrier"
hb_gws_alive="$hb_gws_alive"
hb_health="$hb_health"
hb_block_write="$hb_block_write"
hb_nodes_ranking="${hb_nodes_ranking[*]}"
EOF
#ToDo: hb_drbd="$hb_drbd"
cp /tmp/heartbeat ${_VSTOOLS_CACHE}/stats/heartbeat

if [ -n "$idx" ] ; then
	# Index trouve, ecriture directe en mode block

	local offset=$(( $idx * ${_HB_BLOCK_SIZE} ))

	# RAZ du bloc
	dd bs=1K count=1 seek=$offset of=${_HB_BLOCK_DEV} </dev/zero 2>/dev/null

	# Ecriture des stats sur le LV
	dd bs=1K count=1 seek=$offset of=${_HB_BLOCK_DEV} </tmp/heartbeat 2>/dev/null
		
fi

# Arret des vserveurs et desactivation des volumes en cas d'erreur:
# - le 'fence' doit etre explicitement configure (cluster.cf)
# - le noeud local DOIT etre en erreur
# - il doit y avoir AU MOINS UN NOEUD DISPONIBLE sur le cluster
# ==> Ne rien faire en cas de defaillance locale si aucun noeud ne peut
#     prendre le relais.

if [ $hb_health -eq 0 ] && [ "$hb_pools_enabled" != "" ] ; then
	if [ ! -f /var/run/fence_timestamp ] ; then
		echo $hb_timestamp > /var/run/fence_timestamp
	fi
else
	if [ -f /var/run/fence_timestamp ] ; then
		rm /var/run/fence_timestamp
	fi
fi
	
if [ "$_FENCE" == "1" ] ; then

	if [ ps a |grep " ${_FENCE_SUSPEND} " |grep -v grep 2>/dev/null >/dev/null ] ; then # le fencing est suspendu pendant les sequences de demarrage et d'arret

		log "fencing is not allowed during start/stop sequences"

	else

		if [ -f /var/run/fence_timestamp ] && [ $hb_timestamp -ge $(( $(cat /var/run/fence_timestamp) + $_GRACEFULL )) ] ; then
		
			local node
			for node in $(echo " $_NODES " |sed -e "s/,/ /g ; s/ $hb_node //g") ; do
				(
					eval $(clusterHeartbeatHealth $node) # etat du noeud distant
					if [ $hb_node_alive -eq 1 ] && [ $hb_health -eq 1 ] ; then
						touch /var/run/fence
						log "node '$node' is available, fencing is allowed"
					fi
				) &
			done
			wait
		
			if [ -f /var/run/fence ] ; then
				local pool
				for pool in $hb_pools_enabled ; do
					(
						poolStop $pool
						poolDisable $pool
					) &
				done
				wait
				rm /var/run/fence
			else
				log "no available node found, fencing is not allowed"
			fi
		
		fi
	
	fi

fi

dotlockfile -u /var/lock/clusterHeartbeatWrite.lock

return 0

}

function clusterHeartbeatRead
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	clusterHeartbeatRead

SYNOPSIS

	clusterHeartbeatRead <node>

DESCRIPTION

	Display heartbeat datas of <node>.

	Return code: 0 if success.

EOF
exit 1
fi

local node=$1
[ -n "${_NODES}" ] || { error "$E_100 (_NODES)" ; return 1 ; }
[ -n "$node" ] || { error "$E_100 (node)" ; return 1 ; }
echo " ${_NODES//,/ } " |grep " $node " > /dev/null || { error "$E_104 ($node)" ; return 1 ; }

# Ne pas lancer deux procedures en meme temps
dotlockfile -p -r 1 -l /var/lock/clusterHeartbeatRead.lock || return 0

# Priorite au mode reseau (nc / xinetd)
# test: ping avec 100 ms d'attente
if fping -c1 -t100 $node 2>/dev/null >/dev/null ; then

	nc $node ${_VSTOOLS_HB_PORT} > /tmp/heartbeat.$node 2>/dev/null

	if [ $? -eq 0 ] ; then

		# Filtrage du resultat (-> injection code) et affichage
		echo "hb_block_read=\"0\""
		cat /tmp/heartbeat.$node |tr -d "\\\&\`\$\|\!\(\)\{\}"
		rm /tmp/heartbeat.$node

	else

		false

	fi
	
else

	false

fi

if [ $? -ne 0 ] ; then # echec par le reseau, tentative en mode bloc

	if [ -n "${_HB_BLOCK_DEV}" ] && [ -b ${_HB_BLOCK_DEV} ] && [ -n "${_HB_BLOCK_SIZE}" ] ; then

		# Recherche d'un numero d'index de block lvm
		local i ; for ((i=1; i <= ${#_HB_BLOCK_IDX[@]} ; i++)) ; do
			if [ "${_HB_BLOCK_IDX[$i]}" == "$node" ] ; then
				local idx=$i ; break
			fi
		done

	fi

	if [ -n "$idx" ] ; then # Index trouve

		local offset=$(( $idx * ${_HB_BLOCK_SIZE} ))

		# Lecture des stats sur le bloc
		# Filtrage du resultat (-> injection code) et affichage
		echo "hb_block_read=\"1\""
		dd bs=1K count=1 skip=$offset if=${_HB_BLOCK_DEV} 2>/dev/null |tr -d "\\\&\`\$\|\!\(\)\{\}"

	else

		dotlockfile -u /var/lock/clusterHeartbeatRead.lock
		return 1

	fi

fi

dotlockfile -u /var/lock/clusterHeartbeatRead.lock
return 0

}

function clusterHeartbeatHealth
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	clusterHeartbeatHealth

SYNOPSIS

	clusterHeartbeatHealth <node>

DESCRIPTION

	Display hearth datas of <node>.

	Return code: 0 if success.

EOF
exit 1
fi

local node=$1
[ -n "${_NODES}" ] || { error "$E_100 (_NODES)" ; return 1 ; }
[ -n "$node" ] || { error "$E_100 (node)" ; return 1 ; }
echo " ${_NODES//,/ } " |grep " $node " > /dev/null || { error "$E_104 ($node)" ; return 1 ; }

# Ne pas lancer deux procedures en meme temps
dotlockfile -p -r 1 -l /var/lock/clusterHeartbeatHealth.lock || return 0

local hb_node_alive=0
touch /tmp/health.$node.1 /tmp/health.$node.2

# 1ere passe
clusterHeartbeatRead $node > /tmp/health.$node.1

# 1 battement toutes les 2 secondes -> 3 secondes d'attente
sleep 3

# 2eme passe
clusterHeartbeatRead $node > /tmp/health.$node.2

if [ $? -eq 0 ] ; then # la lecture c'est bien passee
	diff /tmp/health.$node.1 /tmp/health.$node.2 2>/dev/null >/dev/null
	if [ $? -ne 0 ] ; then # le fichier a change -> noeud actif
		hb_node_alive=1
	fi
else
	# recuperation du dernier etat connu dans le cache
	cat ${_VSTOOLS_CACHE}/cluster/$node/stats/heartbeat 2>/dev/null > /tmp/health.$node.2
fi

# Filtrage du resultat (-> injection code) et affichage
echo "hb_node_alive=\"$hb_node_alive\""
cat /tmp/health.$node.2 |tr -d "\\\&\`\$\|\!\(\)\{\}"

rm /tmp/health.$node.1 /tmp/health.$node.2

dotlockfile -u /var/lock/clusterHeartbeatHealth.lock

return 0

}

function clusterCollector
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	clusterCollector

SYNOPSIS

	clusterCollector [options]

OPTIONS

	nodes=<node1,node2...>

DESCRIPTION

	Get vservers datas (conf, cache, stats) from all nodes via rsync.

	Return code: 0 if success.

EOF
exit 1
fi

[ -n "{_NODES}" ] || { error "$E_100 (_NODES)" ; return 1 ; }

eval local $(echo $1 |egrep "^nodes=") >/dev/null
local nodes ; test -n "$nodes" && nodes=${nodes//,/ } || nodes=${_NODES//,/ }

# Ne pas lancer deux procedures en meme temps
dotlockfile -p -r 1 -l /var/lock/clusterCollector.lock || return 0

# Consolidation des noeuds
for node in $nodes ; do

 # lancer un sous-shell par noeud en parallele
 
 (
	
	# les nouvelles variables n'affectent pas le shell parent
	
	timestamp=$(date +%s)

	test -d ${_VSTOOLS_CACHE}/cluster/$node || mkdir ${_VSTOOLS_CACHE}/cluster/$node 

	# 1er test: ping avec 100 ms d'attente
	if fping -c1 -t100 $node 2>/dev/null >/dev/null ; then
		
		# 2eme test: verifier si rsyncd repond sur l'hote distant
		if rsync $node:: 2>/dev/null >/dev/null ; then

			for dir in conf run cache stats ; do
			
				# Synchronisation sur le cache cluster -> Notifier les erreurs
				rsync -aq --delete $node::$dir/ ${_VSTOOLS_CACHE}/cluster/$node/$dir/ 2>/dev/null >/dev/null || error=1
			
			done
			
			# Pas d'erreur -> mise a jour du timestamp de synchro REUSSIE
			test -z "$error" && echo $timestamp > ${_VSTOOLS_CACHE}/cluster/$node/cluster-collector.good
			
		fi

	fi
	
	# Mise a jour du timestamp de synchro
	echo $timestamp > ${_VSTOOLS_CACHE}/cluster/$node/cluster-collector.done
	
 ) &

done
	
wait

dotlockfile -u /var/lock/clusterCollector.lock

return 0

}
