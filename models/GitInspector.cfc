/**
 * Asks git whether a file is tracked or ignored. This is the only component that starts a
 * process, so specs stub it.
 *
 * It runs `git ls-files --error-unmatch` and `git check-ignore -q` in the file's own folder, so a
 * file outside any repository is reported as such. When git is not installed or does not answer
 * in time, the result says so. A caller then skips the git checks instead of failing.
 *
 * It never reads the file. Git output is discarded.
 */
component singleton {

	/** The number of seconds to wait for each git command. */
	variables.timeoutSeconds = 15;

	/**
	 * Returns { known, repository, tracked, ignored } for a file. known is false when git could
	 * not be run. repository is false when the file's folder is not inside a git repository.
	 *
	 * @path The full path to the file. The file does not have to exist.
	 */
	struct function status( required string path ){
		var folder = getDirectoryFromPath( arguments.path );
		var name   = getFileFromPath( arguments.path );
		var result = { known : false, repository : false, tracked : false, ignored : false };
		if ( !directoryExists( folder ) ) {
			return result;
		}

		var tracked = run( folder, [ "ls-files", "--error-unmatch", "--", name ] );
		if ( tracked < 0 ) {
			return result;
		}
		result.known = true;
		// ls-files exits 1 for an untracked file and 128 outside a repository.
		if ( tracked > 1 ) {
			return result;
		}
		result.repository = true;
		result.tracked    = tracked == 0;
		result.ignored    = run( folder, [ "check-ignore", "-q", "--", name ] ) == 0;
		return result;
	}

	/**
	 * Runs git with the arguments in a folder and returns its exit code, or -1 when git could not
	 * be started or did not finish in time.
	 *
	 * @folder The working folder.
	 * @args   The git arguments, without "git".
	 */
	private numeric function run( required string folder, required array args ){
		var command = [ "git" ];
		command.append( arguments.args, true );
		try {
			var redirect = createObject( "java", "java.lang.ProcessBuilder$Redirect" );
			var builder  = createObject( "java", "java.lang.ProcessBuilder" ).init( javaCast( "string[]", command ) );
			builder.directory( createObject( "java", "java.io.File" ).init( arguments.folder ) );
			builder.redirectOutput( redirect.DISCARD );
			builder.redirectError( redirect.DISCARD );
			var process = builder.start();
			var seconds = createObject( "java", "java.util.concurrent.TimeUnit" ).SECONDS;
			if ( !process.waitFor( javaCast( "long", variables.timeoutSeconds ), seconds ) ) {
				process.destroyForcibly();
				return -1;
			}
			return process.exitValue();
		} catch ( any exception ) {
			return -1;
		}
	}
}
