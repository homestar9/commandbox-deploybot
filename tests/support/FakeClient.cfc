/**
 * A stand-in for DeploybotClient. It returns queued responses and records each call, so specs
 * never touch the network.
 */
component {

	function init(){
		variables.queue    = [];
		variables.recorded = [];
		return this;
	}

	/**
	 * Queues a response. A struct is returned as the response. A string is thrown as the type of
	 * a Deploybot exception, such as "Deploybot.Timeout".
	 *
	 * @response The response struct, or an exception type.
	 */
	function respond( required any response ){
		variables.queue.append( arguments.response );
		return this;
	}

	/** Returns the recorded calls, oldest first. */
	array function calls(){
		return variables.recorded;
	}

	/** Records the call and returns the next queued response. */
	struct function pushEnv(
		required string url,
		required string site,
		required string token,
		required any body,
		boolean dryRun = false,
		boolean force  = false
	){
		variables.recorded.append( {
			url    : arguments.url,
			site   : arguments.site,
			token  : arguments.token,
			bytes  : arrayLen( arguments.body ),
			dryRun : arguments.dryRun,
			force  : arguments.force
		} );
		if ( !variables.queue.len() ) {
			throw( type = "Spec.NoResponse", message = "FakeClient has no queued response." );
		}
		var next = variables.queue[ 1 ];
		variables.queue.deleteAt( 1 );
		if ( isSimpleValue( next ) ) {
			throw( type = next, message = "Thrown by FakeClient." );
		}
		return next;
	}
}
