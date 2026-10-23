/**
 * Loads and checks one site's DeployBot settings.
 *
 * The settings are not secret. They live in a "deploybot" block in the site repository's
 * box.json:
 *
 *   "deploybot": { "url": "https://deploybot.example.com", "site": "my-site", "envFile": ".env.production" }
 *
 * A command finds the project root and calls load( root ). The token is not part of these
 * settings. TokenStore keeps it in ~/.deploybot/tokens.json.
 */
component {

	function init(){
		variables.root     = "";
		variables.settings = {};
		return this;
	}

	/**
	 * Reads and checks the settings for one site. Throws Deploybot.Config with an explanation
	 * when the box.json block is missing or wrong.
	 *
	 * @root The project root folder that contains box.json.
	 */
	function load( required string root ){
		variables.root = reReplace( replace( arguments.root, "\", "/", "all" ), "/+$", "" );
		var path = variables.root & "/box.json";
		if ( !fileExists( path ) ) {
			throw( type = "Deploybot.Config", message = "No box.json file was found at #path#." );
		}

		var packageData = {};
		try {
			packageData = deserializeJSON( fileRead( path ) );
		} catch ( any exception ) {
			throw( type = "Deploybot.Config", message = "box.json has invalid JSON: #exception.message#" );
		}
		if ( !isStruct( packageData ) || !packageData.keyExists( "deploybot" ) || !isStruct( packageData.deploybot ) ) {
			throw( type = "Deploybot.Config", message = missingBlockMessage() );
		}
		return use( arguments.root, packageData.deploybot );
	}

	/**
	 * Uses and checks settings that are not in box.json yet. `deploybot init` calls it before it
	 * writes anything. Throws Deploybot.Config like load().
	 *
	 * @root  The project root folder.
	 * @block The settings: url, site, and an optional envFile.
	 */
	function use( required string root, required struct block ){
		variables.root = reReplace( replace( arguments.root, "\", "/", "all" ), "/+$", "" );
		variables.settings = {
			url     : cleanUrl( arguments.block.url ?: "" ),
			site    : trim( arguments.block.site ?: "" ),
			envFile : trim( arguments.block.envFile ?: "" )
		};
		if ( !len( variables.settings.envFile ) ) {
			variables.settings.envFile = defaultEnvFile();
		}
		validate();
		return this;
	}

	/** Returns the env file name used when box.json names none. */
	string function defaultEnvFile(){
		return ".env.production";
	}

	/** Returns the DeployBot server URL without a final slash. */
	string function url(){
		return variables.settings.url;
	}

	/** Returns the DeployBot site slug. */
	string function site(){
		return variables.settings.site;
	}

	/** Returns the env file path as written in box.json, such as ".env.production". */
	string function envFile(){
		return variables.settings.envFile;
	}

	/** Returns the host (with the port, if any) of the DeployBot URL, in lower case. */
	string function host(){
		return parseUrl( variables.settings.url ).host;
	}

	/** Returns the project root folder with forward slashes and no final slash. */
	string function getRoot(){
		return variables.root;
	}

	/** Returns the full path to the env file. */
	string function envPath(){
		var file = replace( variables.settings.envFile, "\", "/", "all" );
		if ( reFind( "^/|^[A-Za-z]:", file ) ) {
			return file;
		}
		return variables.root & "/" & file;
	}

	/** Returns the full path to .env.example in the project root. */
	string function examplePath(){
		return variables.root & "/.env.example";
	}

	/**
	 * Returns true for a host where http is allowed. Only the local machine qualifies, so a
	 * token never travels over a network without TLS.
	 *
	 * @host The host from the URL, with or without a port.
	 */
	boolean function isLocalAddress( required string host ){
		return listFindNoCase( "localhost,127.0.0.1", listFirst( arguments.host, ":" ) ) > 0;
	}

	/** Returns the message that explains the box.json block to add. */
	string function missingBlockMessage(){
		return "box.json has no ""deploybot"" block. Add one like this: "
			& """deploybot"": { ""url"": ""https://deploybot.example.com"", ""site"": ""my-site"", ""envFile"": "".env.production"" } "
			& "(envFile is optional).";
	}

	/** Checks every setting and throws Deploybot.Config for the first problem. */
	private void function validate(){
		var settings = variables.settings;
		if ( !len( settings.url ) ) {
			throw( type = "Deploybot.Config", message = "box.json deploybot.url is missing. #missingBlockMessage()#" );
		}
		if ( !len( settings.site ) ) {
			throw( type = "Deploybot.Config", message = "box.json deploybot.site is missing. #missingBlockMessage()#" );
		}
		// The same rule as DeployBot's RefValidator: 1 to 80 characters, no dash at either end.
		if ( !reFind( "^[a-z0-9]([a-z0-9-]{0,78}[a-z0-9])?$", settings.site ) ) {
			throw( type = "Deploybot.Config", message = "box.json deploybot.site must be a site slug such as ""my-site"". It may use lower-case letters, numbers, and dashes, up to 80 characters. It can't start or end with a dash." );
		}

		var parts = parseUrl( settings.url );
		if ( !len( parts.scheme ) ) {
			throw( type = "Deploybot.Config", message = "box.json deploybot.url must be a full URL such as ""https://deploybot.example.com""." );
		}
		if ( parts.scheme == "http" && !isLocalAddress( parts.host ) ) {
			throw( type = "Deploybot.Config", message = "box.json deploybot.url must use https. Plain http is allowed only for localhost and 127.0.0.1." );
		}
	}

	/**
	 * Cleans the URL: trims it and removes final slashes. Returns an empty string for a
	 * non-string value.
	 *
	 * @value The URL as written in box.json.
	 */
	private string function cleanUrl( required any value ){
		if ( !isSimpleValue( arguments.value ) ) {
			return "";
		}
		return reReplace( trim( arguments.value ), "/+$", "" );
	}

	/**
	 * Splits a URL into its scheme and host. The scheme is empty when the URL is not http(s).
	 *
	 * @url The URL to split.
	 */
	private struct function parseUrl( required string url ){
		var match = reFindNoCase( "^(https?)://([^/?##\s]+)", arguments.url, 1, true );
		if ( match.pos[ 1 ] == 0 ) {
			return { scheme : "", host : "" };
		}
		return {
			scheme : lCase( mid( arguments.url, match.pos[ 2 ], match.len[ 2 ] ) ),
			host   : lCase( mid( arguments.url, match.pos[ 3 ], match.len[ 3 ] ) )
		};
	}
}
