/**
 * Pushes the site's env file to DeployBot.
 * .
 * First it checks the key names against .env.example on this computer. Then it asks DeployBot
 * for a dry run and prints the key names that would be added, removed, or changed. After you
 * confirm, it pushes for real. DeployBot validates, backs up, writes, and protects the file,
 * reinitializes the site, and checks its health. It rolls back if that fails. This command
 * prints each step and the record URL. It exits with an error if any step fails.
 * .
 * The command never prints the file's values or the token.
 * .
 * {code:bash}
 * deploybot env push
 * deploybot env push --dryRun
 * deploybot env push --yes
 * deploybot env push --force
 * {code}
 */
component extends="commandbox-deploybot.models.BaseCommand" {

	/**
	 * @force  Pushes even if keys from .env.example are missing from the env file.
	 * @yes    Skips the confirmation question.
	 * @dryRun Shows the diff from the server and stops. Nothing changes on the server.
	 */
	function run(
		boolean force  = false,
		boolean yes    = false,
		boolean dryRun = false
	){
		var config = loadConfig();
		var args   = arguments;
		guard( function(){
			service( "EnvPusher" ).run(
				config  = config,
				force   = args.force,
				yes     = args.yes,
				dryRun  = args.dryRun,
				confirm = function( required string question ){
					return confirm( question );
				}
			);
		} );
	}
}
