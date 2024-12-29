##
##  Module to send messages to volunteers/organizers
##
package Messaging;

require Exporter;
@ISA = qw( Exporter);
@EXPORT = qw( sendEmail sendReminders sendUpdateRequest);

use warnings;
use strict;

use DBI;

use Email::Send::SMTP::Gmail;
use SaveRestore;


##-->use Email::Sender::Simple qw(try_to_sendmail);
##-->use Email::Simple;
##-->use Email::Simple::Creator;
##-->use Email::Sender::Transport::SMTP;
##-->use Email::Sender::Transport::SMTP::TLS;
##-->use WWW::Twilio::API;
##-->use WWW::Twilio::TwiML;
use URI::Escape;

use open qw(:std :utf8);
use utf8;
use utf8::all;

sub sendReminders($);

my $HOME = $ENV{'HOME'};
my $emailSender;
my $email_pwd;
my $email_uid;
my $email_smtp;
my $email_port;
my $email_use_ssl = 0;
my $email_use_tls = 0;
my $AlwaysTwilio;
my $TwilioAccount;
my $TwilioAuth;
my $TwilioGender;
my $TwilioIntro;
my $TwilioNumber;
my $callerIDNumber;
my $logging;
my $max_retries = 3;
my $delayBetweenRetries = 45;
my $uid;
my $pwd;


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
 if ( -e "$HOME/ET2/config.cfg")
	{
	 open( CFG, "$HOME/ET2/config.cfg");
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
		 if ( m/EmailSSL=(.*)/)
			{
			 $email_use_ssl= int($1);
			 next;
			}
		 if ( m/EmailTLS=(.*)/)
			{
			 $email_use_tls=int($1);
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
		 if ( m/TwilioGender=(.*)/)
		 	{
			 $TwilioGender=$1;
			 next;
			}
		 if ( m/TwilioIntro=(.*)/)
		 	{
			 $TwilioIntro=$1;
			 next;
			}
		 if ( m/TwilioAlways=(.*)/)
		 	{
			 $AlwaysTwilio=$1;
			 next;
			}
		 if ( m/Logging=(.*)/)
		 	{
			 $logging = $1;
			 next;
			}
		 if ( m/MaxRetries=(.*)/)
		 	{
			 $max_retries = $1;
			 next;
			}
		 if ( m/DelayBetweenRetries=(.*)/)
		 	{
			 $delayBetweenRetries = $1;
			 next;
			}
		 if (m/CallerIDNumber=(.*)/i)
		 	{
			 $callerIDNumber = $1;
			}
		}
	 close CFG;
	}
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
#  sub sendUpdateRequest( $baseURL)
#  		This function sends a request to all volunteers to update their
#  		information before the next scheduling.
#------------------------------------------------------------------------------
sub sendUpdateRequest($)
{
	my ($baseURL) = @_;
	my $template;

	##
	##  Get a list of people volunteering on the given date
	##
	my @volunteers = readVolunteers();

	##
	##  Read in the template
	##
	open( my $TEMPLATE, '<', "email/prescheduling.htm") || die "Couldn't read email template!\n";
	read( $TEMPLATE, $template, 999999);
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

		print "Volunteer email = $volunteerEmail\n";
		$positions =~ s/([^,]+),?/<li>$1<\/li>\n/g;


		my $email  = $template;

		$email =~ s/__FIRST_NAME__/$firstName/smg;
		$email =~ s/__POSITIONS__/$positions/smg;
		$email =~ s/__UPDATE_URL__/$baseURL\/$name/smg;

		##
		##  Send the reminder email
		##
		if ( defined( $volunteerEmail) && $volunteerEmail =~ m/\S\@\S/)
		{
			sendEmail( $volunteerEmail, 'Scheduling Assistant at St. James', 'Service reminder', $email, 'email/scheduling.png');
			print "Sent\n";
		}
		else
		{
			print STDERR "No email address for $name!\n";
		}
	}
}

#------------------------------------------------------------------------------
#  sub sendReminders( $numberOfDays)
#  		This function sends reminders to everyone who is scheduled to volunteer
#  		in the next number of days
#------------------------------------------------------------------------------
sub sendReminders($)
{
	my ($number) = @_;
	my $template;
    my $admin = 'Pastor Bobby';
	my $adminEmail = 'pastor@stjamesbg.org';
	my $adminPhone = '270-842-4949';
##-->	my $adminTextNumber = '859-420-4784';
	my $adminTextNumber = '270-777-6029';


	my $dialableAdminPhone = $adminPhone;
	my $textableAdminNumber = $adminTextNumber;
	$dialableAdminPhone =~ s/[^0-9]//g;
	$textableAdminNumber =~ s/[^0-9]//g;

	##
	##  Get a list of people volunteering on the given date
	##
	my @volunteers = readReminderList( $number);

	##
	##  Read in the template
	##
	open( my $TEMPLATE, '<', "email/reminder.htm") || die "Couldn't read email template!\n";
	read( $TEMPLATE, $template, 999999);
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

		my $email  = $template;

		$email =~ s/__FIRST_NAME__/$firstName/smg;
		$email =~ s/__NAME__/$name/smg;
		$email =~ s/__DATE__/$date/smg;
		$email =~ s/__TIME__/$time/smg;
		$email =~ s/__POSITION__/$position/smg;
		$email =~ s/__SCHEDULE_ADMIN__/$admin/smg;
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
			sendEmail( $volunteerEmail, 'Scheduling Assistant @ St. James', 'Service reminder', $email, 'email/reminder.png');
			print "Sent\n";
		}
		else
		{
			print STDERR "No email address for $name!\n";
		}
		
		##
		##  Note that this person was notified
		##
		updateScheduleReminded( $scheduledVolunteer);
	}
}
1;
