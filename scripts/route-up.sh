for ___ifid in $___ifids ; do

	if test -n "${___table[$___ifid]}" ; then
	# Mise en place d'une table de routage pour ce reseau

		if ! ip rule |egrep "from *${___net[$___ifid]}/${___prefix[$___ifid]} *lookup *${___table[$___ifid]} *" > /dev/null ; then
		# La route n'existe pas -> debut de la procedure d'activation
		
			# Mise en place du verrou (15 secondes d'attente maxi)
			if ! dotlockfile -p -r 2 -l /var/lock/route-${___interface[$___ifid]} ; then
				___logger "error: route-up.sh: unable to lock '/var/lock/route-${___interface[$___ifid]}'"
				___logger "error: route-up.sh: aborted"
			else

				# On verifie a nouveau l'etat de la route
				if ! ip rule |egrep "from *${___net[$___ifid]}/${___prefix[$___ifid]} *lookup *${___table[$___ifid]} *" > /dev/null ; then
			
					# Ajout de la route
					if ! ip rule add from ${___net[$___ifid]}/${___prefix[$___ifid]} table ${___table[$___ifid]} 2>/dev/null >/dev/null ; then
						___logger "error: route-up.sh: 'ip rule add from ${___net[$___ifid]}/${___prefix[$___ifid]} table ${___table[$___ifid]}'"
					fi

					if [ ! "$(ip route list table ${___table[$___ifid]})" ] ; then
						if ! ip route add default via ${___gateway[$___ifid]} dev ${___interface[$___ifid]} table ${___table[$___ifid]} 2>/dev/null >/dev/null ; then
							___logger "error: route-up.sh: 'ip route add default via ${___gateway[$___ifid]} dev ${___interface[$___ifid]} table ${___table[$___ifid]}'"
						fi
						if ! ip route add ${___net[$___ifid]}/${___prefix[$___ifid]} dev ${___interface[$___ifid]} table ${___table[$___ifid]} 2>/dev/null >/dev/null ; then
							___logger "error: route-up.sh: 'ip route add ${___net[$___ifid]}/${___prefix[$___ifid]} dev ${___interface[$___ifid]} table ${___table[$___ifid]}'"
						fi
					fi
				fi
		
				# Suppression du verrou
				dotlockfile -u /var/lock/route-${___interface[$___ifid]}

			fi
				
		fi
		
	fi
	
done
