##
##  Module to save/restore scheduling information
##
package SaveRestore;
require Exporter;
@ISA = qw( Exporter);
@EXPORT = qw( checkScheduledDates clearSavedSchedule backupData readReminderList getRoleVolunteerList readVolunteers readSlots readSchedule readScheduleFor removeSlot removeVolunteer saveVolunteer saveSlot saveSchedule updateSchedule updateScheduleReminded);

use warnings;
use strict;


use DBI;
use open qw(:std :utf8);
use utf8;
use utf8::all;

use Archive::Tar;
use Messaging;

our $DBFilename = "./schedule.db";
my $dbh;
my $verbose = 1;


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
sub updateSchedule($);
sub updateScheduleReminded($);

#------------------------------------------------------------------------------
#  BEGIN
#  		Make sure that we have a DB with appropriate tables ready to go
#------------------------------------------------------------------------------
BEGIN
{
	$DBFilename = "./schedule.db";

	if ( !defined( $dbh))
	{
		$dbh = DBI->connect( "dbi:SQLite:$DBFilename", "", "") or die "Sorry, couldn't open schedule database!\n";
		$dbh->{sqlite_unicode} = 1;
	}

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
					time text,
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
	

}

#------------------------------------------------------------------------------
#  END
#  		Make sure DB is disconnected at shutdown
#------------------------------------------------------------------------------
END
{
	if ( defined( $dbh))
	{
		print "Disconneting!\n";
		$dbh->disconnect();
	}
}

#------------------------------------------------------------------------------
#  sub readSlots()
#  		This routine reads the list of slots to be filled for a given date range.
#  		The routine returns an array of references to the "slot" records.
#------------------------------------------------------------------------------
sub readSlots()
{
	my $positions = $dbh->selectall_arrayref( "select * from position order by title ASC", {Slice=>{}});
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
	return( @$volunteers);
}

#------------------------------------------------------------------------------
#  sub removeSlot( $positionTitle)
#		This routine removess the information with the provided title from
#		the "position" table.
#------------------------------------------------------------------------------
sub removeSlot($)
{
	my $title = $_[0];

	if ( $verbose)
	{
		print "*** Deleting position: $title\n";
	}
	my $sth = $dbh->prepare( "delete from position where title = ?");
	$sth->bind_param( 1, $title);
	$sth->execute();
}

#------------------------------------------------------------------------------
#  sub removeVolunteer( $name)
#		This routine removes the named individual's entry from the volunteer,
#		the "position" table.
#------------------------------------------------------------------------------
sub removeVolunteer($)
{
	my $name = $_[0];

	if ( $verbose)
	{
		print "*** Deleting volunteer: $name\n";
	}
	my $sth = $dbh->prepare( "delete from volunteer where name = ?");
	$sth->bind_param( 1, $name);
	$sth->execute();
	$sth = $dbh->prepare( "delete from dates_unavailable where name=?");
	$sth->bind_param( 1, $name);
	$sth->execute();
	$sth = $dbh->prepare( "delete from dates_desired where name=?");
	$sth->bind_param( 1, $name);
	$sth->execute();
}

#------------------------------------------------------------------------------
#  sub saveSlot( $slot)
#		This routine saves the information in the provided "slot" hashref to
#		the "position" table.
#------------------------------------------------------------------------------
sub saveSlot($)
{
	my $slot = $_[0];
	my $sth = $dbh->prepare( "insert or replace into position (title, dayOfWeek,time, numberNeeded) values (?,?,?,?)");
	$sth->bind_param( 1, $slot->{title});
	$sth->bind_param( 2, $slot->{dayOfWeek});
	$sth->bind_param( 3, $slot->{time});
	$sth->bind_param( 4, $slot->{numberNeeded});
	$sth->execute();
}

#------------------------------------------------------------------------------
#  sub saveVolunteer( $volunteer)
#		This routine saves the information in the provide "volunteer" hashref to the "volunteer" table.
#------------------------------------------------------------------------------
sub saveVolunteer($)
{
	my $volunteer = $_[0];

	print "Issuing the first insert.\n";
	##
	##  First, update the volunteer table
	##
	my $sth = $dbh->prepare( "insert or replace into volunteer (name, email, phone, desiredRoles, contact) values (?,?,?,?,?)");
	$sth->bind_param( 1, $volunteer->{name});
	$sth->bind_param( 2, $volunteer->{email});
	$sth->bind_param( 3, $volunteer->{phone});
	$sth->bind_param( 4, $volunteer->{desiredRoles});
	$sth->bind_param( 5, $volunteer->{contact});
 print "Storing the volunteer values $volunteer->{name}, $volunteer->{email}, $volunteer->{phone}, $volunteer->{desiredRoles}, $volunteer->{contact}\n";
	$sth->execute();

	#------------------------------------------------------------------------------
	#	Update entries in the dates_desired table
	#------------------------------------------------------------------------------
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
	my @names = $dbh->selectall_array( "select name from volunteer where desiredRoles like ? order by name ASC", undef, $title);
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
	my @dates = $dbh->selectall_array( "Select distinct date from schedule where date >= ? and date <= ? order by date ASC", undef, $startDate, $endDate);
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
	$dbh->do( "delete from schedule where date >= ? and date <= ?", undef, $startDate, $endDate);
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
	my $schedule = $dbh->selectall_arrayref( "select * from schedule where name=? and date >= ? and date <= ? order by date ASC, title ASC", {Slice=>{}}, $name, $startDate, $endDate);
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
	my $schedule = $dbh->selectall_arrayref( "select * from schedule where date >= ? and date <= ? order by date ASC, title ASC", {Slice=>{}}, $startDate, $endDate);
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
	my $schedule = $dbh->selectall_arrayref( "select * from schedule where date >= date('now') and date <= date( 'now', ?) and reminded=0 order by date ASC, title ASC", {Slice=>{}}, $endDate);
	return( @$schedule);
}


#------------------------------------------------------------------------------
#  sub saveSchedule( @Schedule)
#  		This routine saves the currently generated schedule
#------------------------------------------------------------------------------
sub saveSchedule(@)
{
	my @schedules = @_;
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
}
	
#------------------------------------------------------------------------------
#  sub updateSchedule( $shedule)
#		This routine saves the information in the provided "schedule" hashref to
#		the "schedule" table.
#------------------------------------------------------------------------------
sub updateSchedule($)
{
	my $schedule = $_[0];
	my $sth = $dbh->prepare( "update schedule set name=? where date=? and title=? and name=?");
	$sth->bind_param( 1, $schedule->{name});
	$sth->bind_param( 2, $schedule->{date});
	$sth->bind_param( 3, $schedule->{title});
	$sth->bind_param( 4, $schedule->{oldName});
	$sth->execute();
}

#------------------------------------------------------------------------------
#  sub updateScheduleReminded( $scheduledPosition)
#  		This function updates the schedule to note that the given person for
#  		the given position has been reminded.
#------------------------------------------------------------------------------
sub updateScheduleReminded($)
{
	my ( $scheduledPosition) = @_;

	my $sth = $dbh->prepare( "update schedule set reminded=1 where date=? and title=? and name=?");
	$sth->bind_param( 1, $scheduledPosition->{date});
	$sth->bind_param( 2, $scheduledPosition->{title});
	$sth->bind_param( 3, $scheduledPosition->{name});
	$sth->execute();
}

#------------------------------------------------------------------------------
#  sub backupData()
#  		This function backs up the current DB and config info into a file and
#  		returns the filename.
#------------------------------------------------------------------------------
sub backupData()
{
		my $tar = Archive::Tar->new;
		unlink( 'public/dataBackup.tar');
		unlink( 'public/dataBackup.pbt');
		$tar->add_files( $DBFilename, $Messaging::ConfigName);
		$tar->write( 'public/dataBackup.tar');
		print "Making a backup!\n";
		system( "gpg --yes --no-tty --batch --passphrase TryToBeTimely --quiet --no-use-agent -o public/dataBackup.pbt -c public/dataBackup.tar");
		unlink( 'public/dataBackup.tar');
		return( 'dataBackup.pbt');
}


1;
