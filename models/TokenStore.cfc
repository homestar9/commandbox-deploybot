/**
 * Stores each site's env token in its own file in the user's profile:
 * ~/.deploybot/tokens.json (on Windows, %USERPROFILE%\.deploybot\tokens.json).
 *
 * Tokens are deliberately NOT kept in the CommandBox user config. CommandBox's config auto-sync
 * (on by default for ForgeBox Pro accounts) uploads that whole file to ForgeBox, and there is no
 * way to exclude a key. This file is outside the CommandBox home and outside any repository. On
 * Windows the profile folder is readable only by its owner, SYSTEM, and Administrators. On macOS
 * and Linux the file is made readable only by its owner (600) and its folder private (700).
 *
 * Each token is saved under a key built from the DeployBot host and the site slug, so two
 * DeployBot servers that use the same slug do not share a token. Writes go to a temp file that
 * is then moved into place, so a crash never leaves half a file.
 *
 * Nothing in this component prints the token.
 */
component singleton {

	/** Where tokens are saved. setStorePath() overrides it (specs use a temp file). */
	variables.storePath = "";

	/**
	 * Uses ~/.deploybot/tokens.json unless a path is given.
	 *
	 * @storePath Absolute path of the token file.
	 */
	function init( string storePath = "" ){
		variables.storePath = len( arguments.storePath ) ? arguments.storePath : defaultStorePath();
		return this;
	}

	/**
	 * Points the store at another file.
	 *
	 * @storePath Absolute path of the token file.
	 */
	function setStorePath( required string storePath ){
		variables.storePath = arguments.storePath;
		return this;
	}

	/**
	 * The file tokens are saved in.
	 */
	string function getStorePath(){
		return variables.storePath;
	}

	/**
	 * Builds the key for a site on a DeployBot server. The key joins the encoded host and the
	 * encoded slug with two underscores. Every character other than a letter, a number, or a dash
	 * becomes an underscore and two hex digits (a dot becomes _2e). An encoded part never holds
	 * two underscores in a row, so different servers and slugs never share a key.
	 *
	 * @host The DeployBot host with its port, such as "deploybot.example.com". It is lower-cased.
	 * @site The site slug.
	 */
	string function key( required string host, required string site ){
		return encodePart( lCase( trim( arguments.host ) ) ) & "__" & encodePart( trim( arguments.site ) );
	}

	/**
	 * Returns the saved token for a site, or an empty string when none is saved.
	 *
	 * @host The DeployBot host.
	 * @site The site slug.
	 */
	string function get( required string host, required string site ){
		var tokens = readAll();
		var name   = key( arguments.host, arguments.site );
		return tokens.keyExists( name ) && isSimpleValue( tokens[ name ] ) ? tokens[ name ] : "";
	}

	/**
	 * Returns true when a token is saved for the site.
	 *
	 * @host The DeployBot host.
	 * @site The site slug.
	 */
	boolean function has( required string host, required string site ){
		return len( get( arguments.host, arguments.site ) ) > 0;
	}

	/**
	 * Saves a token for a site. An empty token throws Deploybot.Token.
	 *
	 * @host  The DeployBot host.
	 * @site  The site slug.
	 * @token The env token from the site page in DeployBot.
	 */
	void function set( required string host, required string site, required string token ){
		var clean = trim( arguments.token );
		if ( !len( clean ) ) {
			throw( type = "Deploybot.Token", message = "The token is empty. Nothing was saved." );
		}
		var tokens = readAll();
		tokens[ key( arguments.host, arguments.site ) ] = clean;
		writeAll( tokens );
	}

	/**
	 * Removes the saved token for a site. Returns true when a token was saved.
	 *
	 * @host The DeployBot host.
	 * @site The site slug.
	 */
	boolean function clear( required string host, required string site ){
		var tokens = readAll();
		var name   = key( arguments.host, arguments.site );
		if ( !tokens.keyExists( name ) ) {
			return false;
		}
		tokens.delete( name );
		writeAll( tokens );
		return true;
	}

	/**
	 * ~/.deploybot/tokens.json, from the JVM's user.home.
	 */
	private string function defaultStorePath(){
		var home = createObject( "java", "java.lang.System" ).getProperty( "user.home" );
		return reReplace( home, "[\\/]+$", "" ) & "/.deploybot/tokens.json";
	}

	/**
	 * Reads every saved token as key => token. A missing file is an empty store; a damaged one
	 * throws Deploybot.Token naming the file, so it is never silently overwritten.
	 */
	private struct function readAll(){
		if ( !fileExists( variables.storePath ) ) {
			return {};
		}
		var text = fileRead( variables.storePath, "utf-8" );
		if ( !len( trim( text ) ) ) {
			return {};
		}
		if ( !isJSON( text ) ) {
			throw(
				type    = "Deploybot.Token",
				message = "The token file #variables.storePath# is not valid JSON. Fix or delete it, then run `box deploybot token set` again."
			);
		}
		var parsed = deserializeJSON( text );
		return isStruct( parsed ) && parsed.keyExists( "tokens" ) && isStruct( parsed.tokens ) ? parsed.tokens : {};
	}

	/**
	 * Writes every token through a temp file in the same folder, then moves it into place. On
	 * macOS and Linux the folder is made private (700) and the temp file is made readable only by
	 * its owner (600) before any token is written to it.
	 *
	 * @tokens key => token.
	 */
	private void function writeAll( required struct tokens ){
		var folder = getDirectoryFromPath( variables.storePath );
		if ( !directoryExists( folder ) ) {
			directoryCreate( folder );
		}
		restrictAccess( folder, "700" );
		var temp = variables.storePath & ".tmp-" & createUUID();
		fileWrite( temp, "", "utf-8" );
		restrictAccess( temp, "600" );
		fileWrite( temp, serializeJSON( { "tokens" : arguments.tokens } ), "utf-8" );
		fileMove( temp, variables.storePath );
	}

	/**
	 * Sets a Unix access mode on macOS and Linux. Windows keeps the profile folder's access list,
	 * which already limits it to the owner, SYSTEM, and Administrators.
	 *
	 * @path The file or folder.
	 * @mode The mode, such as "600".
	 */
	private void function restrictAccess( required string path, required string mode ){
		if ( isWindows() ) {
			return;
		}
		fileSetAccessMode( arguments.path, arguments.mode );
	}

	/** Returns true on Windows. */
	private boolean function isWindows(){
		return findNoCase( "windows", server.os.name ) > 0;
	}

	/**
	 * Encodes one part of the key. Letters, numbers, and dashes stay. Everything else becomes an
	 * underscore followed by the character code in two hex digits (_u and four digits above 255).
	 *
	 * @value The text to encode.
	 */
	private string function encodePart( required string value ){
		var encoded = "";
		for ( var position = 1; position <= len( arguments.value ); position++ ) {
			var character = mid( arguments.value, position, 1 );
			var code      = asc( character );
			if ( reFind( "^[A-Za-z0-9-]$", character ) ) {
				encoded &= character;
			} else if ( code < 256 ) {
				encoded &= "_" & lCase( right( "0" & formatBaseN( code, 16 ), 2 ) );
			} else {
				encoded &= "_u" & lCase( right( "0000" & formatBaseN( code, 16 ), 4 ) );
			}
		}
		return encoded;
	}
}
