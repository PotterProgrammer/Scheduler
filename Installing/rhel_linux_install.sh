#!/bin/bash

sudo yum update
sudo yum -y install curl
sudo yum -y install make
sudo yum -y install gcc
sudo yum -y install perl
sudo yum -y install openssl-devel
sudo yum -y install zlib-devel
sudo yum -y install perl-Date-Calc
sudo yum -y install perl-Crypt-DES_EDE3
curl -L https://cpanmin.us | sudo perl - App::cpanminus
