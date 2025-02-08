//-->export { Dialog};

class Dialog
{
	constructor()
	{
	}

	static #pushedYes( resolve)
	{
		resolve( true);
	}

	static #pushedNo( resolve)
	{
		resolve( false);
	}


	static async Confirm({title='Alert', text='Choose Yes or No'}={})
	{
		var me = this;
		var promise = new Promise( (resolve, reject)=>
			{
				this.dialogBox = document.createElement( "dialog");
				this.dialogBox.innerHTML = '<h2 id="dialogTitle">' + title + '</h2><p id="dialogText">' + text + '</p><div id="dialogButtonRow"><button class="dialogButton" id="yesButton">Yes</button><button class="dialogButton" id="noButton">No</button></div>';
				this.dialogBox.id="confirmDialog";
				this.result = null;
				document.body.appendChild( this.dialogBox);
				document.getElementById( "yesButton").onclick = function() {Dialog.#pushedYes( resolve);};
				document.getElementById( "noButton").onclick = function(){Dialog.#pushedNo( resolve);};
				this.dialogBox.showModal();
			});

		var result = await promise;
		this.dialogBox.close();
		this.dialogBox.remove();
		return result;
	}

	static async Alert({title='Alert', text='Please pay attention'}={})
	{
		var me = this;
		var promise = new Promise( (resolve, reject)=>
			{
				this.dialogBox = document.createElement( "dialog");
				this.dialogBox.innerHTML = '<h2 id="dialogTitle">' + title + '</h2><div id="dialogText">' + text + '</div><div id="dialogButtonRow"><button class="dialogButton" id="yesButton">Ok</button></div>';
				this.dialogBox.id="confirmDialog";
				this.result = null;
				document.body.appendChild( this.dialogBox);
				document.getElementById( "yesButton").onclick = function() {Dialog.#pushedYes( resolve);};
				this.dialogBox.showModal();
			});

		var result = await promise;
		this.dialogBox.close();
		this.dialogBox.remove();
		return result;
	}
}

