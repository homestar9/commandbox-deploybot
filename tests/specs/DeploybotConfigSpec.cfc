/** Checks how the box.json deploybot block is read and validated. */
component extends="tests.support.BaseSpec" {

	function run(){
		describe( "DeploybotConfig", function(){
			beforeEach( function(){
				root = createTempProject();
			} );

			afterEach( function(){
				deleteDirectory( root );
			} );

			it( "reads url, site, and envFile", function(){
				writeBoxJson( root, { url : "https://deploybot.example.com", site : "my-site", envFile : "prod.env" } );
				var config = loadConfig( root );
				expect( config.url() ).toBe( "https://deploybot.example.com" );
				expect( config.site() ).toBe( "my-site" );
				expect( config.envFile() ).toBe( "prod.env" );
				expect( config.host() ).toBe( "deploybot.example.com" );
				expect( config.envPath() ).toBe( root & "/prod.env" );
				expect( config.examplePath() ).toBe( root & "/.env.example" );
			} );

			it( "defaults envFile to .env.production", function(){
				writeBoxJson( root );
				expect( loadConfig( root ).envFile() ).toBe( ".env.production" );
				writeBoxJson( root, { url : "https://deploybot.example.com", site : "my-site", envFile : "  " } );
				expect( loadConfig( root ).envFile() ).toBe( ".env.production" );
			} );

			it( "removes final slashes from the url", function(){
				writeBoxJson( root, { url : "https://deploybot.example.com//", site : "my-site" } );
				expect( loadConfig( root ).url() ).toBe( "https://deploybot.example.com" );
			} );

			it( "explains the box.json block when it is missing", function(){
				fileWrite( root & "/box.json", serializeJSON( { name : "Sample" } ) );
				expect( function(){
					loadConfig( root );
				} ).toThrow( type = "Deploybot.Config", regex = """deploybot"": \{ ""url""" );
			} );

			it( "stops when box.json is missing or invalid", function(){
				expect( function(){
					loadConfig( root );
				} ).toThrow( type = "Deploybot.Config", regex = "No box.json" );
				fileWrite( root & "/box.json", "{ nope" );
				expect( function(){
					loadConfig( root );
				} ).toThrow( type = "Deploybot.Config", regex = "invalid JSON" );
			} );

			it( "requires url and site", function(){
				writeBoxJson( root, { site : "my-site" } );
				expect( function(){
					loadConfig( root );
				} ).toThrow( type = "Deploybot.Config", regex = "deploybot.url" );
				writeBoxJson( root, { url : "https://deploybot.example.com" } );
				expect( function(){
					loadConfig( root );
				} ).toThrow( type = "Deploybot.Config", regex = "deploybot.site" );
			} );

			it( "rejects a site slug that is not safe in a URL path", function(){
				for ( var bad in [ "a/b", "a b", "../x", "x?y=1", "-x" ] ) {
					writeBoxJson( root, { url : "https://deploybot.example.com", site : bad } );
					expect( function(){
						loadConfig( root );
					} ).toThrow( type = "Deploybot.Config", regex = "site slug" );
				}
			} );

			it( "uses DeployBot's slug rule: lower-case letters, digits, and dashes", function(){
				for ( var bad in [ "my.site", "my_site", "My-Site", "x-", repeatString( "a", 81 ) ] ) {
					writeBoxJson( root, { url : "https://deploybot.example.com", site : bad } );
					expect( function(){
						loadConfig( root );
					} ).toThrow( type = "Deploybot.Config", regex = "site slug" );
				}
				for ( var good in [ "a", "9", "my-site", "staging-example-com", repeatString( "a", 80 ) ] ) {
					writeBoxJson( root, { url : "https://deploybot.example.com", site : good } );
					expect( loadConfig( root ).site() ).toBe( good );
				}
			} );

			it( "requires https except for localhost and 127.0.0.1", function(){
				writeBoxJson( root, { url : "http://deploybot.example.com", site : "my-site" } );
				expect( function(){
					loadConfig( root );
				} ).toThrow( type = "Deploybot.Config", regex = "https" );

				for ( var allowed in [ "http://localhost", "http://localhost:8080", "http://127.0.0.1:51765", "https://deploybot.example.com:8443" ] ) {
					writeBoxJson( root, { url : allowed, site : "my-site" } );
					expect( loadConfig( root ).url() ).toBe( allowed );
				}
			} );

			it( "does not let a look-alike host pass as local", function(){
				for ( var bad in [ "http://localhost.evil.com", "http://127.0.0.1.evil.com", "http://evil.com/localhost" ] ) {
					writeBoxJson( root, { url : bad, site : "my-site" } );
					expect( function(){
						loadConfig( root );
					} ).toThrow( type = "Deploybot.Config", regex = "https" );
				}
			} );

			it( "rejects a url that is not http or https", function(){
				for ( var bad in [ "ftp://deploybot.example.com", "deploybot.example.com", "" ] ) {
					writeBoxJson( root, { url : bad, site : "my-site" } );
					expect( function(){
						loadConfig( root );
					} ).toThrow( type = "Deploybot.Config" );
				}
			} );

			it( "finds the project root from a child folder", function(){
				writeBoxJson( root );
				directoryCreate( root & "/handlers/sub", true, true );
				expect( model( "ProjectLocator" ).findRoot( root & "/handlers/sub" ) ).toBe( root );
			} );

			it( "stops when no project is found", function(){
				directoryCreate( root & "/.git" );
				expect( function(){
					model( "ProjectLocator" ).findRoot( root );
				} ).toThrow( type = "Deploybot.NoProject" );
			} );
		} );
	}
}
