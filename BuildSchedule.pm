##
##  Module to save/restore scheduling information
##
package SaveRestore;

require Exporter;
@ISA = qw( Exporter);
@EXPORT = qw( build);

use warnings;
use strict;

use lib "./";
use Date::Calc	qw( :all);
use DBI;
use SaveRestore;

my @Slots;
my @Schedule;
my @Volunteers;

my $verbose = 1;
my $scheduleIncomplete = 0;

my %DayOfWeek = ( 'Monday' => 1,
	              'Tuesday' => 2,
	              'Wednesday' => 3,
	              'Thursday' => 4,
	              'Friday' => 5,
				  'Saturday' => 6,
				  'Sunday' => 7
			 	);



sub buildScheduleForDates($$);
sub scheduleSlots($$);
sub scheduleUnavailables($$$);
sub scheduleAllAvailable($$$);
sub scheduleSomeone($$@);

##
##  Define the following structures:
##
##		Slot:  {title} => String naming the slot to be filled (e.g. "techBooth")
##			   {dayOfWeek} => {M,T,W,Th,F,S,Su}
##			   {time} => hh:mm
##			   {numberNeeded} => Int specifying number of volunteers to fill slot
##			   {filled} => 0|1
##			   {volunteers} => [name1, name2 ...]
##
##		@Slots: list of slots to be filled
##
##		Volunteer:  {name} => String naming volunteer
##					 {email} => email address of volunteer for verification/reminder
##					 {phone} => Phone to send text verification/reminder to
##					 {daysDesired} => [ date1, date2 ...] (where date = YYYY-MM-DD
##					 {daysUnavailable} => [ date1, date2 ...] (where date = YYYY-MM-DD
##					 {desiredRoles} => [ 'techBooth', 'greeter'...]
##					 {timesScheduled} => Int indicating how many times this person has been scheduled for this session
##
##		@Volunteers: list of volunteers
##
##		Schedule:	{date} => Date of the position
##					{time} => Time of the position
##					{title} => Title of the position being filled
##					{name} => Name of person filling position
##
##		@Schedule:	list of all scheduled tasks
##


#------------------------------------------------------------------------------
#  sub buildScheduleForDates($startDate, $endDate)
#  		This function reads a list of volunteers and slots to be filled and
#  		then generates a schedule for the provided dates. The schedule (whether
#  		incomplete or not) is stored in the database in the "schedule" table.
#  		If the schedule was built without problems, 0 is returned, otherwise 1
#  		is returned.
#------------------------------------------------------------------------------
sub buildScheduleForDates($$)
{
	my ( $startDate, $endDate) = @_;

	$scheduleIncomplete = 0;

	##
	##  Read a list of the slots to be filled
	##
	@Slots = readSlots();

	##
	##  Read a list of the volunteers
	##
	@Volunteers = readVolunteers();

	##
	##  Schedule the slots
	##
	scheduleSlots( $startDate, $endDate);

	##
	##  Log the results
	##
	@Schedule = sort { $a->{date} cmp $b->{date}} @Schedule;
	
	foreach (@Schedule)
	{
		print "$_->{date} $_->{title}:$_->{name}\n";
	}

	if ( $scheduleIncomplete)
	{
		print "\n\n*** NOT ALL SLOTS WERE FILLED!!! ***\n\n"
	}
	
	saveSchedule( @Schedule);
	
	return( $scheduleIncomplete);
}



#------------------------------------------------------------------------------
#  sub scheduleSlots( $startDate, $endDate)
#  		This routine fills slots with volunteers for the date range provided
#------------------------------------------------------------------------------
sub scheduleSlots($$)
{
	my ($startDate, $endDate) = @_;

	##
	##  Loop through the list of slots to fill
	##
	foreach my $slot ( @Slots)
	{
		##
		##  Get a list of people willing to volunteer for this task
		##
		my @names = findVolunteersForTask( $slot->{title});

		##
		##  Generate a list of dates for this task
		##
		my @dates = getDatesForTask( $slot->{dayOfWeek}, $startDate, $endDate);

		##
		##  Schedule any dates which are unavailable to some volunteers
		##
		my @scheduled = scheduleUnavailables( $slot, \@names, \@dates);

		##
		##  Schedule remaining dates
		##
		push( @scheduled , scheduleAllAvailable( $slot, \@names, \@dates));
		
		##
		##  Store results in final schedule
		##
		push( @Schedule, @scheduled);
	}
}


#------------------------------------------------------------------------------
#  sub findVolunteersForTask( $task)
#  		This routine looks through the list of volunteers to see which ones
#  		have expressed a desire to volunteer for the named task.  The routine
#  		returns an array of references to the volunteer hashes.
#------------------------------------------------------------------------------
sub findVolunteersForTask()
{
	my $task = shift( @_);
	my @names;

	if ( $verbose)
	{
		print "Looking for volunteers for the task of $task\n";
	}
	foreach my $volunteer ( @Volunteers)
	{
		if ( defined( $volunteer->{desiredRoles}) && 
			 length( $volunteer->{desiredRoles}) &&
			 $volunteer->{desiredRoles} =~ m/$task/)
		{
			if ( $verbose)
			{
				print "$volunteer->{name} has volunteered for $task\n";
			}
			push( @names, $volunteer);
		}
	}

	return @names;
}

#------------------------------------------------------------------------------
#  sub getDatesForTask( $slot->{dayOfWeek}, $startDate, $endDate);       
#		This routine generates a list of dates when the given slot will occur
#		between the (inclusive) dates of $startDate and $endDate and returns
#		them as a list of entries in the form "YYYY-MM-DD".
#------------------------------------------------------------------------------
sub getDatesForTask()
{
	my ( $dayOfWeek, $startDate, $endDate) = @_;
	my @dates;

	my ( $startYear, $startMonth, $startDay) = split( /-/, $startDate);
	my ( $endYear, $endMonth, $endDay) = split( /-/, $endDate);

	##
	##  Get first "$dayOfWeek" in the starting month
	##
	if ( $verbose)
	{
		print "Calling: Nth_Weekday_of_Month_Year( $startYear, $startMonth, $DayOfWeek{$dayOfWeek}, 1);\n";
	}

	my ($year, $month, $day) = Nth_Weekday_of_Month_Year( $startYear, $startMonth, $DayOfWeek{$dayOfWeek}, 1);

	##
	##  Advance until we are at or past the start date
	##
	while( ( $year <= $startYear) &&
		   ( $month <= $startMonth) &&
		   ( $day <= $startDay))
	{
		($year, $month, $day) = Add_Delta_Days( $year, $month, $day, 7);
	}
	
	##
	##  Generate a list of desired dates
	##
	while( ( $year <= $endYear) &&
		   ( $month <= $endMonth) &&
		   ( $day <= $endDay))
	{
		push( @dates, sprintf( "%04d-%02d-%02d", $year, $month, $day));
		($year, $month, $day) = Add_Delta_Days( $year, $month, $day, 7);
	}

	if ( $verbose)
	{
		print "Found these ${dayOfWeek}'s between $startDate and $endDate:\n\t";
		print join( "\n\t", @dates) . "\n";
	}

	return @dates;
}

#------------------------------------------------------------------------------
#  sub scheduleUnavailables( $slot, \@names, \@dates)
#  		This routine looks for dates in the list where one or more of the names 
#  		is unavailable.  Other names are used to schedule those dates and then
#  		the "unavailable" names are moved up on the list so that they are more
#  		likely chosen next time.  The call returns a list of scheduled dates.
#------------------------------------------------------------------------------
sub scheduleUnavailables( $$$)
{
	my ( $slot, $names, $dates) = @_;
	my @scheduled;
	my @datesUnfilled;

	##
	##  Look through the list of dates, looking for
	##  dates where someone is unavailable
	##
	foreach my $date (@$dates)
	{
		##
		##  See if there is anyone unavailable
		##
		my $hasUnavailables = 0;
		my @available;
		my @unavailable;

		foreach my $name (@{$names})
		{
			##
			##  Is this person unavailable?
			##
			if (  defined( $name->{daysUnavailable}) &&
				  length( $name->{daysUnavailable}) && 
				  $name->{daysUnavailable} =~ m/$date/ )
			{
				##
				##  If so, add their name to the "unavailable" list
				##
				if ( $verbose)
				{
					print "$name->{name} is unavailable on $date\n";
				}
				$hasUnavailables = 1;
				push( @unavailable, $name);
			}
			else
			{
				##
				##  If not, add them to the "available" list
				##
				push( @available, $name);
			}
		}
		
		##
		##  Was someone unavailable?
		##
		if ( $hasUnavailables)
		{
			##
			##  Schedule one of the availables for this slot
			##
			push( @scheduled, scheduleSomeone( $slot, $date, @available));
		}
		else
		{
			push( @datesUnfilled, $date);
		}

		##
		##  Rebuild the names list with the unavailables moved to the top
		##
		@{$names} = @unavailable;
		push( @{$names}, @available);
	}

	##
	##  Clear dates which were filled for this slot
	##
	@$dates = @datesUnfilled;

	return @scheduled;
}

#------------------------------------------------------------------------------
#  sub scheduleSomeone( $slot, $date, @names)
#------------------------------------------------------------------------------
sub scheduleSomeone( $$@)
{
	my ( $slot, $date, @names) = @_;
	my @slotSchedule;
	
	##
	##  Was someone provided for the slot?
	##
	if ( !@names)
	{
		print "\n\n No one available for $slot->{title} on $date!!\n\n\n\a";
		my %schedule;
		$schedule{date} = $date;
		$schedule{time} = $slot->{time};
		$schedule{title} = $slot->{title};
		$schedule{name} = "n/a";
		push( @slotSchedule, \%schedule);

		$scheduleIncomplete = 1;
	}
	else
	{
		##
		##  Sort the names provide based on how often they've been scheduled already
		##
		@names = sort { $a->{timesScheduled} <=> $b->{timesScheduled}} @names;

		##
		##  Add the person at the top of the list to the schedule
		##
		my %schedule;
		$schedule{date} = $date;
		$schedule{time} = $slot->{time};
		$schedule{title} = $slot->{title};
		$schedule{name} = $names[0]->{name};
		push( @slotSchedule, \%schedule);

		if ( $verbose)
		{
			print "Scheduled $names[0]->{name} for $slot->{title} on $date\n";
		}

		##
		##  Make note that this person was scheduled for a task
		##
		$names[0]->{timesScheduled}++;

		##
		##  Mark the person as unavailable for this date (to prevent schduling two separate tasks on the same date)
		##
		$names[0]->{daysUnavailable} .= ",$date";
	}
	
	return @slotSchedule;
}


#------------------------------------------------------------------------------
#  sub scheduleAllAvailable( $slot, \@names, \@dates)
#  		This routine schedules all provided
#------------------------------------------------------------------------------
sub scheduleAllAvailable($$$)
{
	my ( $slot, $names, $dates) = @_;
	my @scheduled;

	##
	##  Look through the list of dates, looking for
	##  dates where someone is unavailable
	##
	foreach my $date (@$dates)
	{
		if ( $verbose)
		{
			print "Scheduling someone for $slot->{title} on $date\n";
		}
		push( @scheduled, scheduleSomeone( $slot, $date, @$names));
	}

	return @scheduled;
}
	
1;

