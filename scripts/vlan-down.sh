for ___ifid in $___ifids ; do

	if ifconfig ${___interface[$___ifid]} 2>/dev/null >/dev/null ; then
	# Le vlan est actif -> debut de la procedure de desactivation

		# Mise en place du verrou (15 secondes d'attente maxi)
		if  ! dotlockfile -p -r 2 -l /var/lock/vlan-${___interface[$___ifid]} ; then
			___logger "error: unable to lock '/var/lock/vlan-${___interface[$___ifid]}'"
			___logger "error: vlan-down.sh: aborted"
		else

			# On verifie a nouveau l'etat du vlan
			if ifconfig ${___interface[$___ifid]} 2>/dev/null >/dev/null ; then

				# Le vlan ne peut etre desactive que si plus aucune ip virtuelle ne l'utilise
				if ! ip addr ls ${___interface[$___ifid]} |egrep "^ +inet " >/dev/null ; then

					ifconfig ${___interface[$___ifid]} down > /dev/null
					vconfig rem ${___interface[$___ifid]} > /dev/null		

				fi
			
			fi
			
			# Suppression du verrou
			dotlockfile -u /var/lock/vlan-${___interface[$___ifid]}
			
		fi

	fi

done
