/**
 * Sets up shared test helpers. It gets module components from WireBox and creates temporary
 * projects, a recording print buffer, and stubs for the DeployBot client and the config service.
 *
 * tests/Run.cfc loads this working copy before tests run. Therefore,
 * "Name@commandbox-deploybot" refers to this copy.
 */
component extends="testbox.system.BaseSpec" {

	/** A value that must never appear in output. Env files in the specs use it as a secret. */
	variables.secretValue = "S3cr3t-Value-9f8e7d";

	/** A token that must never appear in output. */
	variables.secretToken = "tok-TOPSECRET-123456";

	/** Returns a module component with the same WireBox setup used by commands. */
	function model( required string name ){
		return application.wirebox.getInstance( arguments.name & "@commandbox-deploybot" );
	}

	/** Returns component metadata for a module path, such as "commands.deploybot.env.push". */
	struct function meta( required string dotPath ){
		return getComponentMetadata( "commandbox-deploybot." & arguments.dotPath );
	}

	/** Returns the repository root with forward slashes and no final slash. */
	string function repoRoot(){
		return reReplace( replace( expandPath( "/commandbox-deploybot" ), "\", "/", "all" ), "/+$", "" );
	}

	/** Creates an empty folder under .test-work and returns its path. */
	string function createTempProject(){
		var root = repoRoot() & "/.test-work/commandbox-deploybot-spec-" & createUUID();
		directoryCreate( root, true, true );
		return root;
	}

	/**
	 * Deletes a temporary project. Dropbox or antivirus software can briefly lock files on
	 * Windows, so it tries several times.
	 */
	void function deleteDirectory( required string path ){
		if ( !len( arguments.path ) || !directoryExists( arguments.path ) ) {
			return;
		}
		for ( var attempt = 1; attempt <= 5; attempt++ ) {
			try {
				directoryDelete( arguments.path, true );
				return;
			} catch ( any deleteFailure ) {
				sleep( 500 );
			}
		}
	}

	/** Writes a box.json with a deploybot block into a folder. */
	void function writeBoxJson( required string root, struct deploybot = { url : "https://deploybot.example.com", site : "my-site" } ){
		fileWrite( arguments.root & "/box.json", serializeJSON( { name : "Sample", deploybot : arguments.deploybot } ) );
	}

	/** Writes a UTF-8 text file without a byte order mark. */
	void function writeText( required string path, required string text ){
		fileWrite( arguments.path, arguments.text, "utf-8" );
	}

	/** Returns a loaded DeploybotConfig for a project folder that has box.json. */
	any function loadConfig( required string root ){
		return model( "DeploybotConfig" ).load( arguments.root );
	}

	/** Returns a print buffer stub that saves every printed line in the lines array. */
	any function createRecordingPrinter( required array lines ){
		var printer  = createStub();
		var recorded = arguments.lines;
		for ( var method in [ "line", "boldLine", "redLine", "greenLine", "yellowLine", "boldRedLine", "boldGreenLine" ] ) {
			printer.$( method = method, callback = function( text = "" ){
				recorded.append( arguments.text );
				return printer;
			} );
		}
		printer.$( "toConsole", printer );
		return printer;
	}

	/** Returns a fake DeployBot client. Queue responses with respond(), then read calls(). */
	any function createFakeClient(){
		return new tests.support.FakeClient();
	}

	/** Returns a path for a throwaway token file in the temp directory. It does not exist yet. */
	string function tempTokenPath(){
		return getTempDirectory() & "commandbox-deploybot-spec-#createUUID()#/tokens.json";
	}

	/** Returns a new TokenStore that saves to the given file, or to a fresh temp file. */
	any function createTokenStore( string storePath = tempTokenPath() ){
		return createObject( "component", "commandbox-deploybot.models.TokenStore" ).init( arguments.storePath );
	}

	/** Deletes the folder a temp token file lives in. */
	void function removeTokenFile( required string storePath ){
		var folder = getDirectoryFromPath( arguments.storePath );
		if ( directoryExists( folder ) ) {
			directoryDelete( folder, true );
		}
	}

	/**
	 * Returns an EnvPusher wired to a fake client, a token store, and a recording printer.
	 * The token is saved for https://deploybot.example.com / my-site unless saveToken is false.
	 */
	any function createPusher( required any client, required array lines, boolean saveToken = true ){
		var store = createTokenStore();
		if ( arguments.saveToken ) {
			store.set( "deploybot.example.com", "my-site", variables.secretToken );
		}
		var pusher = prepareMock( model( "EnvPusher" ) );
		pusher.$property( propertyName = "print", propertyScope = "variables", mock = createRecordingPrinter( arguments.lines ) );
		pusher.$property( propertyName = "deploybotClient", propertyScope = "variables", mock = arguments.client );
		pusher.$property( propertyName = "tokenStore", propertyScope = "variables", mock = store );
		return pusher;
	}

	/** Builds the struct DeploybotClient returns for a JSON response. */
	struct function jsonResponse( required numeric statusCode, struct json = {} ){
		return { statusCode : arguments.statusCode, isJson : true, json : arguments.json };
	}

	/** Builds a successful dry-run or push response. */
	struct function okResponse( struct diff = {}, array steps = [] ){
		return jsonResponse( 200, {
			ok         : true,
			error      : "",
			dryRun     : false,
			path       : "C:\websites\x\.env",
			diff       : { added : arguments.diff.added ?: [], removed : arguments.diff.removed ?: [], changed : arguments.diff.changed ?: [] },
			missing    : [],
			extra      : [],
			steps      : arguments.steps,
			rolledBack : false,
			deployId   : "d1",
			recordUrl  : "https://deploybot.example.com/deploys/d1"
		} );
	}
}
