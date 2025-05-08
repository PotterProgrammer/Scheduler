##
##  Module to save/restore scheduling information
##
package SaveRestore;
require Exporter;
@ISA = qw( Exporter);
@EXPORT = qw( checkScheduledDates clearSavedSchedule backupData readReminderList getRoleVolunteerList readVolunteers readSlots readSchedule readScheduleFor removeSlot removeVolunteer saveVolunteer updateRoleCount saveSlot saveSchedule updateSchedule updateScheduleReminded scheduleReminder unscheduleReminder readScheduledReminder isValidUserID getAdminUID isAdminUID initDB closeDB);

use warnings;
use strict;


use DBI;
use open qw(:std :utf8);
use utf8;
use utf8::all;

use Archive::Tar;
use Crypt::OpenPGP;
use Messaging;

our $DBFilename = "./schedule.db";
my $dbh;
my $verbose = 1;

my $crontabEntryHeader = "\n##############################\n##   Send Weekly Reminders  ##\n";
my $crontabMatch = $crontabEntryHeader;
$crontabMatch =~ s/\n/./g;



sub checkScheduledDates($$);
sub getRoleVolunteerList($);
sub readReminderList($);
sub readSchedule($$);
sub readScheduleFor($$$);
sub readSlots();
sub readVolunteers(@);
sub removeSlot($);
sub saveSchedule(@);
sub saveSlot($);
sub saveVolunteer($);
sub scheduleReminder($$$);
sub unscheduleReminder();
sub updateSchedule($);
sub updateScheduleReminded($);

#------------------------------------------------------------------------------
#  sub initDB()
#  		This routine loads the DB and makes sure it is properly set up.
#------------------------------------------------------------------------------
sub initDB()
{
	openDB();

	##
	##  Create Schedule table
	##
	$dbh->do( "create table if not exists schedule
		           ( date text,
				     time text,
					 title text,
					 name text,
					 notified integer default 0,
					 reminded integer default 0
				   )");

	$dbh->do( "create index if not exists schedule_index on schedule ( date, name)");

	##
	##  Create Volunteer table
	##
	$dbh->do( "create table if not exists volunteer
		           ( name text,
				     email text,
					 phone text,
					 desiredRoles text,
					 contact text,
					 UID text,
					 primary key( 'name')
				   )");

	##
	##  Create Dates_Unavailable table
	##
	$dbh->do( 'create table if not exists dates_unavailable
		           ( name text,
				     date text
				   )');

	##
	##  Create Dates_Desired table
	##
	$dbh->do( "create table if not exists dates_desired
		           ( name text,
				     date text
				   )");

	##
	##  Create table of each position needed
	##
	$dbh->do( "create table if not exists position 
				  ( title text,
					dayOfWeek text,
					startTime text,
					endTime text,
					numberNeeded int,
					primary key( 'title')
				  )");
	
	##
	##  Create table of dates position is not needed
	##
	$dbh->do( "create table if not exists position_unneeded
				  ( title text,
				  	date text,
					primary key( 'title', 'date')
				  )");
	

	closeDB();
}

#------------------------------------------------------------------------------
#  sub openDB()
#  		This routine opens the DB
#------------------------------------------------------------------------------
sub openDB()
{
	if ( !defined( $dbh))
	{
		$dbh = DBI->connect( "dbi:SQLite:$DBFilename", "", "", {AutoCommit =>1}) or die "Sorry, couldn't open schedule database!\n";
		$dbh->{sqlite_unicode} = 1;
	}
}

#------------------------------------------------------------------------------
#  sub closeDB()
#  		This routine closes the DB.
#------------------------------------------------------------------------------
sub closeDB()
{
	if ( defined( $dbh))
	{
		$dbh->disconnect();
		undef $dbh;
	}
}

#------------------------------------------------------------------------------
#  BEGIN
#  		Make sure that we have a DB with appropriate tables ready to go
#------------------------------------------------------------------------------
BEGIN
{
	$DBFilename = "./schedule.db";
	initDB();
}

#------------------------------------------------------------------------------
#  END
#  		Make sure DB is disconnected at shutdown
#------------------------------------------------------------------------------
END
{
	closeDB();
}

#------------------------------------------------------------------------------
#  sub readSlots()
#  		This routine reads the list of slots to be filled for a given date range.
#  		The routine returns an array of references to the "slot" records.
#------------------------------------------------------------------------------
sub readSlots()
{
	openDB();
	my $positions = $dbh->selectall_arrayref( "select * from position order by title ASC", {Slice=>{}});
	closeDB();
	return( @$positions);
}


#------------------------------------------------------------------------------
#  sub readVolunteers( [$name])
#  		This routine reads the requested row from the volunteer
#  		table and returns an array of references to the volunteer records.  If
#  		no name is provided, all volunteers are included in the list
#------------------------------------------------------------------------------
sub readVolunteers(@)
{
	my ($name) = @_;
	my $query;

	if ( defined( $name))
	{
		$query = "select * from volunteer where name like '$name'";
	}
	else
	{
		$query = "select * from volunteer order by name ASC";
	}

	openDB();

	my $volunteers = $dbh->selectall_arrayref( $query, {Slice=>{}});

	my $unavailable = $dbh->prepare( "select * from dates_unavailable where name=?");
	my $desired = $dbh->prepare( "select * from dates_desired where name=?");

	##
	##  Get a list of unavailable and desired dates for each volunteer
	##
	foreach my $volunteer (@$volunteers)
	{
		if ( $verbose)
		{
			print "Checking for $volunteer->{name}\n";
		}
		
		##
		##  Find unavailable dates for this person
		##
		$unavailable->bind_param( 1, $volunteer->{name});
		$unavailable->execute();
		my $dates = $unavailable->fetchall_arrayref( {});
		if ( defined( $dates) && @$dates)
		{
			my $dateList = join( ",",( map { $_->{date} } @$dates) );
			$volunteer->{daysUnavailable} = $dateList;
			if ( $verbose)
			{
				print "$dates->[0]->{name} is unavailable on: $dateList\n";
			}
		}
		
		##
		##  Find desired dates for this person
		##
		$desired->bind_param( 1, $volunteer->{name});
		$desired->execute();
		$dates = $desired->fetchall_arrayref( {});
		if ( defined( $dates) && @$dates)
		{
			my $dateList = join( ",",( map { $_->{date} } @$dates) );
			$volunteer->{daysDesired} = $dateList;
			if ( $verbose)
			{
				print "$dates->[0]->{name} wants to volunteer on: $dateList\n";
			}
		}

		##
		##  Set initial worked dates for this run to zero
		##
		$volunteer->{timesScheduled} = 0;
	}

	closeDB();

	return( @$volunteers);
}

#------------------------------------------------------------------------------
#  sub removeSlot( $positionTitle)
#		This routine removes the information with the provided title from
#		the "position" table.
#------------------------------------------------------------------------------
sub removeSlot($)
{
	my $title = $_[0];

	if ( $verbose)
	{
		print "*** Deleting position: $title\n";
	}

	openDB();

	my $sth = $dbh->prepare( "delete from position where title = ?");
	$sth->bind_param( 1, $title);
	$sth->execute();

	closeDB();
}

#------------------------------------------------------------------------------
#  sub removeVolunteer( $name)
#		This routine removes the named individual's entries from the
#		"volunteer", the "dates_unavailable", and the "dates_desired" tables.
#------------------------------------------------------------------------------
sub removeVolunteer($)
{
	my $name = $_[0];

	if ( $verbose)
	{
		print "*** Deleting volunteer: $name\n";
	}
	
	openDB();

	my $sth = $dbh->prepare( "delete from volunteer where name = ?");
	$sth->bind_param( 1, $name);
	$sth->execute();
	$sth = $dbh->prepare( "delete from dates_unavailable where name=?");
	$sth->bind_param( 1, $name);
	$sth->execute();
	$sth = $dbh->prepare( "delete from dates_desired where name=?");
	$sth->bind_param( 1, $name);
	$sth->execute();
	
	closeDB();
}

#------------------------------------------------------------------------------
#  sub saveSlot( $slot)
#		This routine saves the information in the provided "slot" hashref to
#		the "position" table.
#------------------------------------------------------------------------------
sub saveSlot($)
{
	my $slot = $_[0];

	openDB();

	my $sth = $dbh->prepare( "insert or replace into position (title, dayOfWeek, startTime, endTime, numberNeeded) values (?,?,?,?,?)");
	$sth->bind_param( 1, $slot->{title});
	$sth->bind_param( 2, $slot->{dayOfWeek});
	$sth->bind_param( 3, $slot->{startTime});
	$sth->bind_param( 4, $slot->{endTime});
	$sth->bind_param( 5, $slot->{numberNeeded});
	$sth->execute();

	closeDB();
}

#------------------------------------------------------------------------------
#  sub saveVolunteer( $volunteer)
#		This routine saves the information in the provide "volunteer" hashref to the "volunteer" table.
#------------------------------------------------------------------------------
sub saveVolunteer($)
{
	my $volunteer = $_[0];

	##
	##  Does this volunteer have a UID?
	##
	if ( !defined( $volunteer->{UID}) || $volunteer->{UID} =~ /^\s*$/)
	{
		$volunteer->{UID} = generateUID();
	}

	openDB();

	##
	##  First, update the volunteer table
	##
	my $sth = $dbh->prepare( "insert or replace into volunteer (name, email, phone, desiredRoles, contact, UID ) values (?,?,?,?,?,?)");
	$sth->bind_param( 1, $volunteer->{name});
	$sth->bind_param( 2, $volunteer->{email});
	$sth->bind_param( 3, $volunteer->{phone});
	$sth->bind_param( 4, $volunteer->{desiredRoles});
	$sth->bind_param( 5, $volunteer->{contact});
	$sth->bind_param( 6, $volunteer->{UID});
	
 print "Storing the volunteer values $volunteer->{name}, $volunteer->{email}, $volunteer->{phone}, $volunteer->{desiredRoles}, $volunteer->{contact}\n";
	$sth->execute();

	#------------------------------------------------------------------------------
	#	Update entries in the dates_desired table
	#------------------------------------------------------------------------------
	#
	##
	##  First delete any existing entries in the table for this person
	##
	print "Issuing delete against any old desired dates for $volunteer->{name}\n";
	$dbh->do( "delete from dates_desired where name = ?", undef, $volunteer->{name});
	
	##
	##  Store updated desired dates, if any
	##
	if ( defined( $volunteer->{daysDesired}))
	{
		print "Issuing inserts into dates_desired\n";
		my $desired = $dbh->prepare( "insert into dates_desired (name, date) values (?,?)");
		my @dates = split( /,/, $volunteer->{daysDesired});
		foreach my $date (@dates)
		{
			if ( $date ne "-none-")
			{
				print "Inserting $date\n";
				$desired->bind_param( 1, $volunteer->{name});
				$desired->bind_param( 2, $date);
				$desired->execute();
			}
		}
	}

	#------------------------------------------------------------------------------
	#	Update entries in the dates_unavailable table
	#------------------------------------------------------------------------------
	##
	##  First delete any existing entries in the table for this person
	##
	print "Issuing delete against any old unavailable dates for $volunteer->{name}\n";
	$dbh->do( "delete from dates_unavailable where name = ?", undef, $volunteer->{name});
	
	##
	##  Store unavailable dates, if any
	##
	if ( defined( $volunteer->{daysUnavailable}))
	{
		print "Inserting dates into dates_unavailable\n";
		my $unavailable = $dbh->prepare( "insert into dates_unavailable (name, date) values (?,?)");
		my @dates = split( /,/, $volunteer->{daysUnavailable});
		foreach my $date (@dates)
		{
			if ( $date ne "-none-")
			{
				print "Inserting $date\n";
				$unavailable->bind_param( 1, $volunteer->{name});
				$unavailable->bind_param( 2, $date);
				$unavailable->execute();
			}
		}
	}

	closeDB();

	print "$volunteer->{name} added...\n";
	
}

#------------------------------------------------------------------------------
#  sub getRoleVolunteerList( $title)
#  		This routine reads the names of volunteers for the given role  and
#  		returns it as an array.
#------------------------------------------------------------------------------
sub getRoleVolunteerList($)
{
	my ($title) = @_;
	$title = '%'. $title . '%';

	openDB();

	my @names = $dbh->selectall_array( "select name from volunteer where desiredRoles like ? order by name ASC", undef, $title);

	closeDB();

	@names = map { $_->[0]} @names;

	print "I found the names: " . join( ', ', @names) . " for $title\n";
	return( @names);
}

#------------------------------------------------------------------------------
#  sub checkScheduledDates($$)
#  		This routine looks to see if there are any dates in the existing
#  		schedule that conflict with the provided date range.  The routine
#  		returns an array of all dates that overlap.
#------------------------------------------------------------------------------
sub checkScheduledDates($$)
{
	my ( $startDate, $endDate) = @_;

	openDB();

	my @dates = $dbh->selectall_array( "Select distinct date from schedule where date >= ? and date <= ? order by date ASC", undef, $startDate, $endDate);

	closeDB();

	@dates = map { $_->[0]} @dates;
	return @dates;
}


#------------------------------------------------------------------------------
#  sub clearSavedSchedule($startDate, $endDate)
#  		This routine clears the saved schedule for the range of dates provided.
#------------------------------------------------------------------------------
sub clearSavedSchedule($$)
{
	my ($startDate, $endDate) = @_;
	print "Removing schedule entries for dates between $startDate and $endDate\n";

	openDB();

	$dbh->do( "delete from schedule where date >= ? and date <= ?", undef, $startDate, $endDate);

	closeDB();

}

#------------------------------------------------------------------------------
#  sub readScheduleFor( $name, $startDate, $endDate)
#  		This routine reads the schedule for the given name across the range of
#  		dates provided and returns it as an array of references to schedule
#  		entries.
#------------------------------------------------------------------------------
sub readScheduleFor($$$)
{
	my ( $name, $startDate, $endDate) = @_;

	openDB();

	my $schedule = $dbh->selectall_arrayref( "select * from schedule where name=? and date >= ? and date <= ? order by date ASC, title ASC", {Slice=>{}}, $name, $startDate, $endDate);

	closeDB();

	return( @$schedule);
}

#------------------------------------------------------------------------------
#  sub readSchedule($startDate, $endDate)
#  		This routine reads the schedule for the range of dates provided and
#  		returns it as an array of references to schedule entries.
#------------------------------------------------------------------------------
sub readSchedule($$)
{
	my ($startDate, $endDate) = @_;

	openDB();

	my $schedule = $dbh->selectall_arrayref( "select * from schedule where date >= ? and date <= ? order by date ASC, title ASC", {Slice=>{}}, $startDate, $endDate);

	closeDB();

	return( @$schedule);
}

#------------------------------------------------------------------------------
#  sub readReminderList( $nextNDays)
#  		This routine reads the schedule for a list of all people who need to be
#  		reminded that they are volunteering in the next "N" days and returns it
#  		as an array of references to schedule entries.
#------------------------------------------------------------------------------
sub readReminderList($)
{
	my ($nDays) = @_;
	my $endDate = "$nDays days";

	openDB();

	my $schedule = $dbh->selectall_arrayref( "select * from schedule where date >= date('now') and date <= date( 'now', ?) and reminded=0 order by date ASC, title ASC", {Slice=>{}}, $endDate);

	closeDB();

	return( @$schedule);
}


#------------------------------------------------------------------------------
#  sub saveSchedule( @Schedule)
#  		This routine saves the currently generated schedule
#------------------------------------------------------------------------------
sub saveSchedule(@)
{
	my @schedules = @_;

	openDB();

	my $sth = $dbh->prepare( "insert or replace into schedule (date, time, title, name) values (?,?,?,?)");

	foreach my $slot (@schedules)
	{
		$sth->bind_param( 1, $slot->{date});
		$sth->bind_param( 2, $slot->{time});
		$sth->bind_param( 3, $slot->{title});
		if ( defined( $slot->{name}) && (length( $slot->{name}) > 0))
		{
			$sth->bind_param( 4, $slot->{name});
		}
		else
		{
			$sth->bind_param( 4, "—unfilled—");
		}
		$sth->execute();
	}

	closeDB();
}
	
#------------------------------------------------------------------------------
#  sub updateSchedule( $shedule)
#		This routine saves the information in the provided "schedule" hashref to
#		the "schedule" table.
#------------------------------------------------------------------------------
sub updateSchedule($)
{
	my $schedule = $_[0];

	openDB();

	my $sth = $dbh->prepare( "update schedule set name=? where date=? and title=? and name=?");
	$sth->bind_param( 1, $schedule->{name});
	$sth->bind_param( 2, $schedule->{date});
	$sth->bind_param( 3, $schedule->{title});
	$sth->bind_param( 4, $schedule->{oldName});
	$sth->execute();

	closeDB();
}

#------------------------------------------------------------------------------
#  sub updateScheduleReminded( $scheduledPosition)
#  		This function updates the schedule to note that the given person for
#  		the given position has been reminded.
#------------------------------------------------------------------------------
sub updateScheduleReminded($)
{
	my ( $scheduledPosition) = @_;

	openDB();

	my $sth = $dbh->prepare( "update schedule set reminded=1 where date=? and title=? and name=?");
	$sth->bind_param( 1, $scheduledPosition->{date});
	$sth->bind_param( 2, $scheduledPosition->{title});
	$sth->bind_param( 3, $scheduledPosition->{name});
	$sth->execute();

	closeDB();
}

#------------------------------------------------------------------------------
#  sub backupData()
#  		This function backs up the current DB and config info into a file and
#  		returns the filename.
#------------------------------------------------------------------------------
sub backupData()
{
		my $tar = Archive::Tar->new;
		
		##
		##  Remove old files
		##
		unlink( 'public/dataBackup.pbt');
		unlink( 'reminderSchedule.txt');

		##
		##  Store the current reminder schedule
		##
		my ( $enabled, $hour, $minute, $weekday, $crontab) = readScheduledReminder();
		open( my $FILE, '>', 'reminderSchedule.txt') || die "Couldn't save reminder schedule! $!\n";
		printf $FILE "%d %02d:%02d  %s\n", $enabled, $hour, $minute, $weekday;
		close $FILE;

		print "Making a backup!\n";
		$tar->add_files( $DBFilename, $Messaging::ConfigName, 'reminderSchedule.txt');
		my $tarData = $tar->write();

		my $pgp = Crypt::OpenPGP->new( Compat => 'GnuPG');
		my $encrypted = $pgp->encrypt( Data => $tarData, Passphrase => 'TryToBeTimely');
		open( my $PBT, '>', 'public/dataBackup.pbt');
		binmode( $PBT);
		syswrite( $PBT, $encrypted);
		close( $PBT);

		unlink( 'reminderSchedule.txt');
		return( 'dataBackup.pbt');
}


#------------------------------------------------------------------------------
#  sub scheduleReminder( $weekday, $time, $port)
#  		This function schedules a recurring call to '/sendReminders' at the
#  		indicated port.
#------------------------------------------------------------------------------
sub scheduleReminder($$$)
{
	my ( $weekday, $time, $port) = @_;

	##
	##  Break the time in to hour and minute
	##
	my ( $hour, $minute) = split( ':', $time);
	my %weekdays = ( Sunday=>0, Monday=>1, Tuesday=>2, Wednesday=>3, Thursday=>4, Friday=>5, Saturday=>6);

	##
	##  Are we running on Windows?
	##
	if ( $^O =~ /Win/)
	{
		#=======================================================
		#  If so, use schtasks to schedule the reminder  
		#=======================================================
		my %days = ( Sunday=>"SUN", Monday=>"MON", Tuesday=>"TUE", Wednesday=>"WED", Thursday=>"THU", Friday=>"FRI", Saturday=>"SAT");

		##
		##  Generate the cmd to issue
		##
		my $cmd = sprintf( "schtasks /create /f /sc WEEKLY /d %s  /ST %02d:%02d /tn \"SendSchedulerReminders\" /tr \"" .
			               "curl -b UID=%s http://localhost:%d/sendReminders\"", $days{$weekday}, $hour, $minute, getAdminUID(), $port);
	
		##
		##  Run the schtasks command
		##
		system( $cmd);
	}
	else
	{
		my $newLine = sprintf( "%02d %02d * * %02d curl -b UID=%s http://localhost:%d/sendReminders", $minute, $hour, $weekdays{$weekday}, getAdminUID(), $port);
	
		##
		##  Read in the current crontab
		##
		my ( $enabled, $hr, $min, $day, $crontab) = readScheduledReminder();
		
		##
		##  Is there currently an entry for sendReminders?
		##
		if ( $enabled)
		{
			printf( "Replacing old Crontab of $day at %02d:%02d with  $weekday at %02d:%02d\n", $hr, $min, $hour, $minute);
			$crontab =~ s/$crontabMatch(.*?)$/$crontabEntryHeader$newLine/sm;
		}
		else
		{
			$crontab .= "$crontabEntryHeader$newLine\n";
		}

		##
		##  Store the new crontab
		##
		open( my $CRONFILE, '>', 'my_crontab') || die "Can't open crontab file! $!\n";
		print $CRONFILE $crontab;
		close $CRONFILE;

		##
		##  Remove the old crontab
		##
		system( "crontab -r");
		
		##
		## 	Set new crontab in place
		##
		system( "crontab my_crontab");
	}
}

#------------------------------------------------------------------------------
#  sub unscheduleReminder()
#  		This function unschedules a recurring call to '/sendReminders'.
#------------------------------------------------------------------------------
sub unscheduleReminder()
{
	##
	##  Read in the current crontab
	##
	my ( $enabled, $hr, $min, $day, $crontab) = readScheduledReminder();
	
	##
	##  Are we running in Windows?
	##
	if ( $^O =~ /Win/)
	{
		##
		##  For Windows use schtasks to remove scheduled task
		##
		system( 'schtasks /Delete /TN "SendSchedulerReminders" /F 2>NUL:');
	}
	else
	{
		
		##
		##  Is there currently an entry for sendReminders?
		##
		if ( $crontab =~ m/$crontabMatch.*?/sm)
		{
			##
			##  If so, remove the entry
			##
			$crontab =~ s/\s*$crontabMatch(.*?)$.*$//sm;

			##
			##  Store the new crontab
			##
			open( my $CRONFILE, '>', 'my_crontab') || die "Can't open crontab file! $!\n";
			print $CRONFILE $crontab;
			close $CRONFILE;

			##
			##  Remove the old crontab
			##
			system( "crontab -r");
			
			##
			## 	Set new crontab in place
			##
			system( "crontab my_crontab");
		}
	}
}

#------------------------------------------------------------------------------
#  sub readScheduledReminder()
#  		This routine reads the crontab to see if a schedule reminder is set and
#  		if so sets "enabled" to true.  It returns the following:
#		( $enabled, $hour, $minute, $weekday, $crontab)
#		Where "weekday" is one of "Sunday, Monday, ..." and $crontab is the
#		entire contents of the current crontab.
#------------------------------------------------------------------------------
sub readScheduledReminder()
{
	if ( $^O =~ /Win/)
	{
		return readWindowsScheduledReminder();
	}
	else
	{
		return readUnixScheduledReminder();
	}
}

#------------------------------------------------------------------------------
#  sub readUnixScheduledReminder()
#  		This routine reads the crontab to see if a schedule reminder is set and
#  		if so sets "enabled" to true.  It returns the following:
#		( $enabled, $hour, $minute, $weekday, $crontab)
#		Where "weekday" is one of "Sunday, Monday, ..." and $crontab is the
#		entire contents of the current crontab.
#------------------------------------------------------------------------------
sub readUnixScheduledReminder()
{
	my $enabled = 0;
	my $hour = 0;
	my $minute = 0;
	my $day = 0;
	my $weekday = 'Sunday';
	my @dayName = qw( Sunday Monday Tuesday Wednesday Thursday Friday Saturday );

	##
	##  Read in the current crontab
	##
	my $crontab = `crontab -l`;
	
	##
	##  Is there currently an entry for sendReminders?
	##
	if ( $crontab =~ m/$crontabMatch(.*?)$/sm)
	{
		my $matched = $1;
		$matched =~ /^\s*(\d+)\s+(\d+)\s+.\s+.\s+(\d+)/;
		($minute, $hour, $day) = ($1, $2, $3);
		$weekday = $dayName[$day];
		$enabled = 1;
	}

	return( $enabled, $hour, $minute, $weekday, $crontab);
}

#------------------------------------------------------------------------------
#  sub readWindowsScheduledReminder()
#  		This routine uses schtasks to see if a schedule reminder is set and
#  		if so sets "enabled" to true.  It returns the following:
#		( $enabled, $hour, $minute, $weekday, $crontab)
#		Where "weekday" is one of "Sunday, Monday, ..." and $crontab is the
#		the command scheduled.
#------------------------------------------------------------------------------
sub readWindowsScheduledReminder()
{
	my $enabled = 0;
	my $hour = 0;
	my $minute = 0;
	my $weekday = 'Sunday';
	my $crontab = '';
	my %dayName = ( SUN =>"Sunday", MON => "Monday", TUE => "Tuesday", WED => "Wednesday", THU => "Thursday", FRI => "Friday", SAT => "Saturday" );

	my $taskQueryResult = `schtasks /query /tn SendSchedulerReminders /Fo LIST /V`;

	##
	##  Was a task scheduled?
	##
	if ( $taskQueryResult !~ m/^ERROR/)
	{
		$enabled = 1;
		$taskQueryResult =~ /Start Time:\s+(\d+):(\d\d):\d\d ([AP]M)/;
		$hour = $1;
		$minute = $2;
		if ( $3 =~ /PM/)
		{
			$hour += 12;
		}

		$taskQueryResult =~ /Days:\s+(\S+)/;
		$weekday = $dayName{ $1};

		$taskQueryResult =~ /Task To Run:\s+(.*)$/;
		$crontab = $1;
	}
	
	return( $enabled, $hour, $minute, $weekday, $crontab);
}

#------------------------------------------------------------------------------
#	sub isValidUserID( $username, $id) 
#		This routines checks the volunteer table to see if there is an entry
#		for $username, and if so, if the stored UID matches the value provided
#		in $id.  True is returned if the name is found and the ID matches.
##------------------------------------------------------------------------------
sub isValidUserID($$)
{
	my ($name, $id) = (@_);
	
	openDB();

	my $matches = $dbh->selectall_arrayref( "select UID from volunteer where name = ?", undef, $name);

	closeDB();
	
	print "Looking for $name and got " . int( @$matches) . " matches\n";

	print "Got " .  $matches->[0]->[0] . "\n";
	if (( @$matches == 1) && ( $matches->[0]->[0] eq $id))
	{
		return 1;
	}

	return 0;
}

#------------------------------------------------------------------------------
#	sub generateUID()
#		This routine generates a random 10 character alpha-numeric string
#------------------------------------------------------------------------------
sub generateUID()
{
	my @chars = ( 'a'..'z', '0'..'9', 'A'..'Z');
	my $id;
	do 
	{
		$id = '';
		for( 1..10)
		{
			$id .= $chars[ int rand( @chars)];
		}
	} while( (unpack( "%32W*", $id) % 42) == 0);

	return $id;
}

#------------------------------------------------------------------------------
#	sub getAdminUID()
#		This routine generates a random 10 character alpha-numeric string
#------------------------------------------------------------------------------
sub getAdminUID()
{
	my @chars = ( 'a'..'z', '0'..'9', 'A'..'Z');
	my $id;
	do 
	{
		$id = '';
		for( 1..10)
		{
			$id .= $chars[ int rand( @chars)];
		}
	} while( (unpack( "%32W*", $id) % 42) != 0);

	return $id;
}

#------------------------------------------------------------------------------
#	sub isAdminUID( $id) 
#------------------------------------------------------------------------------
sub isAdminUID( $)
{
	my $id = shift( @_);

	return( !( unpack( "%32W*", $id) % 42));
}

1;
