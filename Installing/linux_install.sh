#!/bin/bash


if [[ "$1" =~ --?h(elp)? ]]; then
	cat << 'EOHelp';
linux_install.sh -- A script to install Scheduler on your system

uage:  linux_install.sh [PORT]

  where:
     PORT   is the port number that Scheduler will listen to for web
            connections.  If you do not provide a port number, Scheduler
            will listen to port 3000.

EOHelp
	exit -1;
fi;

if [[ "$1" == "" ]]; then
	PORT=3000;
else
	PORT=$1;
fi;


##
##  First, install the system components needed
##
if [[ -f "/etc/debian_version" ]]; then
	Installing/deb_linux_install.sh
elif [[ -f "/etc/redhat-release" ]]; then
	Installing/rhel_linux_install.sh
else
	echo "Sorry, I don't recognize the linux you are running!"
	exit -1;
fi

##
##  Install the needed Perl modules
##
sudo cpanm --installdeps .

##
##  Set up the program that starts Scheduler
##
echo "Setting Scheduler to listen to port $PORT";
echo "./Scheduler daemon -l http://*:$PORT" > startScheduler
chmod +x startScheduler

##
##  Set up the default configuration
##
cp -p startup_scheduler.cfg .scheduler.cfg

##
##  Signal cron to restart the scheduler on reboot
##
crontab -l > my_crontab
printf "\n# Start Scheduler at Reboot\n@reboot sleep 120 && cd $PWD && ./startScheduler" >> my_crontab
crontab ./my_crontab

echo "Setup completed."
