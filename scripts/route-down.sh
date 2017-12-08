for ___ifid in $___ifids ; do

	if [ "$(ip rule |grep "from ${___net[$___ifid]}/${___prefix[$___ifid]} lookup ${___table[$___ifid]}")" ] ; then
		# La route est active

		# Mise en place du verrou (15 secondes d'attente maxi)
		if ! dotlockfile -p -r 2 -l /var/lock/route-${___interface[$___ifid]} ; then
			___logger "error: unable to lock '/var/lock/route-${___interface[$___ifid]}'"
			___logger "error: route-down.sh: aborted"
		else
			# On verifie a nouveau l'etat de la route
			if [ "$(ip rule |grep "from ${___net[$___ifid]}/${___prefix[$___ifid]} lookup ${___table[$___ifid]}")" ] ; then

				# La route ne peut etre supprimee que si plus aucune ip virtuelle ne l'utilise
				if [ ! "$(ip addr show ${___interface[$___ifid]} 2>/dev/null|grep " scope global ${___interface[$___ifid]}:")" ] ; then
					ip rule del from ${___net[$___ifid]}/${___prefix[$___ifid]} table ${___table[$___ifid]}
				fi

			fi

			dotlockfile -u /var/lock/route-${___interface[$___ifid]}

		fi
	fi
	
done
