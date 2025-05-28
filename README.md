Scheduler
---------

Churches often have to schedule many volunteers each week to
assist in various tasks, such as greeters to welcome people at the
doors, scripture readers, or people to assist with communion.  This can
be a time-consuming chore, so I wrote Scheduler to help make things a
little easier for the pastor.  Scheduler allows you to do define the 
various tasks that need volunteers, and create a list of people who
would like to help out in those tasks.  Then, with the push of a button,
Scheduler can build a schedule that assigns roles to the volunteers.  

In addition to providing a printable schedule, it can also send personalized
schedules to each volunteer, using Gmail to send them by email, or optionally 
using Twilio to send the schedules as text messages.  Similarly, Schedule
can (either manually, or automatically) send out reminders to volunteers
each week to let them know that they are scheduled for a particular task
that week.  Scheduler runs as a web service, so that you or your volunteers
can access Scheduler from any location or device that provides a web browser.
It is written in Perl, and currently has been tested on PCs running on Windows and
Linux. In addition, it can run on a Raspberry Pi, which allows you to
set up a dedicated, web-based server that uses little power, takes up almost
no space, and runs 24-7 for about $50-$80 if you like.

Scheduler is completely free, and is provided under the GPL-3.0 License.
It is written and provided freely so that churches
can better spend there resources working to spread the word and help those in need.

If you would like to read more, you can go to [the website](https://potterprogrammer.github.io/Scheduler/)
which gives a bit more of a description of Scheduler, as well as instructions for how
to install it.  You can also read the [User's Manual](docs/Users%20Manual.pdf)
