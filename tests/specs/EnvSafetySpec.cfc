/** Checks the warnings about where the env file lives: git and cloud-synced folders. */
component extends="tests.support.BaseSpec" {

	function run(){
		describe( "EnvSafety", function(){
			beforeEach( function(){
				root   = createTempProject();
				lines  = [];
				writeBoxJson( root );
				safety = prepareMock( model( "EnvSafety" ) );
				safety.$property( propertyName = "print", propertyScope = "variables", mock = createRecordingPrinter( lines ) );
			} );

			afterEach( function(){
				deleteDirectory( root );
			} );

			describe( "synced folders", function(){
				it( "names the service that syncs a path", function(){
					expect( safety.syncedBy( "D:\Dropbox\Repositories\site\.env.production" ) ).toBe( "Dropbox" );
					expect( safety.syncedBy( "C:/Users/me/Dropbox (Personal)/site/.env.production" ) ).toBe( "Dropbox" );
					expect( safety.syncedBy( "C:\Users\me\OneDrive - Contoso\site\.env.production" ) ).toBe( "OneDrive" );
					expect( safety.syncedBy( "C:\Users\me\iCloudDrive\site\.env.production" ) ).toBe( "iCloud Drive" );
					expect( safety.syncedBy( "/Users/me/Library/Mobile Documents/com~apple~CloudDocs/site/.env" ) ).toBe( "iCloud Drive" );
					expect( safety.syncedBy( "G:\My Drive\site\.env.production" ) ).toBe( "Google Drive" );
				} );

				it( "does not match a folder that only starts with a service name", function(){
					expect( safety.syncedBy( "C:\Code\dropboxer\site\.env.production" ) ).toBe( "" );
					expect( safety.syncedBy( "/home/me/sites/shop/.env.production" ) ).toBe( "" );
				} );
			} );

			describe( "git", function(){
				it( "says nothing for an ignored file outside a synced folder", function(){
					stubGit();
					safety.$( "syncedBy", "" );
					var result = safety.check( loadConfig( root ) );
					expect( result.tracked ).toBeFalse();
					expect( lines ).toBe( [] );
				} );

				it( "explains how to fix a tracked file", function(){
					stubGit( { tracked : true } );
					safety.$( "syncedBy", "" );
					expect( safety.check( loadConfig( root ) ).tracked ).toBeTrue();
					var output = lines.toList( chr( 10 ) );
					expect( output ).toInclude( ".env.production is tracked by git" );
					expect( output ).toInclude( "git rm --cached .env.production" );
				} );

				it( "warns about a file that .gitignore does not cover", function(){
					stubGit( { ignored : false } );
					safety.$( "syncedBy", "" );
					safety.check( loadConfig( root ) );
					expect( lines.toList( chr( 10 ) ) ).toInclude( "not covered by .gitignore" );
				} );

				it( "skips the git checks outside a repository or without git", function(){
					safety.$( "syncedBy", "" );
					stubGit( { repository : false, ignored : false } );
					safety.check( loadConfig( root ) );
					stubGit( { known : false, ignored : false } );
					safety.check( loadConfig( root ) );
					expect( lines ).toBe( [] );
				} );
			} );

			it( "warns about a synced folder and says how to move the file", function(){
				stubGit();
				safety.$( "syncedBy", "Dropbox" );
				expect( safety.check( loadConfig( root ) ).syncedBy ).toBe( "Dropbox" );
				var output = lines.toList( chr( 10 ) );
				expect( output ).toInclude( "is in a Dropbox folder" );
				expect( output ).toInclude( "deploybot.envFile" );
			} );
		} );
	}
}
