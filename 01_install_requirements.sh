#!/usr/bin/env bash
set -ex

source common.sh

# FIXME ocp-doit required this so leave permissive for now
sudo setenforce permissive
sudo sed -i "s/=enforcing/=permissive/g" /etc/selinux/config
sudo yum -y update

sudo yum -y install epel-release
sudo yum -y install curl vim-enhanced wget python-pip patch psmisc figlet golang

sudo pip install lolcat

# for tripleo-repos install
sudo yum -y install python-setuptools python-requests

if [ ! -f openshift-origin-client-tools-v3.11.0-0cbc58b-linux-64bit.tar.gz ]; then
  wget https://github.com/openshift/origin/releases/download/v3.11.0/openshift-origin-client-tools-v3.11.0-0cbc58b-linux-64bit.tar.gz
  tar xvzf openshift-origin-client-tools-v3.11.0-0cbc58b-linux-64bit.tar.gz
  sudo cp openshift-origin-client-tools-v3.11.0-0cbc58b-linux-64bit/{kubectl,oc} /usr/local/bin/
fi

# We're reusing some tripleo pieces for this setup so clone them here
cd
if [ ! -d tripleo-quickstart ]; then
  git clone https://git.openstack.org/openstack/tripleo-quickstart
fi
if [ ! -d tripleo-repos ]; then
  git clone https://git.openstack.org/openstack/tripleo-repos
fi
pushd tripleo-repos
sudo python setup.py install
popd

# Needed to get a recent python-virtualbmc package
sudo tripleo-repos current-tripleo

# Work around a conflict with a newer zeromq from epel
if ! grep -q zeromq /etc/yum.repos.d/epel.repo; then
  sed -i '/enabled=1/a exclude=zeromq*' /etc/yum.repos.d/epel.repo
fi
sudo yum -y update
sudo yum install -y python-virtualbmc

# make sure that 'dig' is installed
sudo yum install -y bind-utils

if [ ! -f $HOME/.ssh/id_rsa.pub ]; then
    ssh-keygen
fi
