/**
 * Checks where the env file lives on this computer. `env check`, `env push`, and `init` use it.
 *
 *  - A file that git tracks is an error. Its values are already in the repository history.
 *  - A file in a git repository that .gitignore does not cover is a warning. One `git add .`
 *    would commit it.
 *
 * It never reads the file. It prints the file name only.
 */
component extends="commandbox-deploybot.models.BaseService" {

	property name="gitInspector" inject="GitInspector@commandbox-deploybot";

	/**
	 * Checks the env file and prints what it finds. Returns { tracked, ignored, repository }.
	 *
	 * @config The loaded DeploybotConfig.
	 */
	struct function check( required any config ){
		var name   = arguments.config.envFile();
		var git    = variables.gitInspector.status( arguments.config.envPath() );
		var result = {
			tracked    : git.known && git.tracked,
			ignored    : git.known && git.ignored,
			repository : git.known && git.repository
		};

		if ( result.tracked ) {
			bad( "#name# is tracked by git. Its values are in the repository history." );
			bad( "  1. Remove it from git, but keep the file: git rm --cached #name#" );
			bad( "  2. Add it to .gitignore. box deploybot init does this." );
			bad( "  3. Change every secret in it. The old values stay in the history." );
		} else if ( result.repository && !result.ignored ) {
			warn( "#name# is not covered by .gitignore. Run box deploybot init, or add it to .gitignore." );
		}
		return result;
	}
}
