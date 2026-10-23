/**
 * Checks GitInspector against real git in throwaway folders. It is the only spec that starts
 * git. It skips itself when git is not installed.
 */
component extends="tests.support.BaseSpec" {

	function run(){
		// A fresh instance: other specs stub the shared one.
		inspector = createObject( "component", "commandbox-deploybot.models.GitInspector" );
		hasGit    = inspector.status( getTempDirectory() & "probe.env" ).known;

		describe( "GitInspector", function(){
			beforeEach( function(){
				root = createTempProject();
			} );

			afterEach( function(){
				// Git makes its object files read-only, which stops a delete on Windows.
				for ( var file in directoryList( root, true, "path", "*", "", "file" ) ) {
					fileSetAttribute( file, "normal" );
				}
				deleteDirectory( root );
			} );

			it( title = "tells tracked, ignored, and uncovered files apart", skip = !hasGit, body = function(){
				git( root, [ "init", "-q" ] );
				writeText( root & "/.gitignore", ".env.production" & chr( 10 ) );
				writeText( root & "/.env.production", "A=1" );
				writeText( root & "/tracked.env", "A=1" );
				writeText( root & "/loose.env", "A=1" );
				git( root, [ "add", "tracked.env" ] );

				var ignored = inspector.status( root & "/.env.production" );
				expect( ignored.known ).toBeTrue();
				expect( ignored.repository ).toBeTrue();
				expect( ignored.tracked ).toBeFalse();
				expect( ignored.ignored ).toBeTrue();

				expect( inspector.status( root & "/tracked.env" ).tracked ).toBeTrue();

				var loose = inspector.status( root & "/loose.env" );
				expect( loose.tracked ).toBeFalse();
				expect( loose.ignored ).toBeFalse();
			} );

			it( title = "reports a file outside any repository", skip = !hasGit, body = function(){
				var outside = getTempDirectory() & "commandbox-deploybot-spec-" & createUUID();
				directoryCreate( outside );
				try {
					var result = inspector.status( outside & "/.env.production" );
					expect( result.known ).toBeTrue();
					expect( result.repository ).toBeFalse();
				} finally {
					deleteDirectory( outside );
				}
			} );

			it( "reports nothing for a folder that does not exist", function(){
				expect( inspector.status( root & "/missing/.env.production" ).known ).toBeFalse();
			} );
		} );
	}

	/** Runs git in a folder for the spec setup and fails the spec when git fails. */
	private void function git( required string folder, required array args ){
		var command = [ "git" ];
		command.append( arguments.args, true );
		var builder = createObject( "java", "java.lang.ProcessBuilder" ).init( javaCast( "string[]", command ) );
		builder.directory( createObject( "java", "java.io.File" ).init( arguments.folder ) );
		builder.redirectErrorStream( true );
		var process = builder.start();
		var output  = createObject( "java", "java.lang.String" ).init( process.getInputStream().readAllBytes() );
		if ( process.waitFor() != 0 ) {
			fail( "git #arguments.args.toList( ' ' )# failed: #output#" );
		}
	}
}
