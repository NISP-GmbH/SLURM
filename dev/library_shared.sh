welcomeMessage()
{
    RED='\033[0;31m'; GREEN='\033[0;32m'; GREY='\033[0;37m'; BLUE='\034[0;37m'; NC='\033[0m'
    ORANGE='\033[0;33m'; BLUE='\033[0;34m'; WHITE='\033[0;97m'; UNLIN='\033[0;4m'
    echo -e "${GREEN}###################################################"
    echo -e "Welcome to the SLURM Installation Script"
    echo -e "###################################################${NC}"
    echo "You can customize the SLURM version executing the command below (before the builder script):"
    echo "export SLURM_VERSION=24.05.2"
    echo "Press enter to continue."
    if ! $without_interaction
    then
        read p
    fi
}

getOsArchitecture() {
    local arch=$(uname -m)

    case "$arch" in
        x86_64)
            OSARCH="x86_64"
            ;;
        aarch64|arm64)
            OSARCH="arm64"
            ;;
        *)
            echo "Unknown architecture: $arch"
            exit 55
            ;;
    esac
}

checkLinuxOsDistro()
{
    if [ -f /etc/redhat-release ]
    then
        OSDISTRO="redhat_based"
        if hostnamectl | egrep -i "operating system" | egrep -iq "red hat enterprise"
        then
            ISOSREDHAT="true"
        fi
    else
        if [ -f /etc/issue ]
        then
            if cat /etc/issue | egrep -iq "ubuntu"
            then
                OSDISTRO="ubuntu"
            else
                if [ -f /etc/os-release ]
                then
                    if cat /etc/os-release | egrep -iq amazon
                    then
                        OSDISTRO="amazon"
                    else
                        OSDISTRO="unknown"
                    fi
                else
                    OSDISTRO="unknown"
                fi
            fi
        else
            OSDISTRO="unknown"
        fi
    fi
	echo "The current Linux distribution is: $OSDISTRO"
    if [[ "${OSDISTRO}" == "unknown" ]]
    then
        echo "Linux distribution not recognized. Aborting..."
        exit 4
    fi
}

createMysqlDatabase()
{
	StorageLoc=$1
	StorageUser=$2
	StoragePass=$3

    if echo $without_interaction | egrep -iq "false"
    then
        echo "If you already have mysql/mariadb installed, please type the password. Leave empty (just press enter) if this server is fresh (without mysql/mariadb) or if there is no password or the password is configured under .my.cnf file."
        if $without_interaction
        then
            mysql_root_password=""
        else
            read mysql_root_password
        fi
    fi

    export MYSQL_PWD=$mysql_root_password
	if sudo mysql -u root -e "SELECT 1" &> /dev/null
	then
        if ! sudo mysql -u root -e "use $StorageLoc" 2> /dev/null
		then
			sudo mysql -u root -e "CREATE DATABASE $StorageLoc;"
	    	sudo mysql -u root -e "CREATE USER '$StorageUser'@'localhost' IDENTIFIED BY '$StoragePass';"
	    	sudo mysql -u root -e "ALTER USER '$StorageUser'@'localhost' IDENTIFIED BY '$StoragePass';"
	    	sudo mysql -u root -e "GRANT ALL PRIVILEGES ON $StorageLoc.* TO '$StorageUser'@'localhost';"
	    	sudo mysql -u root -e "FLUSH PRIVILEGES;"
		fi
		unset MYSQL_PWD
	else
		echo "Was not possible to connect with MySQL or MariaDB server. Please type the correct passord. Exiting..."
        exit 5
	fi
}


executeFirstSlurmCommands()
{
    if $without_interaction_parameter
    then
        return
    fi

	echo Sleep for a few seconds for slurmctld to come up ...
	sleep 5

	# show cluster
	echo
	echo Output from: \"sinfo\"
	sinfo

	# sinfo -Nle
	echo
	echo Output from: \"scontrol show partition\"
	scontrol show partition

	# show host info as slurm sees it
	echo
	echo Output from: \"slurmd -C\"
	slurmd -C

	# in case host is in drain status
	# scontrol update nodename=$HOST state=idle

	echo
	echo Output from: \"scontrol show nodes\"
	scontrol show nodes

	# If jobs are running on the node:
	# scontrol update nodename=$HOST state=resume

	# lets run our first job
	echo
	echo Output from: \"srun hostname\"
	srun hostname

	echo Sleep for a few seconds for slurmd to come up ...
	sleep 2

	# show cluster
	echo
	echo Output from: \"sinfo\"
	sinfo

	# sinfo -Nle
	echo
	echo Output from: \"scontrol show partition\"
	scontrol show partition

	# show host info as slurm sees it
	echo
	echo Output from: \"slurmd -C\"
	slurmd -C

	# in case host is in drain status
	# scontrol update nodename=$HOST state=idle

	echo
	echo Output from: \"scontrol show nodes\"
	scontrol show nodes

	# If jobs are running on the node:
	# scontrol update nodename=$HOST state=resume

	# lets run our first job
	echo
	echo Output from: \"srun hostname\"
	srun hostname
}

enableSystemdServices()
{
	# slurmdbd needs to connect with slurmctld and vice-versa, causing a race condition.
	# the best option for now is start slurmdbd, sleep, start slurmctld, another sleep to wait the registration and then restart slurmdbd
	# this is not ideal, but will work. the slurm dev need to be contacted to fix this problem
	sudo systemctl daemon-reload
	sudo systemctl enable --now slurmdbd
	sleep 5
	sudo systemctl enable --now slurmctld
	sleep 10
	sudo systemctl restart slurmdbd
	sudo systemctl enable --now slurmd
}

createRequiredFiles()
{
	sudo mkdir /var/spool/slurm
	sudo mkdir /var/spool/slurm/slurmctld
	sudo mkdir /var/spool/slurm/cluster_state
	sudo touch /var/log/slurmctld.log
	sudo touch /var/log/slurm_jobacct.log /var/log/slurm_jobcomp.log
}

fixingPermissions()
{
	sudo chown -R slurm:slurm /etc/slurm
	sudo chmod 600 /etc/slurm/slurmdbd.conf
	sudo chown slurm:slurm /var/spool/slurm
	sudo chmod 755 /var/spool/slurm
	sudo chown slurm:slurm /var/spool/slurm/slurmctld
	sudo chmod 755 /var/spool/slurm/slurmctld
	sudo chown slurm:slurm /var/spool/slurm/cluster_state
	sudo chown slurm:slurm /var/log/slurmctld.log
	sudo chown slurm: /var/log/slurm_jobacct.log /var/log/slurm_jobcomp.log
	sudo chmod 777 /var/spool   # hack for now as otherwise slurmctld is complaining
}

createRequiredUsers()
{
	export MUNGEUSER=966
	sudo groupadd -g $MUNGEUSER munge
	if ! id "$USERNAME" &> /dev/null
	then
		sudo useradd  -m -c "MUNGE Uid 'N' Gid Emporium" -d /var/lib/munge -u $MUNGEUSER -g munge  -s /sbin/nologin munge
	fi

	export SLURMUSER=967

	if ! getent group slurm &> /dev/null
	then
		sudo groupadd -g $SLURMUSER slurm
	fi

	sudo useradd  -m -c "SLURM workload manager" -d /var/lib/slurm -u $SLURMUSER -g slurm  -s /bin/bash slurm
}

askSlurmAccountingSupport()
{
    if echo $without_interaction | egrep -iq "false"
    then
        valid_answer=false
        slurm_accounting_support=0
        while ! $valid_answer
        do
            echo -e "${GREEN}##########################################################################"
            echo "Do you want to enable Slurm accounting support? Possible answers: [yes/no]"
            echo -e  "##########################################################################${NC}"
            read answer

            answer_lowercase=$(echo "$answer" | tr '[:upper:]' '[:lower:]')

            if [ "$answer_lowercase" == "y" ] || [ "$answer_lowercase" == "yes" ]
            then
                slurm_accounting_support=1
                valid_answer=true
            elif [ "$answer_lowercase" == "n" ] || [ "$answer_lowercase" == "no" ]
            then
                slurm_accounting_support=0
                valid_answer=true
            else
                echo "Invalid input!"
            fi
        done
    fi
}
