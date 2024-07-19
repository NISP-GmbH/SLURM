# global vars
slurm_accounting_support=0
OSVERSION=""
OSDISTRO=""
SUPPORTED_DISTROS="Centos 7, Centos 8, Centos 9, Ubuntu 18.04, Ubuntu 20.04 and Ubuntu 22.04"

main()
{
	checkLinuxOsDistro
	askSlurmAccountingSupport
	if echo $OSDISTRO | egrep -iq "centos"
	then
		main_centos
	elif echo $OSDISTRO | egrep -iq "ubuntu"
	then
		main_ubuntu
	else
		echo "Unknown Linux OS Distro. The supported distros are: $SUPPORTED_DISTROS"
		echo "Aborting..."
		exit 2
	fi
}

main
