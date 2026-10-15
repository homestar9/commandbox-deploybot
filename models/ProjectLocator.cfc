/**
 * Finds the site project for a deploybot command.
 *
 * A command can run from the project root or one of its child folders. The nearest parent
 * folder with box.json is the project root. The search stops when it finds .git without
 * box.json. This rule prevents a command in an unrelated repository from using a project
 * above that repository.
 */
component singleton {

	/**
	 * Returns the project root with forward slashes and no final slash. It throws
	 * Deploybot.NoProject when no project is found.
	 *
	 * @startDir The first folder to check. This is usually the current folder.
	 */
	string function findRoot( required string startDir ){
		var current = normalise( arguments.startDir );

		while ( len( current ) ) {
			if ( fileExists( current & "/box.json" ) ) {
				return current;
			}
			if ( directoryExists( current & "/.git" ) ) {
				break;
			}
			var parent = reReplace( current, "[\/][^\/]*$", "" );
			if ( parent == current || !find( "/", parent ) ) {
				break;
			}
			current = parent;
		}

		throw(
			type    = "Deploybot.NoProject",
			message = "No box.json file was found in #arguments.startDir# or its parent folders. "
				& "Run this command inside the site's repository."
		);
	}

	/**
	 * Changes a path to forward slashes and removes its final slash.
	 *
	 * @path The path to clean.
	 */
	private string function normalise( required string path ){
		return reReplace( replace( arguments.path, "\", "/", "all" ), "/+$", "" );
	}
}
