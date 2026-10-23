/**
 * Compares the key names in a site's env file with its .env.example.
 *
 * The check runs on this computer only. It never contacts a server and never prints a value.
 * Missing keys are errors, extra keys are information, and keys with a blank value are warnings.
 * It also checks where the env file lives (EnvSafety): a file that git tracks is an error.
 */
component extends="commandbox-deploybot.models.BaseService" {

	property name="envFile"   inject="EnvFile@commandbox-deploybot";
	property name="envSafety" inject="EnvSafety@commandbox-deploybot";

	/**
	 * Compares env text with example text and returns key names only.
	 * The result has three arrays: missing (in the example, not in the env), extra (in the env,
	 * not in the example), and blank (keys in the env whose value is blank).
	 *
	 * @envText     The env file text.
	 * @exampleText The .env.example text.
	 */
	struct function compareKeys( required string envText, required string exampleText ){
		var envKeys     = variables.envFile.keyNames( arguments.envText );
		var exampleKeys = variables.envFile.keyNames( arguments.exampleText );
		var result      = { missing : [], extra : [], blank : variables.envFile.blankKeys( arguments.envText ) };

		for ( var key in exampleKeys ) {
			if ( envKeys.find( key ) == 0 ) {
				result.missing.append( key );
			}
		}
		for ( var key in envKeys ) {
			if ( exampleKeys.find( key ) == 0 ) {
				result.extra.append( key );
			}
		}
		return result;
	}

	/**
	 * Reads the site's env file and .env.example, prints the comparison, and returns it.
	 * It throws Deploybot.EnvFile or Deploybot.NoExample when a file is missing. It does not
	 * throw for missing keys, so the caller decides what they mean.
	 *
	 * @config The loaded DeploybotConfig.
	 */
	struct function report( required any config ){
		var envText = variables.envFile.decode( variables.envFile.readBytes( arguments.config.envPath() ) );
		if ( !fileExists( arguments.config.examplePath() ) ) {
			throw(
				type    = "Deploybot.NoExample",
				message = ".env.example was not found at #arguments.config.examplePath()#. The local check compares the env file with it. Create it, or use --force to skip the check."
			);
		}
		var result = compareKeys( envText, fileRead( arguments.config.examplePath(), "utf-8" ) );
		printResult( arguments.config.envFile(), result );
		return result;
	}

	/**
	 * Checks where the env file lives (EnvSafety) and prints what it finds. Returns its result.
	 *
	 * @config The loaded DeploybotConfig.
	 */
	struct function safety( required any config ){
		return variables.envSafety.usePrinter( variables.print ).check( arguments.config );
	}

	/**
	 * Runs the local check for `deploybot env check`. It prints the comparison and throws
	 * Deploybot.EnvTracked when git tracks the env file, or Deploybot.MissingKeys when keys are
	 * missing.
	 *
	 * @config The loaded DeploybotConfig.
	 */
	struct function run( required any config ){
		if ( safety( arguments.config ).tracked ) {
			stop( "#arguments.config.envFile()# is tracked by git. Remove it from git and change its secrets.", "Deploybot.EnvTracked" );
		}
		var result = report( arguments.config );
		if ( result.missing.len() ) {
			stop( "#result.missing.len()# key#( result.missing.len() == 1 ? "" : "s" )# from .env.example #( result.missing.len() == 1 ? "is" : "are" )# missing in #arguments.config.envFile()#.", "Deploybot.MissingKeys" );
		}
		return result;
	}

	/**
	 * Prints the comparison. Only key names appear in the output.
	 *
	 * @fileName The env file name for the messages.
	 * @result   The result from compareKeys().
	 */
	private void function printResult( required string fileName, required struct result ){
		if ( arguments.result.missing.len() ) {
			bad( "Missing from #arguments.fileName# (in .env.example):" );
			for ( var key in arguments.result.missing ) {
				bad( "  - " & key );
			}
		}
		if ( arguments.result.extra.len() ) {
			say( "Extra in #arguments.fileName# (not in .env.example):" );
			for ( var key in arguments.result.extra ) {
				say( "  + " & key );
			}
		}
		if ( arguments.result.blank.len() ) {
			warn( "Blank value in #arguments.fileName#:" );
			for ( var key in arguments.result.blank ) {
				warn( "  ! " & key );
			}
		}
		if ( !arguments.result.missing.len() ) {
			good( "Local check passed: every key in .env.example is in #arguments.fileName#." );
		}
	}
}
