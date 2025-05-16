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
echo "cd $PWD" > startScheduler
echo "./Scheduler daemon -l http://*:$PORT" >> startScheduler
chmod +x startScheduler

##
##  Set up the default configuration
##
cp -p startup_scheduler.cfg .scheduler.cfg

##
##  Make script to signal cron to restart the scheduler on reboot
##
echo "crontab -l > my_crontab" > autoStartScheduler
echo 'printf "\n# Start Scheduler at Reboot\n@reboot sleep 120 && cd ' $PWD ' && ./startScheduler\n" >> my_crontab' >>startSchedulerOnReboot
echo "crontab ./my_crontab" >> autoStartScheduler
chmod +x autoStartScheduler


##
##  Set up desktop launcher
##
cat > Scheduler.desktop << END_LINK
[Desktop Entry]
Encoding=UTF-8
Version=0.1.1
Name=Scheduler
GenericName=Scheduler Service
Exec=$PWD/startScheduler
Icon=$PWD/public/scheduler.png
Type=Application
Categories=Application
Comment=Web service to provide volunteer scheduling
END_LINK

##
##  It appears some desktops look in ~/Desktop, and others look in
##  ~/.local/share/applications, so put the launcher in both...
##
chmod +x Scheduler.desktop
cp Scheduler.desktop ~/.local/share/applications
cp Scheduler.desktop ~/Desktop

echo "Setup completed."
