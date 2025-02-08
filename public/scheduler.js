//
//  Javascript routines common to all pages
//

//-->import {Dialog} from './Dialog.js';

//==============================================================================
//  function loadNavbar()
//==============================================================================
function loadNavbar()
{
    fetch('/navBar.html')
       .then(response => response.text())
       .then(data => {
            document.getElementById('navbar').innerHTML = data;
        });
}

//==============================================================================
//  function showVolunteerInfo()
//==============================================================================
function showVolunteerInfo()
{
	//
	//  Call server to get info for the current position
	//
	var volunteerList = document.getElementById( "itemList");

	if ( volunteerList != null)
	{
		var selectedItemNumber = volunteerList.selectedIndex;
		var itemName = volunteerList.options[selectedItemNumber].value;
		var url = 'ws://' + window.location.host + '/getVolunteerInfo';
		var ws;

		if ( window.location.protocol == 'https:')
		{
			url = 'wss://' + window.location.host + '/getVolunteerInfo';
		}

		ws = new WebSocket( url);
		var msg = JSON.stringify( { "index" :selectedItemNumber, "name": itemName});

		ws.onopen = (event) => 
		{
			ws.send( msg);
		};

		ws.onerror = (event) =>
		{
			ws.close();
			ws = new WebSocket( url);
			ws.onopen = (event) => 
			{
				ws.send( msg);
			};
		};

		ws.onmessage = (msg) =>
		{
			var reply = JSON.parse( msg.data);
			document.getElementById('name').value = reply.name;
			document.getElementById('email').value = reply.email;
			document.getElementById('phone').value = reply.phone;

			//
			//  Set the preferred contact
			//
			var contactMethod = document.getElementById( 'contactMethod');
			while( contactMethod.options.length > 0)
			{
				contactMethod.remove(0);
			}

			var contactOption = document.createElement('option');
			var contactText = document.createTextNode( reply.contact);
			contactOption.appendChild( contactText);
			contactOption.setAttribute( "value", reply.contact);
			contactMethod.appendChild( contactOption);

			//
			//  Clear current positions listed
			//
			var positions = document.getElementById('positions');
			while( positions.options.length > 0)
			{
				positions.remove(0);
			}

			var list = reply.desiredRoles.split( ",");

			list.forEach( (role) => 
				{
					var pos = document.createElement('option');
					var posText = document.createTextNode( role);
					pos.appendChild( posText);
					pos.setAttribute( "value", role);
					positions.appendChild( pos);
				});
			positions.size = Math.min( 3, positions.length);
			
			//
			//  Clear current days unavailable listed
			//
			var dayListLabel = document.getElementById('daysUnavailableLabel');
			dayListLabel.title = 'Days that ' + reply.name + ' will be unvailable to serve.';
			var dayList = document.getElementById('daysUnavailable');
			dayList.title = 'Days that ' + reply.name + ' will be unavailable to serve.';
			while( dayList.options.length > 0)
			{
				dayList.remove(0);
			}

			//
			//  Set days unavailable
			//
			if ( reply.daysUnavailable != null)
			{
				list = reply.daysUnavailable.split( ",");

				list.forEach( (date) => 
					{
						var pos = document.createElement('option');
						var posText = document.createTextNode( date);
						pos.appendChild( posText);
						pos.setAttribute( "value", date);
						dayList.appendChild( pos);
					});
				dayList.style.width = "7em";
			}
			else
			{
				var pos = document.createElement('option');
				var posText = document.createTextNode( '-none-');
				pos.appendChild( posText);
				pos.setAttribute( "value", "-none-");
				dayList.appendChild( pos);
				dayList.style.width = "6.5em";
			}
			dayList.size = Math.min( 3, dayList.length);


			//
			//  Clear current days desired listed
			//
			dayListLabel = document.getElementById('daysDesiredLabel');
			dayListLabel.title = 'Days that ' + reply.name + ' specifically asked to be chosen.';
			dayList = document.getElementById('daysDesired');
			dayList.title = 'Days that ' + reply.name + ' specifically asked to be chosen.';
			while( dayList.options.length > 0)
			{
				dayList.remove(0);
			}

			//
			//  Set days desired
			//
			if ( reply.daysDesired != null)
			{
				list = reply.daysDesired.split( ",");

				list.forEach( (date) => 
					{
						var pos = document.createElement('option');
						var posText = document.createTextNode( date);
						pos.appendChild( posText);
						pos.setAttribute( "value", date);
						dayList.appendChild( pos);
					});
				dayList.style.width = "6.5em";
			}
			else
			{
				var pos = document.createElement('option');
				var posText = document.createTextNode( '-none-');
				pos.appendChild( posText);
				pos.setAttribute( "value", "-none-");
				dayList.appendChild( pos);
				dayList.style.width = "4em";
			}
			dayList.size = Math.min( 3, dayList.length);

			ws.close();
		};
	}
}

//==============================================================================
//  function saveVolunteerInfo( volunteer, callback)
//		This function saves information about the provided volunteer to the
//		database.
//==============================================================================
function saveVolunteerInfo( volunteer, callback)
{
	//
	//  Call server to get info for the current position
	//
	var ws;
	var url = 'ws://' + window.location.host + '/saveVolunteerInfo';
	if ( window.location.protocol == 'https:')
	{
		url = 'wss://' + window.location.host + '/saveVolunteerInfo';
	}

	ws = new WebSocket( url);
	var msg = JSON.stringify( volunteer);

	ws.onopen = (event) => 
	{
		ws.send( msg);
	};

	ws.onerror = (event) =>
	{
		ws.close();
		ws = new WebSocket( url);
		ws.onopen = (event) => 
		{
			ws.send( msg);
		};
	};

	ws.onmessage = (msg) =>
	{
		var reply = JSON.parse( msg.data);
		if ( reply.status == "OK")
		{
//-->			alert( volunteer.name + " was added to the list of volunteers");
			showAddedAlert( true);
			callback();
		}
		else
		{
			Dialog.Alert( {title: 'WARNING!', text: "A problem arose trying to add " + volunteer.name + " to the list!!"});
		}
		ws.close();
	};
}

//==============================================================================
//  function showAddedAlert( hideBackground)
//		This function shows the "Added" message on the screen for 1 second
//==============================================================================
function showAddedAlert( hideBackground)
{
	document.getElementById('added').hidden = false;

	if ( hideBackground == true)
	{
		document.getElementById('overlay').hidden = false;
		setTimeout( function(){document.getElementById('overlay').hidden = true;document.getElementById('added').hidden = true;}, 1000);
	}
	else
	{
		setTimeout( function(){document.getElementById('added').hidden = true;}, 1000);
	}
}

//==============================================================================
//  function showHelp()
//		This function opens a window with the user's manual
//==============================================================================
function showHelp()
{
	window.open( "/usermanual.pdf");
}


//==============================================================================
//	function hideEditDates()
//		This method hides the overlay panel and the save dates
//==============================================================================
function hideEditDates()
{
	document.getElementById('overlay').hidden = true;
	document.getElementById('dateEdit').hidden = true;
}

//==============================================================================
//	function showEditDates()
//		This method shows the overlay panel
//==============================================================================
function showEditDates()
{
	document.getElementById('overlay').hidden = false;
	document.getElementById('dateEdit').hidden = false;
}

//==============================================================================
//	function hideEditSchedule()
//		This method hides the overlay panel and the edit schedule dialog.
//==============================================================================
function hideEditSchedule()
{
	document.getElementById('overlay').hidden = true;
	document.getElementById('editSchedule').hidden = true;
}

//==============================================================================
//	function showEditSchedule()
//		This method shows the overlay panel and the edit scheudle dialog
//==============================================================================
function showEditSchedule()
{
	document.getElementById('overlay').hidden = false;
	document.getElementById('editSchedule').hidden = false;
}


//==============================================================================
//	function hideConfirmSave()
//		This method hides the overlay panel and the save dialog
//==============================================================================
function hideConfirmSave()
{
	document.getElementById('overlay').hidden = true;
	document.getElementById('confirmSave').hidden = true;
}

//==============================================================================
//	function showConfirmSave()
//		This method shows the overlay panel and the save dialog
//==============================================================================
function showConfirmSave()
{
	document.getElementById('overlay').hidden = false;
	document.getElementById('confirmSave').hidden = false;
}

//==============================================================================
//	function hideConfirmDelete()
//		This method hides the overlay panel and the delete dialog
//==============================================================================
function hideConfirmDelete()
{
	document.getElementById('overlay').hidden = true;
	document.getElementById('confirmDelete').hidden = true;
}

//==============================================================================
//	function showConfirmDelete()
//		This method shows the overlay panel and the delete dialog
//==============================================================================
function showConfirmDelete()
{
	var itemList = document.getElementById( "itemList");
	var selectedItem = itemList.value;
	var position = document.getElementById( "itemToDelete");
	position.innerText = selectedItem;
	document.getElementById('overlay').hidden = false;
	document.getElementById('confirmDelete').hidden = false;
}


//==============================================================================
//  function hideNavbar()
//  	This method hides the menu bar 
//==============================================================================
function hideNavbar()
{
	document.getElementById('navbar').hidden = true;
}

window.addEventListener( "pageshow", loadNavbar);
//-->export { loadNavbar,showVolunteerInfo,saveVolunteerInfo,showAddedAlert,showHelp,hideEditDates,showEditDates,hideEditSchedule,showEditSchedule,hideConfirmSave,showConfirmSave,hideConfirmDelete,showConfirmDelete,hideNavbar}
