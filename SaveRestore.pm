##
##  Module to save/restore scheduling information
##
package SaveRestore;

require Exporter;
@ISA = qw( Exporter);
@EXPORT = qw( readVolunteers readSlots readSchedule removeSlot removeVolunteer saveVolunteer saveSlot saveSchedule);

use warnings;
use strict;
use DBI;


my $dbh;
my $verbose = 1;


sub saveSchedule(@);
sub readSlots();
sub readVolunteers();
sub removeSlot($);
sub saveSlot($);
sub saveVolunteer($);

#------------------------------------------------------------------------------
#  BEGIN
#  		Make sure that we have a DB with appropriate tables ready to go
#------------------------------------------------------------------------------
BEGIN
{
	if ( !defined( $dbh))
	{
		$dbh = DBI->connect( "dbi:SQLite:./schedule.db", "", "") or die "Sorry, couldn't open schedule database!\n";
		$dbh->{sqlite_unicode} = 1;
	}

	##
	##  Create Schedule table
	##
	$dbh->do( "create table if not exists schedule
		           ( date text,
				     time text,
					 title text,
					 name text)");

	$dbh->do( "create index if not exists schedule_index on schedule ( date, name)");

	##
	##  Create Volunteer table
	##
	$dbh->do( "create table if not exists volunteer
		           ( name text,
				     email text,
					 phone text,
					 desiredRoles text,
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
	my $positions = $dbh->selectall_arrayref( "select * from position", {Slice=>{}});
	return( @$positions);
}

#------------------------------------------------------------------------------
#  sub readVolunteers()
#------------------------------------------------------------------------------
sub readVolunteers()
{
	my $volunteers = $dbh->selectall_arrayref( "select * from volunteer", {Slice=>{}});

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
#		This routine saves the information in the provide "volunteer" hashref to the "position" table.
#------------------------------------------------------------------------------
sub saveVolunteer($)
{
	my $volunteer = $_[0];

	##
	##  First, update the volunteer table
	##
	my $sth = $dbh->prepare( "insert or replace into volunteer (name, email, phone, desiredRoles) values (?,?,?,?)");
	$sth->bind_param( 1, $volunteer->{name});
	$sth->bind_param( 2, $volunteer->{email});
	$sth->bind_param( 3, $volunteer->{phone});
	$sth->bind_param( 4, $volunteer->{desiredRoles});
	$sth->execute();

	##
	##  Store desired dates, if any
	##
	if ( defined( $volunteer->{daysDesired}))
	{
		my $desired = $dbh->prepare( "insert or replace into dates_desired (name, date) values (?,?)");
		my @dates = split( /,/, $volunteer->{daysDesired});
		foreach my $date (@dates)
		{
			$desired->bind_param( 1, $volunteer->{name});
			$desired->bind_param( 2, $date);
			$desired->execute();
		}
	}

	##
	##  Store unavailable dates, if any
	##
	if ( defined( $volunteer->{daysUnavailable}))
	{
		my $unavailable = $dbh->prepare( "insert or replace into dates_unavailable (name, date) values (?,?)");
		my @dates = split( /,/, $volunteer->{daysDesired});
		foreach my $date (@dates)
		{
			$unavailable->bind_param( 1, $volunteer->{name});
			$unavailable->bind_param( 2, $date);
			$unavailable->execute();
		}
	}
	
}


#------------------------------------------------------------------------------
#  sub saveSchedule( @Schedule)
#  		This routine saves the currently generated schedule
#------------------------------------------------------------------------------
sub saveSchedule(@)
{
	my @schedules = @_;
	my $sth = $dbh->prepare( "insert or replace into schedule (date. time, title, name) values (?,?,?,?)");

	foreach my $slot (@schedules)
	{
		$sth->bind_param( 1, $slot->{date});
		$sth->bind_param( 2, $slot->{time});
		$sth->bind_param( 3, $slot->{title});
		$sth->bind_param( 4, $slot->{name});
		$sth->execute();
	}
}
	


1;
