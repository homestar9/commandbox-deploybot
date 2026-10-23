/**
 * Runs `deploybot init`: sets up a site repository for DeployBot.
 *
 * The steps:
 *
 *  1. Check the settings. Nothing is written when they are wrong.
 *  2. Write the "deploybot" block in box.json. Other keys and their order stay as they were.
 *  3. Add the env file to .gitignore unless a rule there already covers it.
 *  4. Create the env file from .env.example with blank values, unless it exists.
 *
 * Running it again on a site that is set up changes only what differs. It never overwrites an
 * env file and makes no network request. The command asks for the token afterwards.
 *
 * This component never prints a value from .env.example or the env file. It prints file names.
 */
component extends="commandbox-deploybot.models.BaseService" {

	property name="packageService" inject="PackageService";
	property name="pathMatcher"    inject="PathPatternMatcher@globber";
	property name="envFile"        inject="EnvFile@commandbox-deploybot";
	property name="tokenStore"     inject="TokenStore@commandbox-deploybot";

	/**
	 * Returns the starting answers for the questions: { url, site, envFile }. They come from the
	 * existing "deploybot" block. Without one, site is built from the box.json slug or the folder
	 * name, and envFile is the default.
	 *
	 * @root The project root folder that contains box.json.
	 */
	struct function defaults( required string root ){
		var packageData = readPackage( arguments.root );
		var block       = isStruct( packageData.deploybot ?: "" ) ? packageData.deploybot : {};
		var site        = isSimpleValue( block.site ?: "" ) ? trim( block.site ?: "" ) : "";
		if ( !len( site ) ) {
			var slug = isSimpleValue( packageData.slug ?: "" ) ? trim( packageData.slug ?: "" ) : "";
			site     = toSlug( len( slug ) ? slug : listLast( replace( arguments.root, "\", "/", "all" ), "/" ) );
		}
		var envFile = isSimpleValue( block.envFile ?: "" ) ? trim( block.envFile ?: "" ) : "";
		return {
			url     : isSimpleValue( block.url ?: "" ) ? trim( block.url ?: "" ) : "",
			site    : site,
			envFile : len( envFile ) ? envFile : newConfig().defaultEnvFile()
		};
	}

	/**
	 * Sets up the site and returns { config, tokenSaved }. config is the checked DeploybotConfig.
	 * tokenSaved is true when a token is already saved for the site. Throws Deploybot.Config,
	 * before any write, when a setting is wrong.
	 *
	 * @root    The project root folder that contains box.json.
	 * @url     The DeployBot URL.
	 * @site    The site slug.
	 * @envFile The env file path, relative to the root. Empty means the default.
	 */
	struct function run(
		required string root,
		required string url,
		required string site,
		string envFile = ""
	){
		var config = newConfig().use( arguments.root, { url : arguments.url, site : arguments.site, envFile : arguments.envFile } );
		writeBlock( config );
		ignoreEnvFile( config );
		createEnvFile( config );
		return { config : config, tokenSaved : variables.tokenStore.has( config.host(), config.site() ) };
	}

	/**
	 * Prints what to do after `deploybot init`.
	 *
	 * @config The DeploybotConfig from run().
	 */
	void function printNextSteps( required any config ){
		say( "" );
		heading( "Next:" );
		say( "  1. Fill in the values in #arguments.config.envFile()#." );
		say( "  2. box deploybot env check" );
		say( "  3. box deploybot env push --dryRun" );
		say( "  4. box deploybot env push" );
	}

	/**
	 * Writes the "deploybot" block into box.json when it differs. envFile is written only when it
	 * is not the default, or when the block already had it.
	 *
	 * @config The checked DeploybotConfig.
	 */
	private void function writeBlock( required any config ){
		var root        = arguments.config.getRoot();
		var packageData = readPackage( root );
		var current     = isStruct( packageData.deploybot ?: "" ) ? packageData.deploybot : {};

		var block = structNew( "ordered" );
		block[ "url" ]  = arguments.config.url();
		block[ "site" ] = arguments.config.site();
		if ( current.keyExists( "envFile" ) || arguments.config.envFile() != arguments.config.defaultEnvFile() ) {
			block[ "envFile" ] = arguments.config.envFile();
		}

		if ( sameBlock( current, block ) ) {
			say( "box.json already has these deploybot settings." );
			return;
		}
		packageData[ "deploybot" ] = block;
		variables.packageService.writePackageDescriptor( packageData, root );
		good( "Saved the deploybot settings in box.json. They hold no secrets, so commit them." );
	}

	/**
	 * Adds the env file to .gitignore unless a rule there already covers it. Rules are read in
	 * order, so a later "!" rule can bring the file back.
	 *
	 * @config The checked DeploybotConfig.
	 */
	private void function ignoreEnvFile( required any config ){
		var root     = arguments.config.getRoot();
		var relative = relativeEnvPath( arguments.config );
		if ( !len( relative ) ) {
			warn( "#arguments.config.envFile()# is outside the repository. Make sure it is never committed." );
			return;
		}

		var path = root & "/.gitignore";
		var text = fileExists( path ) ? fileRead( path, "utf-8" ) : "";
		if ( isIgnored( text, relative ) ) {
			say( ".gitignore already covers #relative#." );
			return;
		}
		if ( len( text ) && !reFind( "[\r\n]$", text ) ) {
			text &= chr( 10 );
		}
		text &= "## DeployBot env file. Never commit it." & chr( 10 ) & "/" & relative & chr( 10 );
		fileWrite( path, text, "utf-8" );
		good( "Added /#relative# to .gitignore." );
	}

	/**
	 * Creates the env file from .env.example with blank values. An existing env file is never
	 * changed.
	 *
	 * @config The checked DeploybotConfig.
	 */
	private void function createEnvFile( required any config ){
		var target = arguments.config.envPath();
		var name   = arguments.config.envFile();
		if ( fileExists( target ) ) {
			say( "#name# already exists. It was not changed." );
			return;
		}
		if ( !fileExists( arguments.config.examplePath() ) ) {
			warn( "There is no .env.example. Create #name# yourself, and add .env.example so env check can compare keys." );
			return;
		}
		var folder = getDirectoryFromPath( target );
		if ( !directoryExists( folder ) ) {
			directoryCreate( folder, true );
		}
		fileWrite( target, variables.envFile.templateFrom( fileRead( arguments.config.examplePath(), "utf-8" ) ), "utf-8" );
		good( "Created #name# from .env.example. Every value is blank." );
	}

	/**
	 * Returns true when the .gitignore rules ignore the path. The last matching rule wins.
	 *
	 * @text     The .gitignore text.
	 * @relative The path relative to the root, with forward slashes.
	 */
	private boolean function isIgnored( required string text, required string relative ){
		var ignored = false;
		for ( var line in arguments.text.listToArray( chr( 10 ) & chr( 13 ) ) ) {
			var rule = trim( line );
			if ( !len( rule ) || left( rule, 1 ) == "##" ) {
				continue;
			}
			var negated = left( rule, 1 ) == "!";
			if ( negated ) {
				rule = mid( rule, 2, len( rule ) - 1 );
			}
			if ( len( rule ) && variables.pathMatcher.matchPattern( rule, arguments.relative ) ) {
				ignored = !negated;
			}
		}
		return ignored;
	}

	/**
	 * Returns the env file path relative to the root, or an empty string when it is outside.
	 *
	 * @config The checked DeploybotConfig.
	 */
	private string function relativeEnvPath( required any config ){
		var root = arguments.config.getRoot() & "/";
		var path = replace( arguments.config.envPath(), "\", "/", "all" );
		if ( left( path, len( root ) ) != root ) {
			return "";
		}
		return mid( path, len( root ) + 1, len( path ) - len( root ) );
	}

	/**
	 * Returns true when two deploybot blocks have the same keys and values.
	 *
	 * @current The block in box.json.
	 * @wanted  The block to write.
	 */
	private boolean function sameBlock( required struct current, required struct wanted ){
		if ( arguments.current.count() != arguments.wanted.count() ) {
			return false;
		}
		for ( var key in arguments.wanted ) {
			if ( !arguments.current.keyExists( key ) || !isSimpleValue( arguments.current[ key ] ) || compare( arguments.current[ key ], arguments.wanted[ key ] ) != 0 ) {
				return false;
			}
		}
		return true;
	}

	/**
	 * Reads box.json. Throws Deploybot.Config when it is missing or not a JSON object.
	 *
	 * @root The project root folder.
	 */
	private struct function readPackage( required string root ){
		var path = arguments.root & "/box.json";
		if ( !fileExists( path ) ) {
			throw( type = "Deploybot.Config", message = "No box.json file was found at #path#." );
		}
		var text = fileRead( path );
		if ( !isJSON( text ) || !isStruct( deserializeJSON( text ) ) ) {
			throw( type = "Deploybot.Config", message = "box.json at #path# is not valid JSON. Fix it, then run init again." );
		}
		return variables.packageService.readPackageDescriptorRaw( arguments.root );
	}

	/**
	 * Turns a name into a DeployBot slug: lower-case letters, digits, and dashes, at most 80
	 * characters, with no dash at either end.
	 *
	 * @name The box.json slug or the folder name.
	 */
	private string function toSlug( required string name ){
		var slug = reReplace( reReplace( lCase( arguments.name ), "[^a-z0-9]+", "-", "all" ), "^-+|-+$", "", "all" );
		return reReplace( left( slug, 80 ), "-+$", "" );
	}

	/** Returns a new, empty DeploybotConfig. */
	private any function newConfig(){
		return variables.wirebox.getInstance( "DeploybotConfig@commandbox-deploybot" );
	}
}
