/**
 * Pushes the site's env file to DeployBot.
 * .
 * First it checks the key names against .env.example on this computer. Then it asks DeployBot
 * for a dry run and prints the key names that would be added, removed, or changed. After you
 * confirm, it pushes for real. DeployBot validates, backs up, writes, and protects the file,
 * reinitializes the site, and checks its health. It rolls back if that fails. This command
 * prints each step and the record URL. It exits with an error if any step fails.
 * .
 * It also exits with an error if you answer no, or if the terminal cannot answer the question,
 * such as in CI or a release hook. Use --yes in scripts.
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
		// Without a confirm function the push stops before asking. CommandBox's check covers
		// closed or piped input and output, the CI variable, and its nonInteractiveShell setting.
		var confirmer = "";
		if ( shell.isTerminalInteractive() ) {
			confirmer = function( required string question ){
				return confirm( question );
			};
		}
		guard( function(){
			try {
				service( "EnvPusher" ).run(
					config  = config,
					force   = args.force,
					yes     = args.yes,
					dryRun  = args.dryRun,
					confirm = confirmer
				);
			} catch ( Deploybot.Cancelled exception ) {
				// A "no" is a choice, not a failure: a yellow line, but still a failing exit code.
				print.yellowLine( exception.message ).toConsole();
				setExitCode( 1 );
			}
		} );
	}
}
