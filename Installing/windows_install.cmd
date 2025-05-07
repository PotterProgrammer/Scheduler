@echo off

set PORT=3000

set _showhelp=0
set _skipPerl=0

:parse_options
set foundMatch=0

if "%1" == "/?" ( set _showhelp=1 & shift & set foundMatch=1)
if "%1" == "/h" ( set _showhelp=1 & shift & set foundMatch=1)
if "%1" == "-h" ( set _showhelp=1 & shift & set foundMatch=1)
if "%1" == "--h" ( set _showhelp=1 & shift & set foundMatch=1)

if "%1" == "/skipPerl" ( set _skipPerl=1 & shift & set foundMatch=1)

: If we parsed an option and a non-numeric option remains, go back and try again
if "%1" == "" ( goto :continueInstall)

if %1 LT 1 (
   if %foundMatch% EQU 1 (
	 goto :parse_options
   ) else (
	 echo Unrecognized option %1
	 exit /b -1
   )
)

:continueInstall

if %_showhelp% equ 1 (
   echo ^windows_install:  A batch file to install Scheduler on Windows
   echo ^  usage:  windows_install [/?] [port_number]
   echo ^     where:
   echo ^     port_number    is the number of the port that Scheduler should
   echo ^                    listen to for incoming connections.  If this is
   echo ^                    not specified, it defaults to 3000.
   exit /b 0
)

:: Get the port number, if the user specified one
if NOT "%1" == "" ( set PORT=%1)


if %_skipPerl% EQU 0 (
:: Now, start by downloading Strawberry Perl
   echo.
   echo *******************
   echo * Downloading Perl
   echo *******************
   echo.
   curl -L https://github.com/StrawberryPerl/Perl-Dist-Strawberry/releases/download/SP_54001_64bit_UCRT/strawberry-perl-5.40.0.1-64bit-portable.zip -o strawberryPerl.zip

:: Unpack perl
   echo.
   echo ******************
   echo * Installing Perl
   echo ******************
   echo.
   mkdir  StrawberryPerl
   cd StrawberryPerl
   tar -xf ..\strawberryPerl.zip 
   cd ..
)

:: Use cpanm in Perl to install remaining pieces
echo.
echo ************************************************************
echo * Installing Perl modules.  (This may take a little while.)
echo ************************************************************
echo.
PATH=%CD%\StrawberryPerl\site\bin;%CD%\StrawberryPerl\perl\bin;%CD%\StrawberryPerl\c\bin;%PATH%

:: Install troublesome pieces first
call cpanm --force --cpanfile windows_forced_cpanfile --installdeps .

:: Then install the rest
call cpanm --cpanfile windows_cpanfile --installdeps .


:: Build program to start Scheduler
echo.
echo *******************************
echo * Setting up Scheduler launcher
echo *******************************
echo.
echo @echo off > launchScheduler.cmd
echo PATH=%PATH% >>launchScheduler.cmd
echo perl Scheduler daemon -l http://*:%PORT% >> launchScheduler.cmd

:: Build helper program to do cleanup
echo.
echo *******************************
echo * Setting up cleanup assistant
echo *******************************
echo.
echo @echo off > clearSchedulesBefore.cmd
echo PATH=%PATH% >>clearSchedulesBefore.cmd
echo perl clearSchedulesBefore %* >> clearSchedulesBefore.cmd

:: Set initial config file
copy startup_scheduler.cfg .scheduler.cfg

echo.
echo Done
