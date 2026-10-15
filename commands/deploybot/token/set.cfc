/**
 * Saves the env token for the current site.
 * .
 * Run this command inside the site's repository. It reads the DeployBot URL and site slug from
 * the "deploybot" block in box.json and asks for the token. The typed characters are hidden.
 * Copy the token from the site page in DeployBot ("Generate / rotate env token").
 * .
 * The token is saved in ~/.deploybot/tokens.json, not in the repository or the CommandBox config.
 * .
 * {code:bash}
 * deploybot token set
 * {code}
 */
component extends="commandbox-deploybot.models.BaseCommand" {

	function run(){
		var config = loadConfig();
		var token  = ask( message = "Env token for #config.site()# on #config.host()#: ", mask = "*" );
		guard( function(){
			getInstance( "TokenStore@commandbox-deploybot" ).set( config.host(), config.site(), token );
			print.greenLine( "Token saved for #config.site()# on #config.host()#." ).toConsole();
		} );
	}
}
