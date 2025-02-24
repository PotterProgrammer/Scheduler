##
##  Module to send messages to volunteers/organizers
##
package Messaging;

require Exporter;
@ISA = qw( Exporter);
@EXPORT = qw( makeCalendarFor getConfigInfo saveConfig sendEmail sendReminders sendSchedules sendUpdateRequest);

use warnings;
use strict;

use Data::ICal;
use Data::ICal::Entry::Event;
use DateTime;
use DateTime::Format::ICal;
use DBI;
use Email::Send::SMTP::Gmail;
use POSIX;
use SaveRestore;
use Time::HiRes;


use WWW::Twilio::API;
use WWW::Twilio::TwiML;
use URI::Escape;

use open qw(:std :utf8);
use utf8;
use utf8::all;

sub makeCalendarFor($$$);
sub saveConfig(%);
sub sendReminders($);
sub sendSchedules($$$);

my $HOME = $ENV{'HOME'};
my $adminName;
my $adminEmail;
my $adminPhone;
my $adminTextNumber;
my $emailSender;
my $email_pwd;
my $email_uid;
my $email_smtp;
my $email_port;
my $TwilioAccount;
my $TwilioAuth;
my $TwilioNumber;
my $uid;
my $pwd;
our $ConfigName = "$HOME/.scheduler.cfg";


#------------------------------------------------------------------------------
#  sub hidden()
#------------------------------------------------------------------------------
sub hidden($)
{
 my $text = $_[0];
 $text =~ tr/0-9A-Z!_a-z\-@/a-z\-@A-Z!_0-9/;
 return( $text);
}

#------------------------------------------------------------------------------
#  sub unhidden($)
#------------------------------------------------------------------------------
sub unhidden($)
{
 my $text = $_[0];
 $text =~ tr/a-z\-@A-Z!_0-9/0-9A-Z!_a-z\-@/;
 return( $text);
}

#------------------------------------------------------------------------------
#  sub loadConfig()
#		Load predefined config info for sending emails, etc.
#------------------------------------------------------------------------------
sub loadConfig()
{
	if ( -e $ConfigName)
	{
		open( CFG, $ConfigName);
		while( <CFG>)
		{
			chomp;
			if ( m/EmailServer=(.*)/)
			{
				$email_smtp = $1;
				next;
			}
			if ( m/EmailPort=(.*)/)
			{
				$email_port=int($1);
				next;
			}
			if ( m/EmailUID=(.*)/)
			{
				$email_uid=$1;
				next;
			}
			if ( m/EmailPWD=(.*)/)
			{
				$email_pwd = unhidden($1);
				next;
			}
			if ( m/EmailSender=(.*)/)
			{
				$emailSender=$1;
				next;
			}
			if ( m/TwilioAcct=(.*)/)
			{
				$TwilioAccount=$1;
				next;
			}
			if ( m/TwilioAuth=(.*)/)
			{
				$TwilioAuth = unhidden($1);
				next;
			}
			if ( m/TwilioPhone=(.*)/)
			{
				$TwilioNumber=$1;
				next;
			}
			if ( m/AdminName=(.*)/)
			{
				$adminName = $1;
				next;
			}
			if ( m/AdminEmail=(.*)/)
			{
				$adminEmail = $1;
				next;
			}
			if ( m/AdminPhone=(.*)/)
			{
				$adminPhone = $1;
				next;
			}
			if ( m/AdminText=(.*)/)
			{
				$adminTextNumber = $1;
				next;
			}
		}
		close CFG;
	}
}

#------------------------------------------------------------------------------
#  sub saveConfig( %config)
#  		This routine writes the provided config values to file and updates the
#  		current configuration values in memory
#------------------------------------------------------------------------------
sub saveConfig(%)
{
	my %config = @_;

	open( CFG, ">", $ConfigName);

	print CFG "EmailServer=" . $config{"EmailServer"} ."\n";
	$email_smtp = $config{"EmailServer"};
	print CFG "EmailPort=" . $config{"EmailPort"} . "\n";
	$email_port = $config{"EmailPort"};
	print CFG "EmailUID=" . $config{"EmailUID"} . "\n";
	$email_uid = $config{"EmailUID"};
	print CFG "EmailPWD=" . hidden( $config{"EmailPWD"}) . "\n";
	$email_pwd = $config{"EmailPWD"};
	print CFG "EmailSender=" . $config{"EmailSender"} . "\n";
	$emailSender = $config{"EmailSender"};
	print CFG "TwilioAcct=" . $config{"TwilioAcct"} . "\n";
	$TwilioAccount = $config{"TwilioAcct"};
	print CFG "TwilioAuth=" . hidden( $config{"TwilioAuth"}) . "\n";
	$TwilioAuth = $config{"TwilioAuth"};
	print CFG "TwilioPhone=" . $config{"TwilioPhone"} . "\n";
	$TwilioNumber = $config{"TwilioPhone"};
	print CFG "AdminName=" . $config{"AdminName"} . "\n";
	$adminName = $config{"AdminName"};
	print CFG "AdminEmail=" . $config{"AdminEmail"} . "\n";
	$adminEmail = $config{"AdminEmail"};
	print CFG "AdminPhone=" . $config{"AdminPhone"} . "\n";
	$adminPhone = $config{"AdminPhone"};
	print CFG "AdminText=" . $config{"AdminText"} . "\n";
	$adminTextNumber = $config{"AdminText"};

	close CFG;
}
#------------------------------------------------------------------------------
#  sub getConfigInfo()
#  		This function returns the current data from the Config file
#------------------------------------------------------------------------------
sub getConfigInfo()
{
	if ( !defined( $email_uid))
	{
		loadConfig();
	}

	my %configInfo = (
						'EmailServer' => $email_smtp , 
						'EmailPort' => $email_port, 
						'EmailUID' => $email_uid, 
						'EmailPWD' => $email_pwd , 
						'EmailSender' => $emailSender, 
						'TwilioAcct' => $TwilioAccount, 
						'TwilioAuth' => $TwilioAuth , 
						'TwilioPhone' => $TwilioNumber, 
						'AdminName' => $adminName , 
						'AdminEmail' => $adminEmail , 
						'AdminPhone' => $adminPhone , 
						'AdminText' => $adminTextNumber , 
					 );

	return %configInfo;
}

#------------------------------------------------------------------------------
#  sendEmail( $to, $from, $sub, $message[, @attachments])
#		This function uses the default email settings to send an email message.
#		The function returns a non-zero value if an error occurred.
#------------------------------------------------------------------------------
sub sendEmail(@)
{
	my ( $to, $from, $subj, $message, @attachments) = @_;
##--> my $transport;

	if ( !defined( $email_uid))
	{
		loadConfig();
	}

  
	my ($mailer, $error) = Email::Send::SMTP::Gmail->new( -smtp=> $email_smtp,
														  -login=>$email_uid,
														  -pass=>$email_pwd);

	print STDERR "Can't get mail connection!! $error" if ( defined( $error) && length( $error));

	
	if ( @attachments)
	{
		my $filenames = join( ',', @attachments);

		$mailer->send( -to => $to,
					   -subject => $subj,
					   -from => $from, 
					   -contenttype => "text/html",
					   -body => $message,
					   -attachments => $filenames,
					   -disposition => "inline",
					 );
	}
	else
	{
		$mailer->send( -to => $to,
					   -subject => $subj,
					   -from => $from,
					   -contenttype => "text/html",
					   -body => $message,
					 );
	}
	$mailer->bye;
}

#------------------------------------------------------------------------------
#  sub sendSMSTwilio($$$)
#		Send an SMS message using Twilio to transmit. This function returns a
#		non-zero value on error.
#------------------------------------------------------------------------------
sub sendSMSTwilio($$)
{
	my ( $to, $message) = @_;
	my $rc = 0;
	my @pieces;

##-->	while ( $message =~ s/(.{1,150})\s+//sm)
##-->	{
##-->		my $nextMessage = $1;
##-->
##-->		if ( $nextMessage =~ s/<BREAK>(.*)//sm)
##-->		{
##-->			$message = "$1 $message";
##-->		}
##-->		push( @pieces, $nextMessage);
##-->	}
##-->
##-->	while ( $message =~ s/<BREAK>(.*)//sm)
##-->	{
##-->		push( @pieces, $message);
##-->		$message = $1;
##-->	}
	push( @pieces, $message);

	if ( !defined( $TwilioAccount))
	{
		loadConfig();
	}

	my $twilio = WWW::Twilio::API->new(AccountSid  => $TwilioAccount,
									AuthToken   => $TwilioAuth,
									API_VERSION => '2010-04-01' );



	foreach $message ( @pieces)
	{
		print "Message = '$message'\n";
		chomp $message;
		
		##
		##  Twilio changed the API from SMS/Messages to Messages
		##
##-->	 my $response = $twilio->POST(	'SMS/Messages',
		print "Sending to $to\n";
		my $response = $twilio->POST(	'Messages',
									To   => $to,
									From => $TwilioNumber,
									Body => $message,
									);

		my $sid;
		my $status;
		if ($response->{content} =~ m/<Sid>([^<]*)<\/Sid>/i)
		{
			$sid = $1;
		}
		
		if ( $response->{content} =~ m/.*<Status>(.*?)<\/Status>/i)
		{
			$status = $1;
		}
		
		if ( !defined( $status))
			{
			logCall( "Unable to send TXT message!", "Twilio said: " . $response->{message} . "\n" . $response->{content} );

			sendEmail( 'webmaster@stjamesbg.org', 'St.James PhoneTree Alert', 'St. James Phone Tree Alert!', "Trying to send a message to $to returned the following error: " .  $response->{content});
			$rc = 1;
		}
		else
		{
			print "Status=$status\n";
			while( $status =~ /queued|sending/)
			{
				##
				##  Twilio changed the API from SMS/Messages to Messages
				##
##-->			 $response = $twilio->GET( 'SMS/Messages', Sid=>$sid);
				$response = $twilio->GET( "Messages/$sid", AccountSid=> $TwilioAccount, Sid=>$sid);
				$response->{content} =~ m/<Status>(.*?)<\/Status>/i;
				$status = $1;
				sleep 1;
		  	}

			print "Final status=$status\n";
			$rc |= ( $status =~ m/fail/);
		}
	}
	print "The rc was $rc\n";

	return( $rc);
}

#------------------------------------------------------------------------------
#  sub sendReminders( $numberOfDays)
#  		This function sends reminders to everyone who is scheduled to volunteer
#  		in the next number of days
#------------------------------------------------------------------------------
sub sendReminders($)
{
	local $SIG{CHLD} = "IGNORE";
	my $pid = fork();

	die "Fork failed!!\n" if (! defined( $pid));

	if ( !$pid)
	{
		my ($number) = @_;
		my $emailTemplate;
		my $textTemplate;

		if ( ! defined( $adminName))
		{
			loadConfig();
		}

		my $dialableAdminPhone = $adminPhone;
		my $textableAdminNumber = $adminTextNumber;

		$dialableAdminPhone =~ s/[^0-9]//g;
		$textableAdminNumber =~ s/[^0-9]//g;

		##
		##  Get a list of people volunteering on the given date
		##
		my @volunteers = readReminderList( $number);

		##
		##  Read in the templates
		##
		open( my $TEMPLATE, '<', "email/reminder.htm") || die "Couldn't read email template!\n";
		read( $TEMPLATE, $emailTemplate, 999999);
		close $TEMPLATE;
		
		open( $TEMPLATE, '<', "sms/reminder.txt") || die "Couldn't read text template!\n";
		read( $TEMPLATE, $textTemplate, 999999);
		close $TEMPLATE;


		##
		##  Loop through the list, sending reminders
		##
		foreach  my $scheduledVolunteer ( @volunteers)
		{
			##
			##  Get the info for this slot
			##
			my $name = $scheduledVolunteer->{name};
			my $firstName = ($name =~ m/^([^\s]*)/) ? $1 : $name;
			my $date = $scheduledVolunteer->{date};
			my $time = $scheduledVolunteer->{time};
			my $position = $scheduledVolunteer->{title};
			$date =~ s/(\d+)-(.*)/$2-$1/;

			print "Sending a reminder to $name for $position on $date\n";

			##
			##  Get info for this person
			##
			my @info = readVolunteers( $name);
			my $volunteerEmail = $info[0]->{email};
			my $volunteerPhone = $info[0]->{phone};
			my $contactMode = $info[0]->{contact};

			$volunteerPhone =~ s/[- \(\)]//g;

			##
			##  Should we email the person?
			##
			if ( $contactMode =~ /email|both/)
			{
				my $email  = $emailTemplate;

				$email =~ s/__FIRST_NAME__/$firstName/smg;
				$email =~ s/__NAME__/$name/smg;
				$email =~ s/__DATE__/$date/smg;
				$email =~ s/__TIME__/$time/smg;
				$email =~ s/__POSITION__/$position/smg;
				$email =~ s/__SCHEDULE_ADMIN__/$adminName/smg;
				$email =~ s/__SCHEDULE_ADMIN_EMAIL__/$adminEmail/smg;
				$email =~ s/__SCHEDULE_ADMIN_PHONE__/$adminPhone/smg;
				$email =~ s/__SCHEDULE_ADMIN_DIALABLE_PHONE__/$dialableAdminPhone/smg;
				$email =~ s/__SCHEDULE_ADMIN_TEXT_NUMBER__/$adminTextNumber/smg;
				$email =~ s/__SCHEDULE_ADMIN_TEXTABLE_NUMBER__/$textableAdminNumber/smg;

				##
				##  Send the reminder email
				##
				if ( defined( $volunteerEmail) && $volunteerEmail =~ m/\S\@\S/)
				{
					sendEmail( $volunteerEmail, 'Scheduling Assistant at St. James', 'Service reminder', $email, 'email/reminder.png');
					print "Sent\n";
				}
				else
				{
					print STDERR "No email address for $name!\n";
				}
			}

			##
			##  Should we send a text?
			##
			if ( $contactMode =~ /text|both/)
			{
				my $text  = $textTemplate;

				$text =~ s/__FIRST_NAME__/$firstName/smg;
				$text =~ s/__NAME__/$name/smg;
				$text =~ s/__DATE__/$date/smg;
				$text =~ s/__TIME__/$time/smg;
				$text =~ s/__POSITION__/$position/smg;
				$text =~ s/__SCHEDULE_ADMIN__/$adminName/smg;
				$text =~ s/__SCHEDULE_ADMIN_EMAIL__/$adminEmail/smg;
				$text =~ s/__SCHEDULE_ADMIN_PHONE__/$adminPhone/smg;
				$text =~ s/__SCHEDULE_ADMIN_DIALABLE_PHONE__/$dialableAdminPhone/smg;
				$text =~ s/__SCHEDULE_ADMIN_TEXT_NUMBER__/$adminTextNumber/smg;
				$text =~ s/__SCHEDULE_ADMIN_TEXTABLE_NUMBER__/$textableAdminNumber/smg;

				##
				##  Send the reminder text
				##
				if ( defined( $volunteerPhone) && $volunteerPhone =~ m/^[0-9-]+$/)
				{
					print "Sending a text reminder to $volunteerPhone\n";
					sendSMSTwilio( $volunteerPhone, $text);
					print "Sent\n";
				}
				else
				{
					print STDERR "No phone number for $name!\n";
				}
				
			}
			
			##
			##  Note that this person was notified
			##
			updateScheduleReminded( $scheduledVolunteer);
		}
	}
}

#------------------------------------------------------------------------------
#  sub sendSchedules( $firstDate, $lastDate, $calendarURL)
#  		This function sends out email copies of the personal volunteer schedule
#  		to each person who is scheduled to serve sometime from the first date
#  		through the last date.
#------------------------------------------------------------------------------
sub sendSchedules($$$)
{
	local $SIG{CHLD} = "IGNORE";
	my $pid = fork();

	die "Fork failed!!\n" if (! defined( $pid));

	if ( !$pid)
	{
		my ( $firstDate, $lastDate, $calendarURL) = @_;
		my $template;
		my $textTemplate;
		my $dash = "\x{2014}";
		my $enDash = "\x{2013}";

		if ( ! defined( $adminName))
		{
			loadConfig();
		}

		my $dialableAdminPhone = $adminPhone;
		my $textableAdminNumber = $adminTextNumber;
		$dialableAdminPhone =~ s/[^0-9]//g;
		$textableAdminNumber =~ s/[^0-9]//g;


		my $printableStart = $firstDate;
		my $printableEnd = $lastDate;
		$printableStart =~ s/(\d\d\d\d)-(.*)/$2-$1/;
		$printableEnd =~ s/(\d\d\d\d)-(.*)/$2-$1/;

		##
		##  First, get a list of people volunteering
		##
		my @volunteers = readVolunteers();

		##
		##  Read in the scheduler template
		##
		open( my $TEMPLATE, '<', "email/personalSchedule.htm") || die "Couldn't read email template!\n";
		read( $TEMPLATE, $template, 999999);
		close $TEMPLATE;

		open( $TEMPLATE, '<', "sms/personalSchedule.txt") || die "Couldn't read text template!\n";
		read( $TEMPLATE, $textTemplate, 999999);
		close $TEMPLATE;
		

		##
		##  Loop through the list to find schedules (if any) for the given dates
		##
		foreach my $volunteer (@volunteers)
		{
			my $name = $volunteer->{name};
			my $firstName = ( $name=~/(\S+)/) ? $1 : $name;
			my $volunteerEmail = $volunteer->{email};
			my $volunteerPhone = $volunteer->{phone};
			my $contactMode = $volunteer->{contact};

			##
			##  See if this person is scheduled for the dates given
			##
			my @schedules = readScheduleFor( $name, $firstDate, $lastDate);

			##
			##	Was the person scheduled?
			##
			if ( @schedules)
			{
				##
				##  Should we email the person?
				##
				if ( $contactMode =~ /email|both/)
				{
					my $scheduledDates = '';

					##
					##  Build the schedule list
					##
					foreach my $schedule ( @schedules)
					{
						my $printableDate = $schedule->{date};
						$printableDate =~ s/(\d+)-(.*)/$2-$1/;
						$scheduledDates .= '<li><span class="scheduledDate">' . $printableDate . '</span>';
						$scheduledDates .= '<span class="scheduledSeparator">' . $dash . '</span>';
						$scheduledDates .= '<span class="scheduledRole">' . $schedule->{title}. '</span>';
						$scheduledDates .= 'at <span class="scheduledTime">' . $schedule->{time}. '</span>';
						$scheduledDates .= '</li>';
					}

					my $email  = $template;

					$email =~ s/__FIRST_NAME__/$firstName/smg;
					$email =~ s/__NAME__/$name/smg;
					$email =~ s/__SCHEDULE__/$scheduledDates/smg;
					$email =~ s/__SCHEDULE_ADMIN__/$adminName/smg;
					$email =~ s/__SCHEDULE_ADMIN_EMAIL__/$adminEmail/smg;
					$email =~ s/__SCHEDULE_ADMIN_PHONE__/$adminPhone/smg;
					$email =~ s/__SCHEDULE_ADMIN_DIALABLE_PHONE__/$dialableAdminPhone/smg;
					$email =~ s/__SCHEDULE_ADMIN_TEXT_NUMBER__/$adminTextNumber/smg;
					$email =~ s/__SCHEDULE_ADMIN_TEXTABLE_NUMBER__/$textableAdminNumber/smg;
					$email =~ s/__CALENDAR_FILE__/$calendarURL\/$name?start=$firstDate\&end=$lastDate/smg;
							
					##
					##  Send the reminder email
					##
					if ( defined( $volunteerEmail) && $volunteerEmail =~ m/\S\@\S/)
					{
						sendEmail( $volunteerEmail, 'Scheduling Assistant at St. James', "New Schedule for $printableStart $enDash $printableEnd", $email, 'email/scheduling.png');
						print "Sent\n";
					}
					else
					{
						print STDERR "No email address for $name!\n";
					}
				}

				##
				##  Should we send a text?
				##
				if ( $contactMode =~ /text|both/)
				{
					my $scheduledDates = '';

					##
					##  Build the schedule list
					##
					foreach my $schedule ( @schedules)
					{
						my $printableDate = $schedule->{date};
						$printableDate =~ s/(\d+)-(.*)/$2-$1/;
						$scheduledDates .= " * $printableDate:  $schedule->{title}  $schedule->{time}\n";
					}

					my $text  = $textTemplate;

					$text =~ s/__FIRST_NAME__/$firstName/smg;
					$text =~ s/__NAME__/$firstName/smg;
					$text =~ s/__SCHEDULE__/$scheduledDates/smg;
					$text =~ s/__SCHEDULE_ADMIN__/$adminName/smg;
					$text =~ s/__SCHEDULE_ADMIN_EMAIL__/$adminEmail/smg;
					$text =~ s/__SCHEDULE_ADMIN_PHONE__/$adminPhone/smg;
					$text =~ s/__SCHEDULE_ADMIN_DIALABLE_PHONE__/$dialableAdminPhone/smg;
					$text =~ s/__SCHEDULE_ADMIN_TEXT_NUMBER__/$adminTextNumber/smg;
					$text =~ s/__SCHEDULE_ADMIN_TEXTABLE_NUMBER__/$textableAdminNumber/smg;
							
					##
					##  Send the reminder text
					##
					if ( defined( $volunteerPhone) && $volunteerPhone =~ m/^[0-9-]+$/)
					{
						print "Sending a text of the schedule to $volunteerPhone\n";
						sendSMSTwilio( $volunteerPhone, $text);
						print "Sent\n";
					}
					else
					{
						print STDERR "No phone number for $name!\n";
					}
				}
			}
		}
	}
}

#------------------------------------------------------------------------------
#  sub makeCalendarFor( $$$)
#  		This routine returns a string in .ics format that contains the
#  		scheduled dates that the named individual is to volunteer between the
#  		provided start and end dates.
#------------------------------------------------------------------------------
sub makeCalendarFor( $$$)
{
	my ($name, $firstDate, $lastDate) = @_;
	my $ics;
	
	##
	##  See if this person is scheduled for the dates given
	##
	my @schedules = readScheduleFor( $name, $firstDate, $lastDate);

	##
	##	Was the person scheduled?
	##
	if ( @schedules)
	{
		my $timezoneOffset =  strftime( "%z", localtime());
		my $calendar = Data::ICal->new();
		my $timeNow = DateTime->now();

		##
		##  Build a calendar entry for each scheduled date
		##
		foreach my $schedule ( @schedules)
		{
			my $event = Data::ICal::Entry::Event->new();
			$schedule->{time} =~ m/(\d+):(\d+)/;
			my ( $hour, $minute) = ($1, $2);
			$schedule->{date} =~ m/(\d+)-(\d+)-(\d+)/;
			my ( $year, $month, $day) = ( $1, $2, $3);

			my $start = DateTime->new( year=>$year, month=>$month, day=>$day, hour=>$hour, minute=>$minute, time_zone=>$timezoneOffset);
			my $end = DateTime->new( year=>$year, month=>$month, day=>$day, hour=>$hour + 1, minute=>$minute, time_zone=>$timezoneOffset);

			$event->add_properties(
									summary => 'Volunteering',
									description => "Serving in the position: $schedule->{title}.",
									dtstamp => DateTime::Format::ICal->format_datetime( $timeNow),
									dtstart => DateTime::Format::ICal->format_datetime( $start),
									dtend => DateTime::Format::ICal->format_datetime( $end),
									status => 'CONFIRMED',
									uid => Time::HiRes::time()
								  );

			$calendar->add_entry( $event);
		}
	
		##
		##  Generate ICS 
		##
		$ics = $calendar->as_string;
	}

	return $ics;
}

#------------------------------------------------------------------------------
#  sub sendUpdateRequest( $baseURL)
#  		This function sends a request to all volunteers to update their
#  		information before the next scheduling.
#------------------------------------------------------------------------------
sub sendUpdateRequest($)
{
	local $SIG{CHLD} = "IGNORE";
	my $pid = fork();

	die "Fork failed!!\n" if (! defined( $pid));

	if ( !$pid)
	{
		my ($baseURL) = @_;
		my $template;
		my $textTemplate;

		if ( ! defined( $adminName))
		{
			loadConfig();
		}

		my $dialableAdminPhone = $adminPhone;
		my $textableAdminNumber = $adminTextNumber;
		$dialableAdminPhone =~ s/[^0-9]//g;
		$textableAdminNumber =~ s/[^0-9]//g;

		##
		##  Get a list of people volunteering on the given date
		##
		my @volunteers = readVolunteers();

		##
		##  Read in the templates
		##
		open( my $TEMPLATE, '<', "email/prescheduling.htm") || die "Couldn't read email template!\n";
		read( $TEMPLATE, $template, 999999);
		close $TEMPLATE;

		open( $TEMPLATE, '<', "sms/prescheduling.txt") || die "Couldn't read text template!\n";
		read( $TEMPLATE, $textTemplate, 999999);
		close $TEMPLATE;

		##
		##  Loop through the list, sending a request to update information
		##
		foreach  my $volunteer ( @volunteers)
		{
			##
			##  Get the info for this slot
			##
			my $name = $volunteer->{name};
			my $firstName = ($name =~ m/^([^\s]*)/) ? $1 : $name;
			my $positions = $volunteer->{desiredRoles};
			my $volunteerEmail = $volunteer->{email};
			my $volunteerPhone = $volunteer->{phone};
			my $contactMode = $volunteer->{contact};
			my $url = "$baseURL\/?user=$name";
			$url =~ s/ /%20/g;


			##
			##  Should we email the person?
			##
			if ( $contactMode =~ /email|both/)
			{
				my $email  = $template;

				my $emailPositions = $positions;
				$emailPositions =~ s/([^,]+),?/<li>$1<\/li>\n/g;

				$email =~ s/__FIRST_NAME__/$firstName/smg;
				$email =~ s/__POSITIONS__/$emailPositions/smg;
				$email =~ s/__UPDATE_URL__/$url/smg;
				$email =~ s/__SCHEDULE_ADMIN__/$adminName/smg;
				$email =~ s/__SCHEDULE_ADMIN_EMAIL__/$adminEmail/smg;
				$email =~ s/__SCHEDULE_ADMIN_PHONE__/$adminPhone/smg;
				$email =~ s/__SCHEDULE_ADMIN_DIALABLE_PHONE__/$dialableAdminPhone/smg;
				$email =~ s/__SCHEDULE_ADMIN_TEXT_NUMBER__/$adminTextNumber/smg;
				$email =~ s/__SCHEDULE_ADMIN_TEXTABLE_NUMBER__/$textableAdminNumber/smg;

				##
				##  Send the reminder email
				##
				if ( defined( $volunteerEmail) && $volunteerEmail =~ m/\S\@\S/)
				{
					sendEmail( $volunteerEmail, 'Scheduling Assistant at St. James', 'Any Information updates for volunteering?', $email, 'email/scheduling.png');
					print "Sent\n";
				}
				else
				{
					print STDERR "No email address for $name!\n";
				}
			}

			if ( $contactMode =~ /text|both/)
			{
				my $text  = $textTemplate;
				
				my $textPositions = $positions;
				$textPositions =~ s/([^,]+),?/ *  $1\n/g;

				$text =~ s/__FIRST_NAME__/$firstName/smg;
				$text =~ s/__POSITIONS__/$textPositions/smg;
				$text =~ s/__UPDATE_URL__/$url/smg;
				$text =~ s/__SCHEDULE_ADMIN__/$adminName/smg;
				$text =~ s/__SCHEDULE_ADMIN_EMAIL__/$adminEmail/smg;
				$text =~ s/__SCHEDULE_ADMIN_PHONE__/$adminPhone/smg;
				$text =~ s/__SCHEDULE_ADMIN_DIALABLE_PHONE__/$dialableAdminPhone/smg;
				$text =~ s/__SCHEDULE_ADMIN_TEXT_NUMBER__/$adminTextNumber/smg;
				$text =~ s/__SCHEDULE_ADMIN_TEXTABLE_NUMBER__/$textableAdminNumber/smg;

				##
				##  Send the reminder text
				##
				if ( defined( $volunteerPhone) && $volunteerPhone =~ m/^[0-9-]+$/)
				{
					print "Sending a text reminder to $volunteerPhone\n";
					sendSMSTwilio( $volunteerPhone, $text);
					print "Sent\n";
				}
				else
				{
					print STDERR "No phone number for $name!\n";
				}
				
			}
		}
	}
}
1;
