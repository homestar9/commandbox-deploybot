/** Checks `deploybot init`: box.json, .gitignore, the starter env file, and the defaults. */
component extends="tests.support.BaseSpec" {

	function run(){
		describe( "SiteSetup", function(){
			beforeEach( function(){
				root       = createTempProject();
				lines      = [];
				tokenPath  = tempTokenPath();
				tokenStore = createTokenStore( tokenPath );
				setup      = prepareMock( model( "SiteSetup" ) );
				setup.$property( propertyName = "print", propertyScope = "variables", mock = createRecordingPrinter( lines ) );
				setup.$property( propertyName = "tokenStore", propertyScope = "variables", mock = tokenStore );
				writeText( root & "/box.json", "{" & chr( 10 ) & "    ""name"":""Sample""," & chr( 10 ) & "    ""slug"":""sample-site""," & chr( 10 ) & "    ""version"":""1.0.0""" & chr( 10 ) & "}" & chr( 10 ) );
			} );

			afterEach( function(){
				deleteDirectory( root );
				removeTokenFile( tokenPath );
			} );

			describe( "defaults", function(){
				it( "uses the box.json slug when there is no deploybot block", function(){
					var answers = setup.defaults( root );
					expect( answers.url ).toBe( "" );
					expect( answers.site ).toBe( "sample-site" );
					expect( answers.envFile ).toBe( ".env.production" );
				} );

				it( "builds the slug from the folder name when box.json has none", function(){
					var folder = root & "/My_Shop.Web";
					directoryCreate( folder );
					writeText( folder & "/box.json", "{ ""name"" : ""Shop"" }" );
					expect( setup.defaults( folder ).site ).toBe( "my-shop-web" );
				} );

				it( "keeps a built slug within DeployBot's 80 characters", function(){
					writeText( root & "/box.json", "{ ""slug"" : ""#repeatString( "a", 79 )#.b"" }" );
					expect( setup.defaults( root ).site ).toBe( repeatString( "a", 79 ) );
				} );

				it( "uses an existing deploybot block", function(){
					writeBoxJson( root, { url : "https://deploybot.example.com", site : "my-site", envFile : "config.env" } );
					var answers = setup.defaults( root );
					expect( answers.url ).toBe( "https://deploybot.example.com" );
					expect( answers.site ).toBe( "my-site" );
					expect( answers.envFile ).toBe( "config.env" );
				} );
			} );

			describe( "box.json", function(){
				it( "adds the block and keeps the other keys in their order", function(){
					setup.run( root = root, url = "https://deploybot.example.com/", site = "my-site" );

					var text = fileRead( root & "/box.json" );
					var data = deserializeJSON( text );
					expect( data.deploybot ).toBe( { url : "https://deploybot.example.com", site : "my-site" } );
					expect( data.version ).toBe( "1.0.0" );
					expect( find( """name""", text ) ).toBeLT( find( """version""", text ) );
					expect( lines.toList( chr( 10 ) ) ).toInclude( "Saved the deploybot settings" );
					expect( loadConfig( root ).site() ).toBe( "my-site" );
				} );

				it( "writes envFile only when it is not the default", function(){
					setup.run( root = root, url = "https://deploybot.example.com", site = "my-site", envFile = ".env.production" );
					expect( deserializeJSON( fileRead( root & "/box.json" ) ).deploybot ).notToHaveKey( "envFile" );

					setup.run( root = root, url = "https://deploybot.example.com", site = "my-site", envFile = "config/prod.env" );
					expect( deserializeJSON( fileRead( root & "/box.json" ) ).deploybot.envFile ).toBe( "config/prod.env" );
				} );

				it( "leaves box.json alone when the settings are the same", function(){
					setup.run( root = root, url = "https://deploybot.example.com", site = "my-site" );
					var before = fileRead( root & "/box.json" );
					lines.clear();

					setup.run( root = root, url = "https://deploybot.example.com", site = "my-site" );
					expect( fileRead( root & "/box.json" ) ).toBe( before );
					expect( lines.toList( chr( 10 ) ) ).toInclude( "already has these deploybot settings" );
				} );

				it( "writes nothing when a setting is wrong", function(){
					var before = fileRead( root & "/box.json" );
					expect( function(){
						setup.run( root = root, url = "http://deploybot.example.com", site = "my-site" );
					} ).toThrow( type = "Deploybot.Config", regex = "https" );
					expect( function(){
						setup.run( root = root, url = "https://deploybot.example.com", site = "" );
					} ).toThrow( type = "Deploybot.Config" );
					expect( fileRead( root & "/box.json" ) ).toBe( before );
					expect( fileExists( root & "/.gitignore" ) ).toBeFalse();
				} );

				it( "stops when box.json is not valid JSON", function(){
					writeText( root & "/box.json", "{ nope" );
					expect( function(){
						setup.run( root = root, url = "https://deploybot.example.com", site = "my-site" );
					} ).toThrow( type = "Deploybot.Config", regex = "not valid JSON" );
				} );
			} );

			describe( ".gitignore", function(){
				it( "creates .gitignore with the env file", function(){
					setup.run( root = root, url = "https://deploybot.example.com", site = "my-site" );
					expect( fileRead( root & "/.gitignore" ) ).toInclude( chr( 10 ) & "/.env.production" & chr( 10 ) );
					expect( lines.toList( chr( 10 ) ) ).toInclude( "Added /.env.production to .gitignore" );
				} );

				it( "appends to an existing .gitignore that has no final line break", function(){
					writeText( root & "/.gitignore", "node_modules/" );
					setup.run( root = root, url = "https://deploybot.example.com", site = "my-site" );
					expect( fileRead( root & "/.gitignore" ) ).toBe( "node_modules/" & chr( 10 ) & "## DeployBot env file. Never commit it." & chr( 10 ) & "/.env.production" & chr( 10 ) );
				} );

				it( "does not add a rule when one already covers the env file", function(){
					writeText( root & "/.gitignore", ".env" & chr( 10 ) & ".env.*" & chr( 10 ) & "!.env.example" & chr( 10 ) );
					setup.run( root = root, url = "https://deploybot.example.com", site = "my-site" );
					expect( fileRead( root & "/.gitignore" ) ).notToInclude( "DeployBot" );
					expect( lines.toList( chr( 10 ) ) ).toInclude( ".gitignore already covers .env.production" );
				} );

				it( "adds a rule when a later ! rule brings the env file back", function(){
					writeText( root & "/.gitignore", ".env.*" & chr( 13 ) & chr( 10 ) & "!.env.production" & chr( 13 ) & chr( 10 ) );
					setup.run( root = root, url = "https://deploybot.example.com", site = "my-site" );
					expect( fileRead( root & "/.gitignore" ) ).toInclude( "/.env.production" & chr( 10 ) );
				} );

				it( "ignores an env file in a subfolder by its path", function(){
					setup.run( root = root, url = "https://deploybot.example.com", site = "my-site", envFile = "config/prod.env" );
					expect( fileRead( root & "/.gitignore" ) ).toInclude( "/config/prod.env" );
				} );
			} );

			describe( "env file", function(){
				it( "creates the env file from .env.example with blank values", function(){
					writeText( root & "/.env.example", "## App" & chr( 10 ) & "APP_NAME=#secretValue#" & chr( 10 ) & "export API_KEY = ""#secretValue#""" & chr( 10 ) );
					setup.run( root = root, url = "https://deploybot.example.com", site = "my-site" );

					expect( fileRead( root & "/.env.production", "utf-8" ) ).toBe( "## App" & chr( 10 ) & "APP_NAME=" & chr( 10 ) & "export API_KEY=" & chr( 10 ) );
					expect( lines.toList( chr( 10 ) ) ).toInclude( "Created .env.production from .env.example" );
				} );

				it( "creates the folder of an env file in a subfolder", function(){
					writeText( root & "/.env.example", "A=1" );
					setup.run( root = root, url = "https://deploybot.example.com", site = "my-site", envFile = "config/prod.env" );
					expect( fileRead( root & "/config/prod.env", "utf-8" ) ).toBe( "A=" & chr( 10 ) );
				} );

				it( "never changes an existing env file", function(){
					writeText( root & "/.env.example", "A=" & chr( 10 ) & "B=" );
					writeText( root & "/.env.production", "A=#secretValue#" );
					setup.run( root = root, url = "https://deploybot.example.com", site = "my-site" );

					expect( fileRead( root & "/.env.production", "utf-8" ) ).toBe( "A=#secretValue#" );
					expect( lines.toList( chr( 10 ) ) ).toInclude( ".env.production already exists" );
				} );

				it( "warns when there is no .env.example", function(){
					setup.run( root = root, url = "https://deploybot.example.com", site = "my-site" );
					expect( fileExists( root & "/.env.production" ) ).toBeFalse();
					expect( lines.toList( chr( 10 ) ) ).toInclude( "There is no .env.example" );
				} );
			} );

			describe( "token", function(){
				it( "reports whether a token is saved", function(){
					expect( setup.run( root = root, url = "https://deploybot.example.com", site = "my-site" ).tokenSaved ).toBeFalse();
					tokenStore.set( "deploybot.example.com", "my-site", secretToken );
					expect( setup.run( root = root, url = "https://deploybot.example.com", site = "my-site" ).tokenSaved ).toBeTrue();
				} );
			} );

			describe( "secrets", function(){
				it( "never prints a value from .env.example or the env file", function(){
					writeText( root & "/.env.example", "A=#secretValue#" & chr( 10 ) & "B=#secretValue#" );
					setup.run( root = root, url = "https://deploybot.example.com", site = "my-site" );
					writeText( root & "/.env.production", "A=#secretValue#" );
					setup.run( root = root, url = "https://deploybot.example.com", site = "my-site" );
					setup.printNextSteps( loadConfig( root ) );

					expect( lines.toList( chr( 10 ) ) ).notToInclude( secretValue );
				} );
			} );
		} );
	}
}
