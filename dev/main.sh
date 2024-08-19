# global vars
slurm_accounting_support=0
OSVERSION=""
OSDISTRO=""
SUPPORTED_DISTROS="Centos, Rocky Linux and Almalinux: 7, 8 and 9; Ubuntu: 18.04, 20.04, 22.04 and 24.04; Amazon Linux: 2023."

main()
{
	checkLinuxOsDistro
	askSlurmAccountingSupport
	if echo $OSDISTRO | egrep -iq "redhat_based"
	then
		main_redhat
	elif echo $OSDISTRO | egrep -iq "ubuntu"
	then
		main_ubuntu
    elif echo $OSDISTRO | egrep -iq "amazon"
    then
        main_amazon
	else
		echo "Unknown Linux OS Distro. The supported distros are: $SUPPORTED_DISTROS"
		echo "Aborting..."
		exit 2
	fi
}

main
