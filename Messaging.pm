##
##  Module to send messages to volunteers/organizers
##
package Messaging;

require Exporter;
@ISA = qw( Exporter);
@EXPORT = qw( sendEmail);

use warnings;
use strict;

use DBI;

use Email::Send::SMTP::Gmail;
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
#  sendEmail( $to, $from, $sub, $message)
#		This function uses the default email settings to send an email message.
#		The function returns a non-zero value if an error occurred.
#------------------------------------------------------------------------------
sub sendEmail($$$$)
{
 my ( $to, $from, $subj, $message) = @_;
##--> my $transport;

 if ( !defined( $email_uid))
 {
	 loadConfig();
 }

  
	my ($mailer, $error) = Email::Send::SMTP::Gmail->new( -smtp=> $email_smtp,
														  -login=>$email_uid,
														  -pass=>$email_pwd);

	print STDERR "Can't get mail connection!! $error" if ( defined( $error) && length( $error));

	
	$mailer->send( -to => $to,
				   -subject => $subj,
				   -from => 'Scheduling Assistant @ St. James',
				   -contenttype => "text/html",
				   -body => $message
				 );
	$mailer->bye;
}

1;
