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
    if [ "${VER}" == "" ]
    then
        export VER=24.05.2
    fi

    # https://download.schedmd.com/slurm/slurm-20.02.3.tar.bz2
    wget --no-check-certificate https://download.schedmd.com/slurm/slurm-${VER}.tar.bz2

    [ $? != 0 ] && echo Problem downloading https://download.schedmd.com/slurm/slurm-${VER}.tar.bz2 ... Exiting && exit 1

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
    
    rpmbuild -ta slurm-${VER}.tar.bz2 --with mysql
    rm slurm-${VER}.tar.bz2
    cd ..
    sudo rm -rf slurm-tmp
}

setupSlurmForAmazon()
{
    cd ~/rpmbuild/RPMS/x86_64/
    sudo yum --nogpgcheck localinstall slurm-[0-9]*.amzn2023.x86_64.rpm slurm-contribs-*.amzn2023.x86_64.rpm slurm-devel-*.amzn2023.x86_64.rpm slurm-example-configs-*.amzn2023.x86_64.rpm slurm-libpmi-*.amzn2023.x86_64.rpm slurm-pam_slurm-*.amzn2023.x86_64.rpm slurm-perlapi-*.amzn2023.x86_64.rpm slurm-slurmctld-*.amzn2023.x86_64.rpm slurm-slurmd-*.amzn2023.x86_64.rpm slurm-slurmdbd-*.amzn2023.x86_64.rpm -y

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
