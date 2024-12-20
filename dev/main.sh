# global vars
OSVERSION=""
OSDISTRO=""
OSARCH=""
ISOSREDHAT="false"
SUPPORTED_DISTROS="Centos, Rocky Linux and Almalinux: 7, 8 and 9; Ubuntu: 18.04, 20.04, 22.04 and 24.04; Amazon Linux: 2023."
slurm_accounting_support=0
without_interaction="false"
mysql_root_password=""
without_interaction_parameter="false"

if echo $@ | egrep -iq -- "--without-interaction"
then
    without_interaction_parameter="true"

    if [[ ${without_interaction_parameter} == "true" ]]
    then
        for arg in "$@"
        do
            case $arg in
                --slurm-accounting-support=false)
                slurm_accounting_support=0
                shift
                ;;
                --slurm-accounting-support=true)
                slurm_accounting_support=1
                shift
                ;;
                --without-interaction=true)
                without_interaction=true
                shift
                ;;
                --mysql-password=*)
                mysql_root_password="${arg#*=}"
                shift
                ;;
                *)
                echo "Unknown parameter: $arg"
                exit 1
                ;;
            esac
        done
    fi
fi


main()
{
    welcomeMessage
    getOsArchitecture
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
