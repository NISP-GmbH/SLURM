main_redhat()
{
    disableSElinux
    checkRedHatBasedVersion
    createRequiredUsers
    setupRequiredRedHatBasedRepositories
    installMariaDBforRedHatBased
    installMungeForRedHatBased
    setupRngToolsForRedHatBased
    setupMungeForRedHatBased
    buildSlurmForRedHatBased
    setupSlurmForRedHatBased
    createRequiredFiles
    fixingPermissions
    enableSystemdServices
    executeFirstSlurmCommands
    exit 0
}

setupSlurmForRedHatBased()
{
	cd ~/rpmbuild/RPMS/x86_64/

	# skipping slurm-openlava and slurm-torque because of missing perl-Switch
	sudo yum --nogpgcheck localinstall slurm-[0-9]*.el*.x86_64.rpm slurm-contribs-*.el*.x86_64.rpm slurm-devel-*.el*.x86_64.rpm slurm-example-configs-*.el*.x86_64.rpm slurm-libpmi-*.el*.x86_64.rpm slurm-pam_slurm-*.el*.x86_64.rpm slurm-perlapi-*.el*.x86_64.rpm slurm-slurmctld-*.el*.x86_64.rpm slurm-slurmd-*.el*.x86_64.rpm slurm-slurmdbd-*.el*.x86_64.rpm -y

	# create the SLURM default configuration with
	# compute nodes called "NodeName=linux[1-32]"
	# in a cluster called "cluster"
	# and a partition name called "test"
	# Feel free to adapt to your needs
	HOST=`hostname`

	sudo mkdir /etc/slurm/
	cat << EOF | sudo tee /etc/slurm/slurm.conf

# slurm.conf file generated by configurator easy.html.
# Put this file on all nodes of your cluster.
# See the slurm.conf man page for more information.
#
SlurmctldHost=localhost
#
#MailProg=/bin/mail
MpiDefault=none
#MpiParams=ports=#-#
ProctrackType=proctrack/cgroup
ReturnToService=2
SlurmctldPidFile=/var/run/slurmctld.pid
#SlurmctldPort=6817
SlurmdPidFile=/var/run/slurmd.pid
#SlurmdPort=6818
SlurmdSpoolDir=/var/spool/slurm/slurmd
SlurmUser=slurm
#SlurmdUser=root
StateSaveLocation=/var/spool/slurm/
SwitchType=switch/none
TaskPlugin=task/affinity
#
#
# TIMERS
#KillWait=30
#MinJobAge=300
#SlurmctldTimeout=120
#SlurmdTimeout=300
#
#
# SCHEDULING
SchedulerType=sched/backfill
SelectType=select/cons_tres
SelectTypeParameters=CR_Core
#
#
# LOGGING AND ACCOUNTING
AccountingStorageType=accounting_storage/none
ClusterName=cluster
#JobAcctGatherFrequency=30
JobAcctGatherType=jobacct_gather/none
#SlurmctldDebug=info
SlurmctldLogFile=/var/log/slurmctld.log
#SlurmdDebug=info
SlurmdLogFile=/var/log/slurmd.log
#
#
# COMPUTE NODES
NodeName=$HOST State=idle Feature=dcv2,other
# NodeName=linux[1-32] CPUs=1 State=UNKNOWN
# NodeName=linux1 NodeAddr=128.197.115.158 CPUs=4 State=UNKNOWN
# NodeName=linux2 NodeAddr=128.197.115.7 CPUs=4 State=UNKNOWN

PartitionName=test Nodes=$HOST Default=YES MaxTime=INFINITE State=UP
# PartitionName=test Nodes=$HOST,linux[1-32] Default=YES MaxTime=INFINITE State=UP

# DefMemPerNode=1000
# MaxMemPerNode=1000
# DefMemPerCPU=4000 
# MaxMemPerCPU=4096

EOF

	if [ "$slurm_accounting_support" == "1" ]
	then
	    StorageType=accounting_storage/mysql
	    DbdHost=localhost
	    StorageHost=$DbdHost
	    StorageLoc=slurm_acct_db
	    StorageUser=slurm
	    SlurmUser=$StorageUser
	    random_mysql_password=$(tr -dc '0-9a-zA-Z@' < /dev/urandom | head -c 20)
	    StoragePass=$random_mysql_password
	    StoragePort=3306

		createMysqlDatabase $StorageLoc $StorageUser $StoragePass

	    sudo sed -i 's/AccountingStorageType=accounting_storage\/none/AccountingStorageType=accounting_storage\/slurmdbd/' /etc/slurm/slurm.conf

	    cat <<EOF | sudo tee /etc/slurm/slurmdbd.conf
StorageType=$StorageType
DbdHost=$DbdHost
StorageHost=$StorageHost
StorageLoc=$StorageLoc
StorageUser=$StorageUser
SlurmUser=$SlurmUser
StoragePass=$StoragePass
StoragePort=$StoragePort
LogFile=/var/log/slurmdbd.log
EOF
fi

		cat << EOF | sudo tee /etc/slurm/cgroup.conf
###
#
# Slurm cgroup support configuration file
#
# See man slurm.conf and man cgroup.conf for further
# information on cgroup configuration parameters
#--
CgroupPlugin=cgroup/v1
# CgroupAutomount=yes

ConstrainCores=no
ConstrainRAMSpace=no
EOF

		if [ ! -f /etc/my.cnf.d/slurm.cnf  ]
        then
			total_memory=$(free -m | awk '/^Mem:/{print $2}')
			innodb_buffer_percent=50
			innodb_buffer_pool_size=$((total_memory * innodb_buffer_percent / 100))
			cat <<EOF | sudo tee /etc/my.cnf.d/slurm.cnf
[mariadb]
innodb_lock_wait_timeout=900
innodb_log_file_size=128M
max_allowed_packet=32M
innodb_buffer_pool_size=${innodb_buffer_pool_size}M
EOF

			sudo systemctl restart mariadb
		fi
}

buildSlurmForRedHatBased()
{
	# build and install SLURM
	sudo yum install python3 gcc openssl openssl-devel pam-devel numactl numactl-devel hwloc lua readline-devel ncurses-devel man2html libibmad libibumad rpm-build  perl-ExtUtils-MakeMaker.noarch -y
	if [ "$OSVERSION" == "7" ]
	then
		sudo yum install rrdtool-devel lua-devel hwloc-devel -y
	fi
	if [ "$OSVERSION" == "8" ]
	then
	    sudo yum install rpm-build make -y
	    # dnf --enablerepo=PowerTools install rrdtool-devel lua-devel hwloc-devel -y
	    sudo dnf --enablerepo=powertools install rrdtool-devel lua-devel hwloc-devel rpm-build -y
	    # dnf group install "Development Tools"
	fi
	if [ "$OSVERSION" == "9" ]
	then
    	sudo yum install rpm-build make -y
    	# dnf --enablerepo=PowerTools install rrdtool-devel lua-devel hwloc-devel -y
    	sudo dnf --enablerepo=crb install rrdtool-devel lua-devel hwloc-devel -y
    	# dnf group install "Development Tools"
	fi

	mkdir slurm-tmp
	cd slurm-tmp
	if [ "$VER" == "" ]; then
	    export VER=22.05.9
	fi
	wget --no-check-certificate https://download.schedmd.com/slurm/slurm-$VER.tar.bz2

	[ $? != 0 ] && echo Problem downloading https://download.schedmd.com/slurm/slurm-$VER.tar.bz2 ... Exiting && exit

	if [ "$OSVERSION" == "9" ] ; then
	    # fix LTO issue on 9
	    # https://bugs.schedmd.com/show_bug.cgi?id=14565
	    rpmbuild -ta slurm-$VER.tar.bz2 --define '_lto_cflags %{nil}' --with mysql
	else
	    rpmbuild -ta slurm-$VER.tar.bz2 --with mysql
	fi

	rm slurm-$VER.tar.bz2
	cd ..
	rmdir slurm-tmp

	# get perl-Switch
	# sudo yum install cpan -y
}

setupMungeForRedHatBased()
{
	sudo /usr/sbin/create-munge-key -r -f
	sudo sh -c  "dd if=/dev/urandom bs=1 count=1024 > /etc/munge/munge.key"
	sudo chown munge: /etc/munge/munge.key
	sudo chmod 400 /etc/munge/munge.key

	sudo systemctl enable munge
	sudo systemctl start munge
}

setupRngToolsForRedHatBased()
{
	sudo yum install rng-tools -y
	sudo rngd -r /dev/urandom
}

disableSElinux()
{
	if [ "$slurm_accounting_support" == "1" ]
	then
	    # SLURM accounting support
	    if [ "$OSVERSION" == "9" ] ; then
	        sudo setenforce 0
	        cat << EOF | sudo tee /etc/selinux/config
SELINUX=disabled
SELINUXTYPE=targeted
EOF
    	fi
	fi
}

installMungeForRedHatBased()
{
	if [ "$OSVERSION" == "7" ] ; then
	    sudo yum install munge munge-libs munge-devel -y
	fi
	if [ "$OSVERSION" == "8" ] ; then
	    sudo yum install munge munge-libs  -y
	    sudo dnf --enablerepo=powertools install munge-devel -y
	fi
	if [ "$OSVERSION" == "9" ] ; then
	    sudo yum install munge munge-libs  -y
	    sudo dnf --enablerepo=crb install munge-devel -y
	fi
}

installMariaDBforRedHatBased()
{
	if [ "$slurm_accounting_support" == "1" ]
	then
		if ! rpm -qa | egrep -iq mariadb-server
		then
        	# SLURM accounting support
        	if [ "$OSVERSION" == "9" ]
			then
        		sudo yum install MariaDB-server MariaDB-devel dnf -y
        	    sudo systemctl enable --now mariadb
        	else
            	sudo yum install MariaDB-server MariaDB-devel dnf -y
            	sudo systemctl enable --now mariadb
        	fi
		fi
    else
        sudo yum install MariaDB-server MariaDB-devel dnf -y
	fi
}

checkRedHatBasedVersion()
{
	OSVERSION="7"
	# [ "`hostnamectl | grep Kernel | grep el8`" != "" ] && OSVERSION="8"
	. /etc/os-release

	if [[ $VERSION =~ ^8 ]]
	then
    OSVERSION="8"
    # in case of repo access issues uncomment the following lines
    # sudo sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-*
    # sudo sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*
	fi

	if [[ $VERSION =~ ^9 ]]
	then
	    OSVERSION="9"
	fi
}

setupRequiredRedHatBasedRepositories()
{
	sudo yum install epel-release -y
	if [ "$OSVERSION" == "7" ] ; then
	    sudo curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | sudo bash
	    sudo yum install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm -y
	    # sudo dnf install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
	fi
	if [ "$OSVERSION" == "8" ] ; then
	    sudo curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | sudo bash
	    sudo yum install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm -y
	    # sudo dnf install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
	fi
	if [ "$OSVERSION" == "9" ] ; then
	    sudo curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | sudo bash
	    sudo yum install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm -y
	    # sudo dnf install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
	fi
}
