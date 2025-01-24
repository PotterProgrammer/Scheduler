##
##  Module to save/restore scheduling information
##
package BuildSchedule;

require Exporter;
@ISA = qw( Exporter);
@EXPORT = qw( buildScheduleForDates );

use warnings;
use strict;

use lib "./";
use Date::Calc	qw( :all);
use DBI;
use List::Util qw( shuffle);
use SaveRestore;
use open qw(:std :utf8);
use utf8;
use utf8::all;

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
	@Schedule = ();

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
	
	clearSavedSchedule( $startDate, $endDate);
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
	my %volunteerCount;

	##
	##  Sort the slots based on the number of volunteers.  (Slots with fewer
	##	volunteers get filled first to make sure those volunteers aren't chosen
	##	elsewhere first.)
	##
	@Slots = sort { ( int( findVolunteersForTask( $a->{title})) - $a->{numberNeeded})  <=> 
	                ( int( findVolunteersForTask( $b->{title})) - $b->{numberNeeded}) } @Slots;
	
	##
	## 	Reset volunteer counts for this period
	##
	foreach my $person ( @Volunteers)
	{
		$volunteerCount{ $person->{name}} = 0;
	}

	##
	##  Loop through the list of slots to fill
	##
	foreach my $slot ( @Slots)
	{
		##
		##  Generate a list of dates for this task
		##
		my @dates = getDatesForTask( $slot->{dayOfWeek}, $startDate, $endDate);

		##
		##  Assign volunteers for each date for this slot
		##
		foreach  my $date ( @dates)
		{
			if ( $verbose)
			{
				print "Scheduling " . $slot->{title} . " for $date\n";
			}

			##
			##  Get a list of people willing to volunteer for this task
			##
			my @names = findVolunteersForTask( $slot->{title});
			
			##
			##  Shuffle the names so that the same people don't get picked every time
			##
			@names = shuffle( @names);

			##
			##  Remove names which are unavailable on this date
			##
			@names = removeUnavailables( $date, @names);

			##
			##  Sort the remaining names based on how often they've volunteered thus far
			##
			@names = orderByCount( \%volunteerCount, @names);

			##
			##  Did anyone volunteer specifically for this date?
			##
			@names = orderBySpecialRequest( $date, @names);

			##
			##  Schedule volunteers for this slot
			##
			my @scheduled = fillSlot( $slot, $date, \%volunteerCount, @names);
			
			##
			##  Store results in final schedule
			##
			if ( @scheduled)
			{
				push( @Schedule, @scheduled);
			}
		}
		
	}
}


#------------------------------------------------------------------------------
#  sub orderByCount( \%volunteerCount, @names)
#  		This function sorts the list of names placing those who have
#  		volunteered most at the end of the list and returns the new list.  (The
#  		original list is untouched.)
#------------------------------------------------------------------------------
sub orderByCount($@)
{
	my ($volunteerCount, @names) = @_;
	
	##
	##  Sort the names provide based on how often they've been scheduled already
	##
	@names = sort { $volunteerCount->{$a->{name}} <=> $volunteerCount->{$b->{name}}} @names;

	return @names;
}

#------------------------------------------------------------------------------
#  sub orderBySpecialRequest( $date, @names)
#  		This function sorts the list of names placing those who have
#  		requested to serve on this date at the head of the list.  (The
#  		original list is untouched.)
#------------------------------------------------------------------------------
sub orderBySpecialRequest( $@)
{
	my ($date, @names) = @_;
	my @sortedList;
	
	##
	##  Loop through the list of names
	##
	foreach my $name (@names)
	{
		##
		##  Did this person ask to work on this date?
		##
		if (  defined( $name->{daysDesired}) &&
			  length( $name->{daysDesired}) && 
			  $name->{daysDesired} =~ m/$date/ )
		{
			##
			##  If so, put them at the front of the list
			##
			unshift( @sortedList, $name);
	
print "\n\n ***********  Moving $name->{name} to the front of the list!!\n";
		}
		else
		{
			##
			##  If not, add them to the list in the same order
			##
			push( @sortedList, $name);
		}
	}
	return @sortedList;
}

#------------------------------------------------------------------------------
#  sub removeUnavailables( $date, @names)
#  		This function looks through the list of names and generates a list of
#  		all names that are available on the given date.
#------------------------------------------------------------------------------
sub removeUnavailables( $@)
{
	my ( $date, @names) = @_;
	my @availables;

	foreach my $name (@names)
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
		}
		else
		{
			push( @availables, $name);
		}
	}

	return @availables;
}

#------------------------------------------------------------------------------
#  sub fillSlot( $slot, $date, \%volunteerCount, @names)
#  		This function attempts to fill all needed openings in this slot using
#  		the list of names provided.  Volunteers who are scheduled have their
#  		volunteerCount incremented and have the current date added
#  		(temporarily) to their "dates unavailable" list to prevent double
#  		booking.
#------------------------------------------------------------------------------
sub fillSlot( $$$@)
{
	my ( $slot, $date, $volunteerCount, @names) = @_;
	my @slotSchedule;
	
	##
	##  Schedule each person needed for this slot
	##
	for( my $count = 0; $count < $slot->{numberNeeded}; $count++)
	{
		##
		##  Is anyone available?
		##
		if ( @names)
		{
			##
			##  If so, schedule the next person in line
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
			$volunteerCount->{$names[0]->{name}}++;

			##
			##  Mark the person as unavailable for this date (to prevent schduling two separate tasks on the same date)
			##
			$names[0]->{daysUnavailable} .= ",$date";

			shift( @names);
		}
		else
		{
			print "\n\n No one available for $slot->{title} on $date!!\n\n\n\a";
			my %schedule;
			$schedule{date} = $date;
			$schedule{time} = $slot->{time};
			$schedule{title} = $slot->{title};
			$schedule{name} = "—unfilled—";
			push( @slotSchedule, \%schedule);

			$scheduleIncomplete = 1;
		}
	}
	
	return @slotSchedule;
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

	if ( $verbose)
	{
		print "Found $year-$month-$day as the first Sunday of the starting month\n";
	}

	my $startYMD = ($startYear * 10000) + ($startMonth * 100) + $startDay;
	my $endYMD = ($endYear * 10000) + ($endMonth * 100) + $endDay;

	##
	##  Advance until we are at or past the start date
	##
	while( (( $year * 10000) + ($month * 100) + $day) < $startYMD)
	{
		($year, $month, $day) = Add_Delta_Days( $year, $month, $day, 7);
	}

	if ( $verbose)
	{
		print "Found $year-$month-$day as the first Sunday for the schedule\n";
	}
	
	##
	##  Generate a list of desired dates
	##
	while( (( $year * 10000) + ($month * 100) + $day) <= $endYMD)
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
		$schedule{name} = "—unfilled—";
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

