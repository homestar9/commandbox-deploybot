/** Checks the local key comparison between the env file and .env.example. */
component extends="tests.support.BaseSpec" {

	function run(){
		describe( "EnvChecker", function(){
			beforeEach( function(){
				root  = createTempProject();
				lines = [];
				writeBoxJson( root );
				checker = prepareMock( model( "EnvChecker" ) );
				checker.$property( propertyName = "print", propertyScope = "variables", mock = createRecordingPrinter( lines ) );
			} );

			afterEach( function(){
				deleteDirectory( root );
			} );

			it( "lists missing, extra, and blank keys", function(){
				var result = checker.compareKeys(
					"A=1" & chr( 10 ) & "EXTRA=2" & chr( 10 ) & "BLANK=",
					"A=" & chr( 10 ) & "BLANK=" & chr( 10 ) & "MISSING="
				);
				expect( result.missing ).toBe( [ "MISSING" ] );
				expect( result.extra ).toBe( [ "EXTRA" ] );
				expect( result.blank ).toBe( [ "BLANK" ] );
			} );

			it( "compares an env file that uses export, CRLF, and a byte order mark", function(){
				var result = checker.compareKeys(
					chr( 65279 ) & "export A=1" & chr( 13 ) & chr( 10 ) & "B=2" & chr( 13 ) & chr( 10 ),
					"A=" & chr( 10 ) & "B="
				);
				expect( result.missing ).toBe( [] );
				expect( result.extra ).toBe( [] );
			} );

			it( "passes when every key is present", function(){
				writeText( root & "/.env.production", "A=1" & chr( 10 ) & "B=2" );
				writeText( root & "/.env.example", "A=" & chr( 10 ) & "B=" );
				var result = checker.run( loadConfig( root ) );
				expect( result.missing ).toBe( [] );
				expect( lines.toList( chr( 10 ) ) ).toInclude( "Local check passed" );
			} );

			it( "stops with Deploybot.MissingKeys and names the missing keys", function(){
				writeText( root & "/.env.production", "A=1" );
				writeText( root & "/.env.example", "A=" & chr( 10 ) & "B=" & chr( 10 ) & "C=" );
				expect( function(){
					checker.run( loadConfig( root ) );
				} ).toThrow( type = "Deploybot.MissingKeys", regex = "2 keys" );
				var output = lines.toList( chr( 10 ) );
				expect( output ).toInclude( "  - B" );
				expect( output ).toInclude( "  - C" );
			} );

			it( "reports extra keys and blank values without failing", function(){
				writeText( root & "/.env.production", "A=1" & chr( 10 ) & "EXTRA=1" & chr( 10 ) & "EMPTY=''" );
				writeText( root & "/.env.example", "A=" & chr( 10 ) & "EMPTY=" );
				checker.run( loadConfig( root ) );
				var output = lines.toList( chr( 10 ) );
				expect( output ).toInclude( "  + EXTRA" );
				expect( output ).toInclude( "  ! EMPTY" );
			} );

			it( "uses envFile from box.json", function(){
				writeBoxJson( root, { url : "https://deploybot.example.com", site : "my-site", envFile : "config.env" } );
				writeText( root & "/config.env", "A=1" );
				writeText( root & "/.env.example", "A=" );
				expect( checker.run( loadConfig( root ) ).missing ).toBe( [] );
			} );

			it( "stops when the env file is missing", function(){
				writeText( root & "/.env.example", "A=" );
				expect( function(){
					checker.run( loadConfig( root ) );
				} ).toThrow( type = "Deploybot.EnvFile" );
			} );

			it( "stops when .env.example is missing", function(){
				writeText( root & "/.env.production", "A=1" );
				expect( function(){
					checker.run( loadConfig( root ) );
				} ).toThrow( type = "Deploybot.NoExample" );
			} );

			it( "never prints a value", function(){
				writeText( root & "/.env.production", "A=#secretValue#" & chr( 10 ) & "EXTRA=#secretValue#" & chr( 10 ) & "export Z=""#secretValue#""" );
				writeText( root & "/.env.example", "A=" & chr( 10 ) & "MISSING=" );
				try {
					checker.run( loadConfig( root ) );
				} catch ( any exception ) {
					lines.append( exception.message );
				}
				expect( lines.toList( chr( 10 ) ) ).notToInclude( secretValue );
				expect( lines.toList( chr( 10 ) ) ).toInclude( "EXTRA" );
			} );
		} );
	}
}
