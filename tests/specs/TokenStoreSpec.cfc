/** Checks how env tokens are keyed and stored, using a throwaway token file. */
component extends="tests.support.BaseSpec" {

	function run(){
		describe( "TokenStore", function(){
			beforeEach( function(){
				path  = tempTokenPath();
				store = createTokenStore( path );
			} );

			afterEach( function(){
				removeTokenFile( path );
			} );

			it( "builds a key from the host and slug", function(){
				var key = store.key( "deploybot.example.com", "my-site" );
				expect( key ).toBe( "deploybot_2eexample_2ecom__my-site" );
				expect( key ).toMatch( "^[A-Za-z0-9_-]+$" );
			} );

			it( "encodes dots, underscores, ports, and uppercase hosts", function(){
				expect( store.key( "Localhost:8080", "a.b_c" ) ).toBe( "localhost_3a8080__a_2eb_5fc" );
			} );

			it( "gives different keys for different servers or slugs", function(){
				var keys = {};
				for ( var pair in [
					[ "a.example.com", "site" ],
					[ "b.example.com", "site" ],
					[ "a.example.com", "site2" ],
					[ "a-example.com", "site" ],
					[ "a.example.com", "site." ],
					[ "a.example.com", "site_" ],
					[ "a.example.com:8443", "site" ]
				] ) {
					keys[ store.key( pair[ 1 ], pair[ 2 ] ) ] = true;
				}
				expect( keys.len() ).toBe( 7 );
			} );

			it( "saves, reads, and clears a token", function(){
				expect( store.has( "deploybot.example.com", "my-site" ) ).toBeFalse();
				expect( store.get( "deploybot.example.com", "my-site" ) ).toBe( "" );

				store.set( "deploybot.example.com", "my-site", secretToken );
				expect( store.has( "deploybot.example.com", "my-site" ) ).toBeTrue();
				expect( store.get( "deploybot.example.com", "my-site" ) ).toBe( secretToken );

				expect( store.clear( "deploybot.example.com", "my-site" ) ).toBeTrue();
				expect( store.get( "deploybot.example.com", "my-site" ) ).toBe( "" );
			} );

			it( "restricts the folder and the file before it writes a token", function(){
				var calls = [];
				// restrictAccess is private and does nothing on Windows, so replace it in place.
				prepareMock( store ).$property(
					propertyName  = "restrictAccess",
					propertyScope = "variables",
					mock          = function( path, mode ){
						calls.append( { path : arguments.path, mode : arguments.mode, size : fileExists( arguments.path ) ? getFileInfo( arguments.path ).size : -1 } );
					}
				);
				store.set( "deploybot.example.com", "my-site", secretToken );

				expect( calls.len() ).toBe( 2 );
				expect( calls[ 1 ].mode ).toBe( "700" );
				expect( calls[ 2 ].mode ).toBe( "600" );
				expect( calls[ 2 ].path ).toInclude( ".tmp-" );
				expect( calls[ 2 ].size ).toBe( 0 );
			} );

			it( "persists to its own file, not the CommandBox config", function(){
				store.set( "deploybot.example.com", "my.site", secretToken );
				expect( fileExists( path ) ).toBeTrue();
				var saved = deserializeJSON( fileRead( path ) );
				expect( saved.tokens ).toHaveKey( store.key( "deploybot.example.com", "my.site" ) );
				// A second instance on the same file sees it.
				expect( createTokenStore( path ).get( "deploybot.example.com", "my.site" ) ).toBe( secretToken );
			} );

			it( "defaults to ~/.deploybot/tokens.json", function(){
				var home = createObject( "java", "java.lang.System" ).getProperty( "user.home" );
				var defaultPath = createObject( "component", "commandbox-deploybot.models.TokenStore" ).init().getStorePath();
				expect( defaultPath ).toInclude( ".deploybot" );
				expect( defaultPath ).toInclude( "tokens.json" );
				expect( left( replace( defaultPath, "\", "/", "all" ), len( home ) ) ).toBe( replace( home, "\", "/", "all" ) );
				expect( defaultPath ).notToInclude( ".CommandBox" );
			} );

			it( "does not share a token between two servers with the same slug", function(){
				store.set( "one.example.com", "my-site", "token-one" );
				store.set( "two.example.com", "my-site", "token-two" );
				expect( store.get( "one.example.com", "my-site" ) ).toBe( "token-one" );
				expect( store.get( "two.example.com", "my-site" ) ).toBe( "token-two" );
				store.clear( "one.example.com", "my-site" );
				expect( store.get( "two.example.com", "my-site" ) ).toBe( "token-two" );
			} );

			it( "keeps a numeric or JSON-looking token as text", function(){
				for ( var token in [ "1234567890", "true", "null", "{""a"":1}" ] ) {
					store.set( "deploybot.example.com", "my-site", token );
					expect( createTokenStore( path ).get( "deploybot.example.com", "my-site" ) ).toBe( token );
				}
			} );

			it( "trims the token and refuses an empty one", function(){
				store.set( "deploybot.example.com", "my-site", "  abc  " );
				expect( store.get( "deploybot.example.com", "my-site" ) ).toBe( "abc" );
				expect( function(){
					store.set( "deploybot.example.com", "my-site", "   " );
				} ).toThrow( type = "Deploybot.Token" );
			} );

			it( "refuses to overwrite a damaged token file", function(){
				directoryCreate( getDirectoryFromPath( path ) );
				fileWrite( path, "not json" );
				expect( function(){
					store.set( "deploybot.example.com", "my-site", "abc" );
				} ).toThrow( type = "Deploybot.Token" );
				expect( fileRead( path ) ).toBe( "not json" );
			} );

			it( "reports that clear found nothing to remove", function(){
				expect( store.clear( "deploybot.example.com", "my-site" ) ).toBeFalse();
			} );
		} );
	}
}
