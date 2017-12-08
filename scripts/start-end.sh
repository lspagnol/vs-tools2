___logger "END"

# Forcer la mise a jour des caches ARP
# Indispensable sur certains types de chassis, en particulier Cisco ...

for ___ifid in $___ifids ; do

	arping -c 10 -w 1000 -i ${___interface[$___ifid]} -S ${___ip[$___ifid]} ${___gateway[$___ifid]} 2>/dev/null >/dev/null &
	arping -c 10 -w 1000 -i ${___interface[$___ifid]} -S ${___ip[$___ifid]} -B 2>/dev/null >/dev/null &
	
done
