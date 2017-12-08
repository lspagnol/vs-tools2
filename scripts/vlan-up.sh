for ___ifid in $___ifids ; do

	if test -n "${___vlan[$___ifid]}" ; then
		# 802.1q sur cette interface
		
		if ! ifconfig ${___interface[$___ifid]} 2>/dev/null >/dev/null ; then
		# Le vlan n'est pas actif -> debut de la procedure d'activation
			
			# Mise en place du verrou (15 secondes d'attente maxi)
			if ! dotlockfile -p -r 2 -l /var/lock/vlan-${___interface[$___ifid]} ; then
				___logger "error: vlan-up.sh: unable to lock '/var/lock/vlan-${___interface}'"
				___logger "error: vlan-up.sh: aborted"
			else

				# On verifie a nouveau l'etat du vlan
				if ! ifconfig ${___interface[$___ifid]} 2>/dev/null >/dev/null ; then
		
					# Chargement du module 8021q si necessaire
					grep "^8021q " /proc/modules >/dev/null
					if [ $? -ne 0 ] ; then
						modprobe 8021q
						if [ $? -ne 0 ] ; then
							___logger "error: vlan-up.sh: unable to load '8021q' module"
						fi
					fi

					# Activation du vlan
					if ! vconfig add ${___device[$___ifid]} ${___vlan[$___ifid]} >/dev/null ; then
						___logger "error: vlan-up.sh: 'vconfig add ${___device[$___ifid]} ${___vlan}'"
					fi
		
					# Modification du MTU par defaut si necessaire
					if test -f ${__CONFDIR}/.defaults/dot1q.${___device[$___ifid]} ; then
						. ${__CONFDIR}/.defaults/dot1q.${___device[$___ifid]}
						if test -n "${_MTU}" ; then
							if ! ifconfig ${___interface[$___ifid]} mtu ${_MTU} >/dev/null ; then
								___logger "error: vlan-up.sh: 'ifconfig ${___interface} mtu ${_MTU}'"
							fi
						fi
					fi

					# Activation de l'interface
					if ! ifconfig ${___interface[$___ifid]} up >/dev/null ; then
						___logger "error: vlan-up.sh: 'ifconfig ${___interface} up'"
					fi
	
				fi

				# Suppression du verrou
				dotlockfile -u /var/lock/vlan-${___interface[$___ifid]}
	
			fi
	
		fi

	fi

done

