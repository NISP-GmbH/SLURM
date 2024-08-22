# Slurm installation script

A script that downloads, extracts, compiles and installs Slurm for you.


## Supported OS

- Ubuntu: 18.04, 20.04, 22.04, 24.04
- Centos: 7, 8 and 9
- Rocky Linux: 7, 8 and 9
- Alma Linux: 7, 8 and 9
- Amazon Linux: 2023

## Features
- Can be installed with and without accounting support
- Can use an alredy installed MySQL/MariaDB server
- Can install MariaDB

## How to install with interaction

```bash
bash slurm_install.sh
```

or without clone the git:

```bash
sudo bash -c "$(wget --no-check-certificate -qO- https://raw.githubusercontent.com/NISP-GmbH/SLURM/main/slurm_install.sh)"
```

## How to install without interaction

```bash
bash slurm_install.sh --without-interaction=true --slurm-accounting-support=true --mysql-password=123456789
```

**Notes:**
* --mysql-password= and --slurm-accounting-support will not work if there is no --without-interaction parameter set to true
* If you do not have mysql installed, the script will install it for you; In that case, you can leave the mysql parameter empty, like this: --mysql-password=

Example of slurm installer without mysql server previously installed:
```bash
bash slurm_install.sh --without-interaction=true --slurm-accounting-support=true --mysql-password=
```
