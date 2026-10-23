/**
 * Sets up the current site for DeployBot.
 * .
 * Run this command in the site's repository. It asks for the DeployBot URL and the site slug.
 * Then it writes the "deploybot" block in box.json, adds the env file to .gitignore, and creates
 * the env file from .env.example with blank values. Last, it offers to save the env token.
 * .
 * Run it again to change the settings. It never overwrites an existing env file.
 * .
 * {code:bash}
 * deploybot init
 * deploybot init url=https://deploybot.example.com site=my-site
 * deploybot init envFile=config/.env.production
 * {code}
 */
component extends="commandbox-deploybot.models.BaseCommand" {

	/**
	 * @url     The DeployBot URL, such as https://deploybot.example.com. Asked when empty.
	 * @site    The site's slug in DeployBot. Asked when empty.
	 * @envFile The env file to push, relative to the repository. The default is .env.production.
	 */
	function run(
		string url     = "",
		string site    = "",
		string envFile = ""
	){
		var root     = guard( function(){
			return variables.locator.findRoot( getCWD() );
		} );
		var setup    = service( "SiteSetup" );
		var defaults = guard( function(){
			return setup.defaults( root );
		} );

		var answers = {
			url     : len( trim( arguments.url ) ) ? arguments.url : ask( message = "DeployBot URL: ", defaultResponse = defaults.url ),
			site    : len( trim( arguments.site ) ) ? arguments.site : ask( message = "Site slug in DeployBot: ", defaultResponse = defaults.site ),
			envFile : len( trim( arguments.envFile ) ) ? arguments.envFile : defaults.envFile
		};
		var result = guard( function(){
			return setup.run( root = root, url = answers.url, site = answers.site, envFile = answers.envFile );
		} );
		var config = result.config;

		if ( result.tokenSaved ) {
			print.line( "A token is already saved for #config.site()# on #config.host()#." ).toConsole();
		} else if ( confirm( "Save the env token now? Get it on the site page in DeployBot (""Generate / rotate env token""). [y/n] " ) ) {
			var token = ask( message = "Env token for #config.site()# on #config.host()#: ", mask = "*" );
			guard( function(){
				getInstance( "TokenStore@commandbox-deploybot" ).set( config.host(), config.site(), token );
				print.greenLine( "Token saved for #config.site()# on #config.host()#." ).toConsole();
			} );
		} else {
			print.line( "Save the token later with: box deploybot token set" ).toConsole();
		}
		setup.printNextSteps( config );
	}
}
