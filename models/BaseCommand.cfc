/**
 * Provides the shared setup and error handling for each `deploybot` command.
 *
 * It finds the project, loads its DeployBot settings, and starts the requested model component.
 * It also converts expected model exceptions into command errors.
 *
 * CommandBox keeps command components between runs. The component stores only the injected
 * project locator. Each command run creates a new DeploybotConfig.
 */
component {

	property name="locator" inject="ProjectLocator@commandbox-deploybot";

	/**
	 * Finds the project root, loads its DeployBot settings, and returns them.
	 */
	any function loadConfig(){
		return guard( function(){
			var root = variables.locator.findRoot( getCWD() );
			return getInstance( "DeploybotConfig@commandbox-deploybot" ).load( root );
		} );
	}

	/**
	 * Creates a model component that uses this command's print buffer.
	 *
	 * @name The component name, such as "EnvPusher".
	 */
	any function service( required string name ){
		return getInstance( arguments.name & "@commandbox-deploybot" ).usePrinter( print );
	}

	/**
	 * Runs a function and reports an expected DeployBot error without a stack trace.
	 * It throws unexpected exceptions again so CommandBox can show the full stack trace.
	 *
	 * @work The function to run.
	 */
	any function guard( required any work ){
		try {
			return arguments.work();
		} catch ( any exception ) {
			if ( isStop( exception ) ) {
				return error( exception.message );
			}
			rethrow;
		}
	}

	/**
	 * Returns true for an expected DeployBot error or a failed command called from this command.
	 * The error already has a message for the user.
	 *
	 * @exception The caught exception.
	 */
	private boolean function isStop( required any exception ){
		var type = arguments.exception.type ?: "";
		return left( type, 10 ) == "Deploybot." || type == "commandException";
	}
}
