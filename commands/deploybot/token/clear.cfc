/**
 * Removes the saved env token for the current site.
 * .
 * Run this command inside the site's repository. It reads the DeployBot URL and site slug from
 * the "deploybot" block in box.json.
 * .
 * {code:bash}
 * deploybot token clear
 * {code}
 */
component extends="commandbox-deploybot.models.BaseCommand" {

	function run(){
		var config = loadConfig();
		guard( function(){
			var removed = getInstance( "TokenStore@commandbox-deploybot" ).clear( config.host(), config.site() );
			if ( removed ) {
				print.greenLine( "Token removed for #config.site()# on #config.host()#." ).toConsole();
			} else {
				print.line( "No token was saved for #config.site()# on #config.host()#." ).toConsole();
			}
		} );
	}
}
