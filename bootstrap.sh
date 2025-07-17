#!/bin/bash
set -e

HOSTNAME=$1
echo "Setting up $HOSTNAME ..."

# Set hostname
hostnamectl set-hostname $HOSTNAME

# Update system and install EPEL
dnf -y install epel-release

# Enable powertools / crb for munge-devel
dnf install -y dnf-plugins-core
dnf config-manager --set-enabled powertools || dnf config-manager --set-enabled crb

# Install dependencies
dnf -y install wget vim git gcc gcc-c++ make \
  munge munge-libs munge-devel \
  openssl openssl-devel pam-devel \
  numactl numactl-devel \
  readline-devel perl perl-ExtUtils-MakeMaker \
  python3

# /etc/hosts for cluster nodes
cat <<EOF > /etc/hosts
127.0.0.1   localhost localhost.localdomain
192.168.56.180 master
192.168.56.181 compute1
192.168.56.182 compute2
EOF

# MUNGE setup
if [ "$HOSTNAME" == "master" ]; then
  /usr/sbin/create-munge-key
  cp /etc/munge/munge.key /vagrant/munge.key
else
  # Wait for key to exist (just in case)
  while [ ! -f /vagrant/munge.key ]; do
    echo "Waiting for /vagrant/munge.key..."
    sleep 2
  done
  cp /vagrant/munge.key /etc/munge/munge.key
fi

chown munge:munge /etc/munge/munge.key
chmod 400 /etc/munge/munge.key
systemctl enable --now munge

# SLURM build + install only on master
if [ "$HOSTNAME" == "master" ]; then
  cd /usr/local/src
  wget https://download.schedmd.com/slurm/slurm-23.02.0.tar.bz2
  tar -xvjf slurm-23.02.0.tar.bz2
  cd slurm-23.02.0
  ./configure --prefix=/opt/slurm --disable-html
  make -j $(nproc)
  make install
fi

# SLURM directories (shared via NFS or local)
mkdir -p /opt/slurm/etc /opt/slurm/spool /opt/slurm/log /var/spool/slurmctld /var/spool/slurmd
useradd slurm || true
chown slurm:slurm /opt/slurm/spool /opt/slurm/log /var/spool/slurmctld /var/spool/slurmd

# slurm.conf
if [ "$HOSTNAME" == "master" ]; then
  cat <<EOF > /opt/slurm/etc/slurm.conf
ClusterName=rockycluster
ControlMachine=master
MpiDefault=none
ProctrackType=proctrack/pgid
ReturnToService=1
SlurmctldPidFile=/var/run/slurmctld.pid
SlurmdPidFile=/var/run/slurmd.pid
SlurmctldPort=6817
SlurmdPort=6818
SlurmdSpoolDir=/var/spool/slurmd
SlurmUser=slurm
StateSaveLocation=/var/spool/slurmctld
SwitchType=switch/none
TaskPlugin=task/none

NodeName=compute1 NodeAddr=compute1 CPUs=2 RealMemory=2048 State=UNKNOWN
NodeName=compute2 NodeAddr=compute2 CPUs=2 RealMemory=2048 State=UNKNOWN
PartitionName=debug Nodes=compute1,compute2 Default=YES MaxTime=INFINITE State=UP
EOF

  cp /opt/slurm/etc/slurm.conf /vagrant/slurm.conf
else
  cp /vagrant/slurm.conf /opt/slurm/etc/slurm.conf
fi

# Systemd services
cat <<EOF > /etc/systemd/system/slurmd.service
[Unit]
Description=Slurm node daemon
After=munge.service network.target

[Service]
Type=simple
ExecStart=/opt/slurm/sbin/slurmd -D
PIDFile=/var/run/slurmd.pid

[Install]
WantedBy=multi-user.target
EOF

if [ "$HOSTNAME" == "master" ]; then
  cat <<EOF > /etc/systemd/system/slurmctld.service
[Unit]
Description=Slurm controller daemon
After=munge.service network.target

[Service]
Type=simple
ExecStart=/opt/slurm/sbin/slurmctld -D
PIDFile=/var/run/slurmctld.pid

[Install]
WantedBy=multi-user.target
EOF
fi

# Enable and start services
systemctl daemon-reexec
systemctl enable --now slurmd
if [ "$HOSTNAME" == "master" ]; then
  systemctl enable --now slurmctld
fi

echo "$HOSTNAME setup complete!"
