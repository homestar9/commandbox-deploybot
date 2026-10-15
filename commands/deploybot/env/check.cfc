/**
 * Compares the key names in the site's env file with .env.example.
 * .
 * The check runs on this computer only. It makes no network request and never prints a value.
 * It reports keys that are missing from the env file (an error, exit code 1), extra keys (for
 * information), and keys with a blank value (a warning).
 * .
 * The env file is ".env.production" in the project root unless box.json sets deploybot.envFile.
 * .
 * {code:bash}
 * deploybot env check
 * {code}
 */
component extends="commandbox-deploybot.models.BaseCommand" {

	function run(){
		var config = loadConfig();
		guard( function(){
			service( "EnvChecker" ).run( config );
		} );
	}
}
