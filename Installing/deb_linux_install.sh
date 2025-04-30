#!/bin/bash

sudo apt-get -y update
sudo apt-get -y install curl
sudo apt-get -y install make
sudo apt-get -y install gcc
sudo apt-get -y install perl
sudo apt-get -y install libssl-dev
sudo apt-get -y install zlib1g-dev
curl -L https://cpanmin.us | sudo perl - App::cpanminus
