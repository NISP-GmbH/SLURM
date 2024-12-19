#!/bin/bash
################################################################################
# Copyright (C) 2019-2024 NI SP GmbH
# All Rights Reserved
#
# info@ni-sp.com / www.ni-sp.com
#
# We provide the information on an as is basis.
# We provide no warranties, express or implied, related to the
# accuracy, completeness, timeliness, useability, and/or merchantability
# of the data and are not liable for any loss, damage, claim, liability,
# expense, or penalty, or for any direct, indirect, special, secondary,
# incidental, consequential, or exemplary damages or lost profit
# deriving from the use or misuse of this information.
################################################################################
# Version v1.7 including accounting support

main_amazon()
{
    disableSElinux
    checkAmazonVersion
    createRequiredUsers
    installMariaDBforAmazon
    installMungeForAmazon
    setupRngToolsForAmazon
    setupMungeForAmazon
    buildSlurmForAmazon
    setupSlurmForAmazon
    createRequiredFiles
    fixingPermissions
    enableSystemdServices
    executeFirstSlurmCommands
    exit 0
}

disableSElinux()
{
    if [ "$slurm_accounting_support" == "1" ]
    then
        sudo setenforce 0
        cat << EOF | sudo tee /etc/selinux/config
SELINUX=disabled
SELINUXTYPE=targeted
EOF
    fi
}

checkAmazonVersion()
{
    OSVERSION=$(grep -E '^VERSION_ID=' /etc/os-release | cut -d'"' -f2)

    if ! echo $OSVERSION | egrep -iq "^2023$"
    then
        echo "Amazon Linux Version >>> $OSVERSION <<< is not supported! Exiting..."
        echo "Supported distros: ${SUPPORTED_DISTROS}"
        exit 2
    fi
}

installMariaDBforAmazon()
{
    if [ "$slurm_accounting_support" == "1" ]
    then
        if ! sudo rpm -qa | egrep -iq "mariadb105-server "
        then
            # SLURM accounting support
            if [ "$OSVERSION" == "2023" ]
            then
                sudo yum -y install mariadb105-server mariadb105-devel
                sudo mysql_install_db --user=mysql --basedir=/usr --datadir=/var/lib/mysql
                sudo systemctl start --now mariadb
                if [ $? -ne 0 ]
                then
i                    echo "Failed to setup mariadb-server. Exiting..."
                    exit 3
                fi
            fi
        fi
    else
        sudo yum -y install mariadb105-server mariadb105-devel
    fi
}

setupRngToolsForAmazon()
{
    sudo yum install rng-tools -y
    sudo rngd -r /dev/urandom
}

installMungeForAmazon()
{
    sudo yum install munge munge-libs munge-devel -y

    cat << EOF | sudo tee /usr/sbin/create-munge-key
#!/usr/bin/sh
# Generates a random key for munged
#
# (C) 2007 Gennaro Oliva
# You may freely distribute this file under the terms of the GNU General
# Public License, version 2 or later.

#Setting default random file
randomfile=/dev/urandom

#Usage message
usage="Try \'\$0 -h' for more information."

#Help message
needhelp() {
echo Usage: create-munge-key [OPTION]...
echo Generates a random key for munged
echo List of options
echo "  -f            force overwriting existing old key"
echo "  -r            specify /dev/random as random file for key generation"
echo "                default is /dev/urandom"
echo "  -h            display this help and exit"
}

#Parsing command line options
while getopts "hrf" options; do
  case \$options in
    r ) randomfile=/dev/random;;
    f ) force=yes;;
    h ) needhelp
        exit 0;;
    \? ) echo \$usage
         exit 1;;
    * ) echo \$usage
          exit 1;;
  esac
done

if [ \`id -u\` != 0 ] ; then
  echo "Please run create-munge-key as root."
  exit 1
fi


#Checking random file presence
if [ ! -e \$randomfile ] ; then
  echo \$0: cannot find random file \$randomfile
  exit 1
fi

#Checking if the user want to overwrite existing key file
if [ "\$force" != "yes" ] && [ -e /etc/munge/munge.key ] ; then
  echo The munge key /etc/munge/munge.key already exists
  echo -n "Do you want to overwrite it? (y/N) "
  read ans
  if [ "\$ans" != "y" -a "\$ans" != "Y" ] ; then
    exit 0
  fi
fi

#Generating the key file and change owner and permissions
if [ "\$randomfile" = "/dev/random" ] ; then
  echo Please type on the keyboard, echo move your mouse,
  echo utilize the disks. This gives the random number generator
  echo a better chance to gain enough entropy.
fi
echo -n "Generating a pseudo-random key using \$randomfile "
dd if=\$randomfile bs=1 count=1024 > /etc/munge/munge.key \
  2>/dev/null
chown munge:munge /etc/munge/munge.key
chmod 0400 /etc/munge/munge.key
echo completed.
exit 0
EOF

    sudo chmod +x /usr/sbin/create-munge-key
}

setupMungeForAmazon()
{
    sudo /usr/sbin/create-munge-key -r -f
    sudo chown munge: /etc/munge/munge.key
    sudo chmod 400 /etc/munge/munge.key

    sudo systemctl enable munge
    sudo systemctl start munge
}

buildSlurmForAmazon()
{
    # build and install SLURM
    sudo yum install python3 gcc openssl openssl-devel pam-devel numactl numactl-devel hwloc lua readline-devel ncurses-devel libibmad libibumad rpm-build  perl-ExtUtils-MakeMaker.noarch -y
    sudo yum install rrdtool-devel lua-devel hwloc-devel -y

    if [[ "${OSVERSION}" == "2023" ]]
    then
        sudo yum install rpm-build make automake autoconf -y
    fi
        
    mkdir slurm-tmp
    cd slurm-tmp

    if [ "${SLURM_VERSION}" == "" ]
    then
        export SLURM_VERSION=24.05.2
    fi

    wget --no-check-certificate https://download.schedmd.com/slurm/slurm-${SLURM_VERSION}.tar.bz2

    [ $? != 0 ] && echo Problem downloading https://download.schedmd.com/slurm/slurm-${SLURM_VERSION}.tar.bz2 ... Exiting && exit 1

    if [[ "${OSVERSION}" == "2023" ]]
    then
        cat << EOF | tee ~/dummy-mariadb-devel.spec
Name:           dummy-mariadb-devel
Version:        5.0.0
Release:        1%{?dist}
Summary:        Dummy package to satisfy mysql-devel dependency

License:        MIT
BuildArch:      noarch

Provides:       mariadb-devel = %{version}

%description
This is a dummy package to satisfy the mysql-devel dependency.

%files

%changelog
* Wed Aug 16 2023 Your Name <your.email@example.com> - 5.0.0-1
- Initial dummy package
EOF

        cat << EOF | tee ~/dummy-mysql-devel.spec
Name:           dummy-mysql-devel
Version:        5.0.0
Release:        1%{?dist}
Summary:        Dummy package to satisfy mysql-devel dependency

License:        MIT
BuildArch:      noarch

Provides:       mysql-devel = %{version}

%description
This is a dummy package to satisfy the mysql-devel dependency.

%files

%changelog
* Wed Aug 16 2023 Your Name <your.email@example.com> - 5.0.0-1
- Initial dummy package
EOF
        rpmbuild -bb ~/dummy-mysql-devel.spec
        rpmbuild -bb ~/dummy-mariadb-devel.spec
        sudo rpm -ivh ~/rpmbuild/RPMS/noarch/dummy-mysql-devel-5.0.0-1.amzn2023.noarch.rpm
        sudo rpm -ivh ~/rpmbuild/RPMS/noarch/dummy-mariadb-devel-5.0.0-1.amzn2023.noarch.rpm
    fi
    
    rpmbuild -ta slurm-${SLURM_VERSION}.tar.bz2 --with mysql
    rm slurm-${SLURM_VERSION}.tar.bz2
    cd ..
    sudo rm -rf slurm-tmp
}

setupSlurmForAmazon()
{
    if echo $OSARCH | egrep -i "x86_64"
    then
        cd ~/rpmbuild/RPMS/x86_64/

        # skipping slurm-openlava and slurm-torque because of missing perl-Switch
        sudo yum --nogpgcheck localinstall slurm-[0-9]*.el*.x86_64.rpm slurm-contribs-*.el*.x86_64.rpm slurm-devel-*.el*.x86_64.rpm slurm-example-configs-*.el*.x86_64.rpm slurm-libpmi-*.el*.x86_64.rpm slurm-pam_slurm-*.el*.x86_64.rpm slurm-perlapi-*.el*.x86_64.rpm slurm-slurmctld-*.el*.x86_64.rpm slurm-slurmd-*.el*.x86_64.rpm slurm-slurmdbd-*.el*.x86_64.rpm -y
    else
        cd ~/rpmbuild/RPMS/aarch64/
        sudo yum --nogpgcheck localinstall slurm-[0-9]*.el*.aarch64.rpm slurm-pam_slurm-[0-9]*.el*.aarch64.rpm slurm-contribs-[0-9]*.el*.aarch64.rpm slurm-perlapi-[0-9]*.el*.aarch64.rpm slurm-devel-[0-9]*-1.el*.aarch64.rpm slurm-slurmctld-[0-9]*.el*.aarch64.rpm slurm-example-configs-[0-9]*.el*.aarch64.rpm slurm-slurmd-[0-9]*.el*.aarch64.rpm slurm-libpmi-[0-9]*.el*.aarch64.rpm slurm-slurmdbd-[0-9]*.el*.aarch64.rpm slurm-openlava-[0-9]*.el*.aarch64.rpm slurm-torque-[0-9]*.el*.aarch64.rpm

    fi

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
ProctrackType=proctrack/linuxproc
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
    if echo $OSARCH | egrep -i "x86_64"
    then
    	cd ~/rpmbuild/RPMS/x86_64/

	    # skipping slurm-openlava and slurm-torque because of missing perl-Switch
	    sudo yum --nogpgcheck localinstall slurm-[0-9]*.el*.x86_64.rpm slurm-contribs-*.el*.x86_64.rpm slurm-devel-*.el*.x86_64.rpm slurm-example-configs-*.el*.x86_64.rpm slurm-libpmi-*.el*.x86_64.rpm slurm-pam_slurm-*.el*.x86_64.rpm slurm-perlapi-*.el*.x86_64.rpm slurm-slurmctld-*.el*.x86_64.rpm slurm-slurmd-*.el*.x86_64.rpm slurm-slurmdbd-*.el*.x86_64.rpm -y
    else
    	cd ~/rpmbuild/RPMS/aarch64/
        sudo yum --nogpgcheck localinstall slurm-[0-9]*.el*.aarch64.rpm slurm-pam_slurm-[0-9]*.el*.aarch64.rpm slurm-contribs-[0-9]*.el*.aarch64.rpm slurm-perlapi-[0-9]*.el*.aarch64.rpm slurm-devel-[0-9]*-1.el*.aarch64.rpm slurm-slurmctld-[0-9]*.el*.aarch64.rpm slurm-example-configs-[0-9]*.el*.aarch64.rpm slurm-slurmd-[0-9]*.el*.aarch64.rpm slurm-libpmi-[0-9]*.el*.aarch64.rpm slurm-slurmdbd-[0-9]*.el*.aarch64.rpm slurm-openlava-[0-9]*.el*.aarch64.rpm slurm-torque-[0-9]*.el*.aarch64.rpm
        
    fi

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
	    export SLURM_VERSION=22.05.9
	fi
	wget --no-check-certificate https://download.schedmd.com/slurm/slurm-${SLURM_VERSION}.tar.bz2

	[ $? != 0 ] && echo Problem downloading https://download.schedmd.com/slurm/slurm-${SLURM_VERSION}.tar.bz2 ... Exiting && exit

	if [ "$OSVERSION" == "9" ] ; then
	    # fix LTO issue on 9
	    # https://bugs.schedmd.com/show_bug.cgi?id=14565
	    rpmbuild -ta slurm-${SLURM_VERSION}.tar.bz2 --define '_lto_cflags %{nil}' --with mysql
	else
	    rpmbuild -ta slurm-${SLURM_VERSION}.tar.bz2 --with mysql
	fi

	rm slurm-${SLURM_VERSION}.tar.bz2
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
    read p
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
        read mysql_root_password
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
main_ubuntu()
{
    checkUbuntuVersion
    createRequiredUsers
    setupRequiredUbuntuRepositories
    installMariaDBforUbuntu
    installMungeForUbuntu
    setupRngToolsForUbuntu
    setupMungeForUbuntu
    buildSlurmForUbuntu
    setupSlurmForUbuntu
    createRequiredFiles
    fixingPermissions
    setupSystemdForUbuntu
    enableSystemdServices
    executeFirstSlurmCommands
    exit 0
}

setupSystemdForUbuntu()
{
	cat <<EOF  | sudo tee /etc/systemd/system/slurmctld.service
[Unit]
Description=Slurm controller daemon
After=network.target munge.service
ConditionPathExists=/etc/slurm/slurm.conf

[Service]
Type=forking
EnvironmentFile=-/etc/sysconfig/slurmctld
ExecStart=/usr/sbin/slurmctld $SLURMCTLD_OPTIONS
ExecReload=/bin/kill -HUP \$MAINPID
PIDFile=/var/run/slurmctld.pid

[Install]
WantedBy=multi-user.target
EOF

	cat <<EOF | sudo tee /etc/systemd/system/slurmdbd.service
[Unit]
Description=Slurm DBD accounting daemon
Wants=network.target munge.service slurmctld.service
After=network.target munge.service slurmctld.service
ConditionPathExists=/etc/slurm/slurmdbd.conf

[Service]
Type=forking
EnvironmentFile=-/etc/sysconfig/slurmdbd
ExecStart=/usr/sbin/slurmdbd $SLURMDBD_OPTIONS
ExecReload=/bin/kill -HUP \$MAINPID
PIDFile=/var/run/slurmdbd.pid

[Install]
WantedBy=multi-user.target
EOF

	cat  <<EOF  | sudo tee /etc/systemd/system/slurmd.service
[Unit]
Description=Slurm node daemon
After=network.target munge.service
ConditionPathExists=/etc/slurm/slurm.conf

[Service]
Type=forking
EnvironmentFile=-/etc/sysconfig/slurmd
ExecStart=/usr/sbin/slurmd -d /usr/sbin/slurmstepd $SLURMD_OPTIONS
ExecReload=/bin/kill -HUP \$MAINPID
PIDFile=/var/run/slurmd.pid
KillMode=process
LimitNOFILE=51200
LimitMEMLOCK=infinity
LimitSTACK=infinity

[Install]
WantedBy=multi-user.target
EOF
}

setupSlurmForUbuntu()
{
	# create the SLURM default configuration with
	# compute nodes called "NodeName=linux[1-32]"
	# in a cluster called "cluster"
	# and a partition name called "test"
	# Feel free to adapt to your needs
	HOST=`hostname`

	sudo mkdir /etc/slurm/
    if [[ $(echo "$VERSION_ID >= 22.04" | bc -l) -eq 1 ]]
    then
		ProctrackType="linuxproc"
	else
		ProctrackType="cgroup"
	fi

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
ProctrackType=proctrack/${ProctrackType}
ReturnToService=1
SlurmctldPidFile=/var/run/slurmctld.pid
#SlurmctldPort=6817
SlurmdPidFile=/var/run/slurmd.pid
#SlurmdPort=6818
SlurmdSpoolDir=/var/spool/slurm/slurmd
SlurmUser=slurm
#SlurmdUser=root
StateSaveLocation=/var/spool/slurm
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
#SlurmctldLogFile=
#SlurmdDebug=info
#SlurmdLogFile=
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
		if [ ! -f /etc/slurm/slurmdbd.conf ]
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

		    cat <<EOF | sudo tee /etc/slurm/slurmdbd.conf
StorageType=$StorageType
DbdAddr=$DbdHost
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
		sudo sed -i 's/AccountingStorageType=accounting_storage\/none/AccountingStorageType=accounting_storage\/slurmdbd/' /etc/slurm/slurm.conf
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

		if [ ! -f /etc/mysql/mariadb.conf.d/99-slurm.cnf  ]
		then
			total_memory=$(free -m | awk '/^Mem:/{print $2}')
			innodb_buffer_percent=50
			innodb_buffer_pool_size=$((total_memory * innodb_buffer_percent / 100))
			cat <<EOF | sudo tee /etc/mysql/mariadb.conf.d/99-slurm.cnf
[mariadb]
innodb_lock_wait_timeout=900
innodb_log_file_size=128M
max_allowed_packet=32M
innodb_buffer_pool_size=${innodb_buffer_pool_size}M
EOF

			sudo systemctl restart mariadb
		fi
}

buildSlurmForUbuntu()
{
	sudo apt update
	sudo DEBIAN_FRONTEND=noninteractive apt -y upgrade
	. /etc/os-release

	sudo DEBIAN_FRONTEND=noninteractive apt -y install bzip2 python3 gcc openssl numactl hwloc lua5.3 man2html make ruby ruby-dev libmunge-dev libpam0g-dev
	sudo /usr/bin/gem install fpm
    mkdir slurm-tmp
    cd slurm-tmp

	if [ "$SLURM_VERSION" == "" ]
	then
	    export SLURM_VERSION=22.05.9
	fi
	wget --no-check-certificate https://download.schedmd.com/slurm/slurm-${SLURM_VERSION}.tar.bz2

	[ $? != 0 ] && echo Problem downloading https://download.schedmd.com/slurm/slurm-${SLURM_VERSION}.tar.bz2 ... Exiting && exit

	tar jxvf slurm-${SLURM_VERSION}.tar.bz2
	cd  slurm-[0-9]*.[0-9]
    if echo $OSARCH | egrep -iq x86_64
    then
	    ./configure --prefix=/usr --sysconfdir=/etc/slurm --enable-pam --with-pam_dir=/lib/x86_64-linux-gnu/security/ --without-shared-libslurm
    else
        ./configure --prefix=/usr --sysconfdir=/etc/slurm --enable-pam --with-pam_dir=/usr/lib/aarch64-linux-gnu/security/ --without-shared-libslurm
    fi

	make
	make contrib
	sudo make install
	cd ../../
	rm -rf slurm-tmp
}

setupMungeForUbuntu()
{
	if [ "$VERSION_ID" == "22.04" ]
	then
	    sudo /usr/sbin/mungekey -f
	else
	    sudo /usr/sbin/create-munge-key -r -f
	fi

	sudo sh -c  "dd if=/dev/urandom bs=1 count=1024 > /etc/munge/munge.key"
	sudo chown munge: /etc/munge/munge.key
	sudo chmod 400 /etc/munge/munge.key
}

setupRngToolsForUbuntu()
{
	sudo DEBIAN_FRONTEND=noninteractive apt -y install rng-tools
	sudo rngd -r /dev/urandom
}

installMungeForUbuntu()
{
	sudo DEBIAN_FRONTEND=noninteractive apt -y install munge libmunge-dev libmunge2
}

installMariaDBforUbuntu()
{
	if [ "$slurm_accounting_support" == "1" ]
	then
		if ! dpkg -l | egrep -iq "^.*mariadb-server"
		then
	    	sudo DEBIAN_FRONTEND=noninteractive apt -y install mariadb-server libmariadbd-dev libmariadb3
	    	sudo systemctl enable --now mariadb
		fi
	fi
}

checkUbuntuVersion()
{
# check if Ubuntu version is compatible
	ubuntu_version=$(lsb_release -rs)
	VERSION_ID=$ubuntu_version
	min_version="18.04"

	if [[ $(echo "$ubuntu_version >= $min_version" | bc -l) -ne 1 ]]
	then
	    echo "The Ubuntu >>> $ubuntu_version <<< is not compatible. The minimal version supported is >>> $min_version <<<. Aborting..."
	    exit 1
	else
		OSVERSION=$ubuntu_version
	fi
}

setupRequiredUbuntuRepositories()
{
	sudo apt update
	if [ ! -f /etc/apt/sources.list.d/mariadb.list ]
	then
		sudo curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | sudo bash
		sudo apt update
	fi
}

# global vars
OSVERSION=""
OSDISTRO=""
OSARCH=""
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

# unknown error
exit 255
